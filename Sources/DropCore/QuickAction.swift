import Foundation

/// The common actions offered outside the wheel: Finder's Services menu and the
/// `--run` command line that Shortcuts can call. Each one maps onto existing
/// `FileOperation`s, so the conversion work itself stays in `Processor`.
public enum QuickAction: Equatable, Hashable, Sendable {
  case convertImage(ImageFormat)
  case convertAudio(AudioOutput)
  case convertVideo(VideoOutput)
  case convertDocument(DocumentOutput)
  /// Images and PDFs at the quality setting; videos at medium strength.
  case compress
  case resize(ResizeSpec)
  /// One PDF from images, or one merged PDF from PDFs.
  case makePDF

  /// Parses a spec such as `convert-image:png`, `resize:50%`, `resize:1920`,
  /// `compress` or `make-pdf`. Returns nil for anything else.
  public init?(spec: String) {
    let parts = spec.lowercased().split(separator: ":", maxSplits: 1).map(String.init)
    let verb = parts.first ?? ""
    let option = parts.count > 1 ? parts[1] : nil
    switch (verb, option) {
    case ("compress", nil): self = .compress
    case ("make-pdf", nil): self = .makePDF
    case ("convert-image", let id?):
      guard let format = ImageFormat(rawValue: id), format.isWritable else { return nil }
      self = .convertImage(format)
    case ("convert-audio", let id?):
      guard let output = AudioOutput(rawValue: id) else { return nil }
      self = .convertAudio(output)
    case ("convert-video", let id?):
      guard let output = VideoOutput(rawValue: id) else { return nil }
      self = .convertVideo(output)
    case ("convert-document", let id?):
      guard let output = DocumentOutput(rawValue: id) else { return nil }
      self = .convertDocument(output)
    case ("resize", let size?):
      if size.hasSuffix("%") {
        guard let percent = Double(size.dropLast()), ResizeSpec.percentRange.contains(percent) else {
          return nil
        }
        self = .resize(.percent(percent))
      } else {
        guard let edge = Int(size.hasSuffix("px") ? String(size.dropLast(2)) : size),
          ResizeSpec.edgeRange.contains(edge)
        else { return nil }
        self = .resize(.maxEdge(edge))
      }
    default: return nil
    }
  }

  /// The inverse of `init(spec:)`.
  public var spec: String {
    switch self {
    case .convertImage(let format): "convert-image:\(format.rawValue)"
    case .convertAudio(let output): "convert-audio:\(output.rawValue)"
    case .convertVideo(let output): "convert-video:\(output.rawValue)"
    case .convertDocument(let output): "convert-document:\(output.rawValue)"
    case .compress: "compress"
    case .resize(.percent(let p)): "resize:\(p.formatted(.number.precision(.fractionLength(0...2))))%"
    case .resize(.maxEdge(let edge)): "resize:\(edge)"
    case .makePDF: "make-pdf"
    }
  }

  /// A short name for history and notifications.
  public var title: String {
    switch self {
    case .convertImage(let format): "Convert to \(format.displayName)"
    case .convertAudio(let output): "Convert to \(output.displayName)"
    case .convertVideo(let output): "Convert to \(output.displayName)"
    case .convertDocument(let output): "Convert to \(output.displayName)"
    case .compress: "Compress"
    case .resize(let spec): "Resize to \(spec.summary)"
    case .makePDF: "Make PDF"
    }
  }

  /// Every spec form, for `--list` and help text.
  public static let specForms: [String] = [
    "convert-image:<" + ImageFormat.allCases.filter(\.isWritable).map(\.rawValue).joined(separator: "|")
      + ">",
    "convert-audio:<" + AudioOutput.allCases.map(\.rawValue).joined(separator: "|") + ">",
    "convert-video:<" + VideoOutput.allCases.map(\.rawValue).joined(separator: "|") + ">",
    "convert-document:<" + DocumentOutput.allCases.map(\.rawValue).joined(separator: "|") + ">",
    "compress",
    "resize:<percent>% | resize:<longest edge in px>",
    "make-pdf",
  ]

  /// One operation on a group of the inputs.
  public struct Step: Equatable, Sendable {
    public let operation: FileOperation
    public let files: [DroppedFile]
  }

  /// Splits `files` into the operations that carry out this action. Files no step
  /// accepts come back in `rejected`, with a message.
  public func plan(
    for files: [DroppedFile], settings: AppSettings
  ) -> (steps: [Step], rejected: [OperationResult.Failure]) {
    let single: FileOperation
    switch self {
    case .convertImage(let format):
      single = .convert(format, quality: settings.quality(for: format.rawValue))
    case .convertAudio(let output): single = .convertAudio(output)
    case .convertVideo(let output): single = .convertVideo(output)
    case .convertDocument(let output): single = .convertDocument(output)
    case .resize(let spec): single = .resize(spec)
    case .makePDF:
      let allPDFs = !files.isEmpty && files.allSatisfy { $0.kind == .pdf }
      single = allPDFs ? .mergePDFs : .imagesToPDF
    case .compress:
      let stills = files.filter { $0.kind.isImage || $0.kind == .pdf }
      let videos = files.filter(\.kind.isVideo)
      var steps: [Step] = []
      if !stills.isEmpty {
        steps.append(Step(operation: .compress(quality: settings.quality), files: stills))
      }
      if !videos.isEmpty { steps.append(Step(operation: .compressVideo(.strength(.medium)), files: videos)) }
      let rejected = files.filter { !$0.kind.isImage && $0.kind != .pdf && !$0.kind.isVideo }
        .map { OperationResult.Failure(file: $0.name, message: "Compress works on images, PDFs and videos.") }
      return (steps, rejected)
    }
    return files.isEmpty ? ([], []) : ([Step(operation: single, files: files)], [])
  }
}

/// Runs a `QuickAction` on file URLs through the `JobEngine`.
public enum QuickActionRunner {
  /// Loads `urls`, plans the action, and runs each step as a `ProcessorJob`. Problems
  /// with single files, invalid steps and failed jobs all end up in `failures`.
  public static func run(
    _ action: QuickAction, on urls: [URL], settings: AppSettings, engine: JobEngine = .shared,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async -> OperationResult {
    var result = OperationResult()
    var files: [DroppedFile] = []
    for url in urls {
      do {
        files.append(try DroppedFile.load(url))
      } catch {
        result.failures.append(.init(file: url.lastPathComponent, message: error.localizedDescription))
      }
    }
    if urls.isEmpty { result.failures.append(.init(file: "", message: "No files were given.")) }

    let (steps, rejected) = action.plan(for: files, settings: settings)
    result.failures += rejected
    for (index, step) in steps.enumerated() {
      if let message = Processor.validate(step.operation, files: step.files) {
        result.failures.append(.init(file: "", message: message))
        continue
      }
      let handle = engine.submit(
        ProcessorJob(operation: step.operation, files: step.files, settings: settings))
      if let progress {
        let count = Double(steps.count)
        handle.observe { state in
          if case .running(let fraction) = state { progress((Double(index) + fraction) / count) }
        }
      }
      // Cancelling the caller's task cancels the job too.
      _ = await withTaskCancellationHandler {
        await handle.result()
      } onCancel: {
        handle.cancel()
      }
      switch handle.state {
      case .finished(let stepResult):
        result.outputs += stepResult.outputs
        result.failures += stepResult.failures
        result.notes += stepResult.notes
      case .failed(let message):
        result.failures.append(.init(file: "", message: message))
      case .cancelled:
        result.failures.append(.init(file: "", message: "\(step.operation.summary) was cancelled."))
      default:
        break
      }
    }
    return result
  }
}

/// The `--run` command line: `FileDropUtility --run <action> [--out <folder>] <file>…`.
public struct QuickActionCommand: Equatable, Sendable {
  public let action: QuickAction
  public let files: [URL]
  public let outputFolder: URL?

  /// Returns nil when `arguments` (the full argv) has no `--run`; throws a usage
  /// message when it has one but the rest is wrong.
  public static func parse(_ arguments: [String], currentDirectory: URL) throws -> QuickActionCommand? {
    guard let runIndex = arguments.firstIndex(of: "--run") else { return nil }
    var rest = Array(arguments[(runIndex + 1)...])
    guard !rest.isEmpty else { throw DropError.wrongInput(usage) }
    let spec = rest.removeFirst()
    guard let action = QuickAction(spec: spec) else {
      throw DropError.wrongInput("Unknown action \"\(spec)\".\n\(usage)")
    }
    var files: [URL] = []
    var outputFolder: URL?
    while !rest.isEmpty {
      let argument = rest.removeFirst()
      if argument == "--out" {
        guard !rest.isEmpty else { throw DropError.wrongInput("--out needs a folder.\n\(usage)") }
        outputFolder =
          URL(fileURLWithPath: rest.removeFirst(), relativeTo: currentDirectory).standardizedFileURL
      } else {
        files.append(URL(fileURLWithPath: argument, relativeTo: currentDirectory).standardizedFileURL)
      }
    }
    guard !files.isEmpty else { throw DropError.wrongInput("Give at least one file.\n\(usage)") }
    return QuickActionCommand(action: action, files: files, outputFolder: outputFolder)
  }

  public static var usage: String {
    "Usage: FileDropUtility --run <action> [--out <folder>] <file>…\nActions:\n"
      + QuickAction.specForms.map { "  " + $0 }.joined(separator: "\n")
  }
}
