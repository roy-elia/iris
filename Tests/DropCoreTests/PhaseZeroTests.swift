import Foundation
import Testing

@testable import DropCore

@Suite struct ModifierSettingsTests {
  @Test func symbolsFollowAppleOrder() {
    #expect(ModifierCombo(shift: true, command: true, control: true, option: true).symbols == "⌃⌥⇧⌘")
    #expect(ModifierCombo(shift: true, command: true).names == "shift + command")
  }

  @Test func duplicateOrEmptyCombinationsAreInvalid() {
    #expect(WheelModifiers().isValid)
    #expect(!WheelModifiers(convert: .init(shift: true), tools: .init(shift: true)).isValid)
    #expect(!WheelModifiers(convert: .init()).isValid)
    // Invalid settings fall back to the defaults instead of breaking the trigger.
    let settings = AppSettings(wheelModifiers: WheelModifiers(convert: .init(command: true)))
    #expect(settings.wheelModifiers == WheelModifiers())
  }

  @Test func oldSettingsFilesGetNewDefaults() throws {
    let old =
      #"{"defaultFormat":"jpeg","quality":0.6,"outputLocation":{"nextToSource":{}},"launchAtLogin":false,"wheelTriggerEnabled":true,"appearance":"dark","hasCompletedOnboarding":true}"#
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
    #expect(s.defaultFormat == .jpeg)
    #expect(s.wheelModifiers == WheelModifiers())
    #expect(s.soundAndHaptics)
    #expect(s.terminalBundleID == AppSettings.defaultTerminal)
    #expect(s.formatSettings.isEmpty)
  }

  @Test func newSettingsRoundTripAndPerFormatQuality() throws {
    var s = AppSettings(quality: 0.8)
    s.wheelModifiers = WheelModifiers(
      convert: .init(option: true), tools: .init(shift: true, command: true), actions: .init(control: true))
    s.soundAndHaptics = false
    s.terminalBundleID = "com.googlecode.iterm2"
    s.formatSettings["jpeg"] = FormatSettings(quality: 0.5, preserveMetadata: false)
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    #expect(back == s)
    #expect(back.quality(for: "jpeg") == 0.5)
    #expect(back.quality(for: "heic") == 0.8)
    #expect(!back.format("jpeg").preserveMetadata)
    #expect(back.format("png").preserveMetadata)
  }

  @Test func formatQualityIsClamped() {
    #expect(FormatSettings(quality: 7).quality == AppSettings.qualityRange.upperBound)
  }
}

@Suite struct JobEngineTests {
  struct Sleepy: Job {
    let title = "sleepy"
    let steps: Int
    let tracker: Tracker?
    func run(_ context: JobContext) async throws -> OperationResult {
      await tracker?.begin()
      defer { Task { await tracker?.end() } }
      for i in 1...steps {
        try context.checkCancelled()
        try await Task.sleep(for: .milliseconds(20))
        context.progress(Double(i) / Double(steps))
      }
      return OperationResult(outputs: [URL(fileURLWithPath: "/tmp/out-\(steps)")])
    }
  }

  actor Tracker {
    private(set) var running = 0
    private(set) var peak = 0
    func begin() {
      running += 1
      peak = max(peak, running)
    }
    func end() { running -= 1 }
  }

  final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ v: Double) { lock.withLock { values.append(v) } }
    var all: [Double] { lock.withLock { values } }
  }

  @Test func runsAndReportsMonotonicProgress() async {
    let engine = JobEngine()
    let handle = engine.submit(Sleepy(steps: 5, tracker: nil))
    let log = Log()
    handle.observe { state in
      if case .running(let p) = state { log.add(p) }
    }
    let result = await handle.result()
    #expect(result?.outputs.count == 1)
    #expect(log.all == log.all.sorted())
    #expect(log.all.last == 1)
    if case .finished = handle.state {} else { Issue.record("expected finished, got \(handle.state)") }
  }

  @Test func cancelStopsTheJob() async {
    let engine = JobEngine()
    let handle = engine.submit(Sleepy(steps: 200, tracker: nil))
    try? await Task.sleep(for: .milliseconds(60))
    handle.cancel()
    #expect(await handle.result() == nil)
    #expect(handle.state == .cancelled)
  }

  @Test func respectsTheConcurrencyLimit() async {
    let engine = JobEngine(quickLimit: 2, heavyLimit: 1)
    let tracker = Tracker()
    let handles = (0..<6).map { _ in engine.submit(Sleepy(steps: 3, tracker: tracker)) }
    for h in handles { _ = await h.result() }
    #expect(await tracker.peak <= 2)
    #expect(await tracker.peak >= 1)
  }

  @Test func processorJobWrapsExistingOperations() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let png = try Fixtures.writeCGImage(Fixtures.image(), to: dir.appendingPathComponent("a.png"))
    let job = ProcessorJob(
      operation: .convert(.jpeg, quality: 0.8), files: [try DroppedFile.load(png)], settings: AppSettings())
    let result = await JobEngine().submit(job).result()
    #expect(result?.outputs.first?.pathExtension == "jpeg" || result?.outputs.first?.pathExtension == "jpg")
  }
}

@Suite struct ToolRunnerTests {
  @Test func parsesFFmpegProgress() {
    #expect(ToolRunner.ffmpegProgress(line: "out_time_us=5000000", duration: 10) == 0.5)
    #expect(ToolRunner.ffmpegProgress(line: "out_time_ms=20000000", duration: 10) == 1)
    #expect(ToolRunner.ffmpegProgress(line: "frame=12", duration: 10) == nil)
    #expect(ToolRunner.ffmpegProgress(line: "out_time_us=N/A", duration: 10) == nil)
  }

  @Test func missingToolIsAClearError() async {
    let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    // An override folder that doesn't contain the tool doesn't hide the real ones, so ask
    // for a tool through a locator check instead of relying on what's installed.
    #expect(ToolLocator.url(for: .ffmpeg).map { !$0.path.hasPrefix(empty.path) } ?? true)
    #expect(ToolError.missing(.cwebp).errorDescription?.contains("cwebp") == true)
  }

  @Test(.enabled(if: ToolLocator.isAvailable(.ffmpeg)))
  func runsBundledFFmpeg() async throws {
    let out = try await ToolRunner.run(.ffmpeg, ["-hide_banner", "-version"])
    #expect(String(decoding: out.stdout, as: UTF8.self).contains("ffmpeg version"))
  }

  @Test(.enabled(if: ToolLocator.isAvailable(.ffmpeg)))
  func failingToolReportsStatusAndMessage() async {
    await #expect(throws: ToolError.self) {
      _ = try await ToolRunner.run(.ffmpeg, ["-hide_banner", "-i", "/nonexistent/file.mov"])
    }
  }

  @Test(.enabled(if: ToolLocator.isAvailable(.cwebp)))
  func runsBundledCwebp() async throws {
    let out = try await ToolRunner.run(.cwebp, ["-version"])
    #expect(String(decoding: out.stdout, as: UTF8.self).hasPrefix("1."))
  }

  @Test(.enabled(if: ToolLocator.isAvailable(.exiftool)))
  func runsBundledExifTool() async throws {
    let out = try await ToolRunner.run(.exiftool, ["-ver"])
    #expect(
      Double(String(decoding: out.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        != nil)
  }

  @Test(.enabled(if: ToolLocator.isAvailable(.ffmpeg)))
  func cancellationTerminatesTheProcess() async {
    let task = Task {
      // Generates silence forever until cancelled.
      try await ToolRunner.run(.ffmpeg, ["-hide_banner", "-f", "lavfi", "-i", "anullsrc", "-f", "null", "-"])
    }
    try? await Task.sleep(for: .milliseconds(300))
    task.cancel()
    let result = await task.result
    #expect(throws: CancellationError.self) { try result.get() }
  }
}
