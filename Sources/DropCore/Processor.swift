import Foundation

/// The outcome of running an operation on a set of files.
public struct OperationResult: Equatable, Sendable {
  public var outputs: [URL] = []
  /// File name (or "" for the whole run) paired with a user-facing message.
  public var failures: [Failure] = []

  public struct Failure: Equatable, Sendable {
    public let file: String
    public let message: String
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
  public var settings: Settings

  public init(settings: Settings) {
    self.settings = settings
  }

  /// Checks that the inputs suit the operation. Returns a message if they do not.
  public static func validate(_ operation: FileOperation, files: [DroppedFile]) -> String? {
    if files.isEmpty { return "Drop some files first." }
    switch operation {
    case .convert, .stripMetadata, .imagesToPDF:
      if files.contains(where: { !$0.kind.isImage }) {
        return "\(operation.summary) works on images only (PNG, JPEG, HEIC, TIFF)."
      }
    case .mergePDFs:
      if files.contains(where: { $0.kind != .pdf }) { return "Merge PDFs works on PDF files only." }
      if files.count < 2 { return "Drop at least two PDFs to merge." }
    }
    return nil
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
        let target = claim(dir.appendingPathComponent(name).appendingPathExtension(file.url.pathExtension))
        record(&result, file: file, output: target) {
          try ImageOps.stripMetadata(file.url, destination: target)
        }
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
