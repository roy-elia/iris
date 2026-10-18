import Foundation

/// The outcome of running an operation on a set of files.
public struct OperationResult: Equatable, Sendable {
  public var outputs: [URL] = []
  /// File name (or "" for the whole run) paired with a user-facing message.
  public var failures: [Failure] = []

  public struct Failure: Equatable, Sendable {
    public let file: String
    public let message: String

    public init(file: String, message: String) {
      self.file = file
      self.message = message
    }
  }

  public init(outputs: [URL] = [], failures: [Failure] = []) {
    self.outputs = outputs
    self.failures = failures
  }

  public var succeeded: Bool { failures.isEmpty && !outputs.isEmpty }

  public func historyEntry(for operation: FileOperation, inputCount: Int) -> HistoryEntry {
    HistoryEntry(
      operation: operation.summary,
      inputCount: inputCount,
      outputs: outputs.map(\.lastPathComponent),
      errors: failures.map { $0.file.isEmpty ? $0.message : "\($0.file): \($0.message)" })
  }
}

/// Runs operations on dropped files. Never overwrites existing files.
public struct Processor: Sendable {
  public var settings: AppSettings

  public init(settings: AppSettings) {
    self.settings = settings
  }

  /// Checks that the inputs suit the operation. Returns a message if they do not.
  public static func validate(_ operation: FileOperation, files: [DroppedFile]) -> String? {
    if files.isEmpty { return "Drop some files first." }
    switch operation {
    case .convert(let format, _):
      if !format.isWritable { return "macOS can't write \(format.displayName) files." }
      if files.contains(where: { !$0.kind.isImage }) { return imagesOnly(operation) }
    case .stripMetadata, .imagesToPDF, .replaceBackground:
      if files.contains(where: { !$0.kind.isImage }) { return imagesOnly(operation) }
    case .edit:
      if files.count != 1 || !files[0].kind.isImage { return "Edit works on one image at a time." }
    case .compress:
      if files.contains(where: { $0.kind == .unsupported }) { return "Compress works on images and PDFs." }
    case .mergePDFs:
      if files.contains(where: { $0.kind != .pdf }) { return "Merge PDFs works on PDF files only." }
      if files.count < 2 { return "Drop at least two PDFs to merge." }
    }
    return nil
  }

  private static func imagesOnly(_ operation: FileOperation) -> String {
    let names = ImageFormat.allCases.map(\.displayName).joined(separator: ", ")
    return "\(operation.summary) works on images only (\(names))."
  }

  /// Runs `operation`. Per-file operations keep going past individual failures.
  public func run(_ operation: FileOperation, on files: [DroppedFile]) -> OperationResult {
    var result = OperationResult()
    if let message = Self.validate(operation, files: files) {
      result.failures.append(.init(file: "", message: message))
      return result
    }

    var reserved: Set<URL> = []
    func claim(_ desired: URL) -> URL {
      let url = OutputNamer.uniqueURL(for: desired, reserved: reserved)
      reserved.insert(url.standardizedFileURL)
      return url
    }

    switch operation {
    case .convert(let format, let quality):
      for file in files {
        let dir = outputDirectory(for: file.url)
        let base = file.url.deletingPathExtension().lastPathComponent
        let target = claim(dir.appendingPathComponent(base).appendingPathExtension(format.fileExtension))
        record(&result, file: file, output: target) {
          try ImageOps.convert(file.url, to: format, quality: quality, destination: target)
        }
      }

    case .stripMetadata:
      for file in files {
        let dir = outputDirectory(for: file.url)
        let base = file.url.deletingPathExtension().lastPathComponent
        let name = "\(base) no-metadata"
        // Read-only formats (WebP) come out as PNG.
        let writable = ImageFormat(fileExtension: file.url.pathExtension)?.isWritable ?? false
        let ext = writable ? file.url.pathExtension : "png"
        let target = claim(dir.appendingPathComponent(name).appendingPathExtension(ext))
        record(&result, file: file, output: target) {
          try ImageOps.stripMetadata(file.url, destination: target)
        }
      }

    case .compress(let quality):
      for file in files {
        let dir = outputDirectory(for: file.url)
        let base = file.url.deletingPathExtension().lastPathComponent
        let ext = CompressOps.outputExtension(for: file.url, kind: file.kind)
        let target = claim(dir.appendingPathComponent("\(base) compressed").appendingPathExtension(ext))
        record(&result, file: file, output: target) {
          try CompressOps.compress(file.url, kind: file.kind, quality: quality, destination: target)
        }
      }

    case .replaceBackground(let fill):
      for file in files {
        let dir = outputDirectory(for: file.url)
        let base = file.url.deletingPathExtension().lastPathComponent
        let ext = BackgroundOps.outputFormat(for: file.url, fill: fill).fileExtension
        let target = claim(dir.appendingPathComponent("\(base) no-bg").appendingPathExtension(ext))
        record(&result, file: file, output: target) {
          try BackgroundOps.replaceBackground(file.url, fill: fill, destination: target)
        }
      }

    case .edit(let recipe):
      let file = files[0]
      let base = file.url.deletingPathExtension().lastPathComponent
      let ext = EditOps.outputFormat(for: file.url).fileExtension
      let target = claim(
        outputDirectory(for: file.url).appendingPathComponent("\(base) edited").appendingPathExtension(ext))
      record(&result, file: file, output: target) {
        try EditOps.apply(file.url, recipe: recipe, destination: target)
      }

    case .mergePDFs:
      let target = claim(outputDirectory(for: files[0].url).appendingPathComponent("Merged.pdf"))
      record(&result, file: nil, output: target) {
        try PDFOps.merge(files.map(\.url), destination: target)
      }

    case .imagesToPDF:
      let base = files.count == 1 ? files[0].url.deletingPathExtension().lastPathComponent : "Images"
      let target = claim(outputDirectory(for: files[0].url).appendingPathComponent("\(base).pdf"))
      record(&result, file: nil, output: target) {
        try PDFOps.imagesToPDF(files.map(\.url), destination: target)
      }
    }
    return result
  }

  private func outputDirectory(for source: URL) -> URL {
    let dir = OutputNamer.directory(for: source, location: settings.outputLocation)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func record(
    _ result: inout OperationResult, file: DroppedFile?, output: URL, _ work: () throws -> Void
  ) {
    do {
      try work()
      result.outputs.append(output)
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      result.failures.append(.init(file: file?.name ?? "", message: message))
    }
  }
}
