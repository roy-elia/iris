import Foundation

/// A command-line helper shipped inside the app (see `scripts/fetch-tools.sh`).
public enum BundledTool: String, CaseIterable, Sendable {
  case ffmpeg, ffprobe, cwebp, exiftool
  /// Monkey's Audio's encoder.
  case mac

  /// Path of the tool relative to a tools folder.
  var relativePath: String {
    self == .exiftool ? "exiftool/exiftool" : rawValue
  }
}

/// Finds the bundled tools: an override folder (tests), the app's `Contents/Helpers`
/// (binaries) and `Contents/Resources` (ExifTool), or the repository's `Vendor/out` when
/// running from a build folder.
public enum ToolLocator {
  /// Set by tests or debugging to point at another tools folder.
  nonisolated(unsafe) public static var overrideDirectory: URL?

  public static func url(for tool: BundledTool) -> URL? {
    candidates().map { $0.appendingPathComponent(tool.relativePath) }
      .first { FileManager.default.fileExists(atPath: $0.path) }
  }

  public static func isAvailable(_ tool: BundledTool) -> Bool { url(for: tool) != nil }

  private static func candidates() -> [URL] {
    var dirs: [URL] = []
    if let overrideDirectory { dirs.append(overrideDirectory) }
    dirs.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers"))
    dirs.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
    #if DEBUG
      // Development: <repo>/Vendor/out, found from this source file's location.
      let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
      dirs.append(repo.appendingPathComponent("Vendor/out"))
      dirs.append(repo.appendingPathComponent("Vendor/out/bin"))
    #endif
    return dirs
  }
}

public enum ToolError: Error, Equatable, LocalizedError {
  case missing(BundledTool)
  case failed(BundledTool, status: Int32, message: String)

  public var errorDescription: String? {
    switch self {
    case .missing(let tool): "The bundled \(tool.rawValue) tool is missing. Reinstall the app."
    case .failed(let tool, let status, let message):
      "\(tool.rawValue) failed (\(status)): \(message.isEmpty ? "no details" : message)"
    }
  }
}

/// Runs a bundled tool as a child process. Cancelling the calling task terminates it.
public enum ToolRunner {
  public struct Output: Sendable {
    public let stdout: Data
    public let stderr: String
  }

  /// - Parameter onStderrLine: called for each line the tool writes to stderr, for
  ///   progress parsing. Called on a background queue.
  public static func run(
    _ tool: BundledTool, _ arguments: [String], onStderrLine: (@Sendable (String) -> Void)? = nil
  ) async throws -> Output {
    guard let url = ToolLocator.url(for: tool) else { throw ToolError.missing(tool) }
    let process = Process()
    if tool == .exiftool {
      // ExifTool is a Perl script; macOS ships /usr/bin/perl.
      process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
      process.arguments = [url.path] + arguments
    } else {
      process.executableURL = url
      process.arguments = arguments
    }
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    process.standardInput = FileHandle.nullDevice

    let collector = OutputCollector(onStderrLine: onStderrLine)

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
        // The result is ready only when both pipes have reached end-of-file and the process
        // has exited; output read after the exit is never dropped.
        let group = DispatchGroup()
        PipeReader.drain(outPipe, group: group) { collector.appendOut($0) }
        PipeReader.drain(errPipe, group: group) { collector.appendErr($0) }
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        do {
          try process.run()
        } catch {
          // No child holds the write ends, so close ours to end the readers.
          try? outPipe.fileHandleForWriting.close()
          try? errPipe.fileHandleForWriting.close()
          group.leave()
          group.notify(queue: .global()) { continuation.resume(throwing: error) }
          return
        }
        // A cancel that arrived before the launch found no process to stop, so stop it now.
        if collector.wasCancelled { process.terminate() }
        group.notify(queue: .global()) {
          let output = collector.output()
          // ffmpeg traps SIGTERM and exits normally, so check whether we asked it to stop.
          if collector.wasCancelled || process.terminationReason == .uncaughtSignal {
            continuation.resume(throwing: CancellationError())
          } else if process.terminationStatus != 0 {
            let lastLines = output.stderr.split(separator: "\n").suffix(3).joined(separator: " ")
            continuation.resume(
              throwing: ToolError.failed(tool, status: process.terminationStatus, message: lastLines))
          } else {
            continuation.resume(returning: output)
          }
        }
      }
    } onCancel: {
      collector.markCancelled()
      if process.isRunning { process.terminate() }
    }
  }

  /// Reads ffmpeg's `-progress pipe:2` output (`out_time_us=…`) as a 0…1 fraction.
  public static func ffmpegProgress(line: String, duration: Double) -> Double? {
    guard duration > 0, line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") else { return nil }
    guard let micros = Double(line.split(separator: "=").last ?? "") else { return nil }
    // ffmpeg reports out_time_ms in microseconds too (a long-standing naming quirk).
    return min(max(micros / 1_000_000 / duration, 0), 1)
  }
}

/// Reads a pipe to end-of-file on its own thread. Blocking reads stay off GCD's worker
/// threads, which are limited (64) and needed by system frameworks such as ImageIO's encoders.
enum PipeReader {
  static func drain(_ pipe: Pipe, group: DispatchGroup, onChunk: @escaping @Sendable (Data) -> Void) {
    group.enter()
    let handle = pipe.fileHandleForReading
    let thread = Thread {
      while true {
        let chunk = handle.availableData
        if chunk.isEmpty { break }
        onChunk(chunk)
      }
      group.leave()
    }
    thread.name = "FileDropUtility pipe reader"
    thread.start()
  }
}

/// Thread-safe accumulation of a child process's output.
private final class OutputCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var out = Data()
  private var err = Data()
  private var pendingLine = ""
  private var cancelled = false
  private let onStderrLine: (@Sendable (String) -> Void)?

  init(onStderrLine: (@Sendable (String) -> Void)?) { self.onStderrLine = onStderrLine }

  func appendOut(_ data: Data) {
    guard !data.isEmpty else { return }
    lock.withLock { out.append(data) }
  }

  func appendErr(_ data: Data) {
    guard !data.isEmpty else { return }
    let lines: [String] = lock.withLock {
      err.append(data)
      pendingLine += String(decoding: data, as: UTF8.self)
      var parts = pendingLine.components(separatedBy: .newlines)
      pendingLine = parts.removeLast()
      return parts
    }
    if let onStderrLine { lines.forEach(onStderrLine) }
  }

  func markCancelled() { lock.withLock { cancelled = true } }
  var wasCancelled: Bool { lock.withLock { cancelled } }

  func output() -> ToolRunner.Output {
    lock.withLock { ToolRunner.Output(stdout: out, stderr: String(decoding: err, as: UTF8.self)) }
  }
}
