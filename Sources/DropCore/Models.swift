import Foundation

/// Image formats the app can read and write.
public enum ImageFormat: String, CaseIterable, Codable, Sendable {
  case png, jpeg, heic, tiff

  public var fileExtension: String {
    switch self {
    case .png: "png"
    case .jpeg: "jpg"
    case .heic: "heic"
    case .tiff: "tiff"
    }
  }

  /// Uniform type identifier used by ImageIO.
  public var typeIdentifier: String {
    switch self {
    case .png: "public.png"
    case .jpeg: "public.jpeg"
    case .heic: "public.heic"
    case .tiff: "public.tiff"
    }
  }

  public var displayName: String {
    switch self {
    case .png: "PNG"
    case .jpeg: "JPEG"
    case .heic: "HEIC"
    case .tiff: "TIFF"
    }
  }

  /// Whether the format takes a lossy quality setting.
  public var usesQuality: Bool { self == .jpeg || self == .heic }

  public init?(fileExtension ext: String) {
    switch ext.lowercased() {
    case "png": self = .png
    case "jpg", "jpeg": self = .jpeg
    case "heic", "heif": self = .heic
    case "tif", "tiff": self = .tiff
    default: return nil
    }
  }
}

/// What a dropped file is, as far as the app's operations are concerned.
public enum FileKind: Equatable, Sendable {
  case image(ImageFormat)
  case pdf
  case unsupported

  public init(url: URL) {
    let ext = url.pathExtension
    if let format = ImageFormat(fileExtension: ext) {
      self = .image(format)
    } else if ext.lowercased() == "pdf" {
      self = .pdf
    } else {
      self = .unsupported
    }
  }

  public var isImage: Bool {
    if case .image = self { return true }
    return false
  }
}

/// A file queued in the drop panel.
public struct DroppedFile: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let url: URL
  public let kind: FileKind
  public let byteSize: Int64

  public var name: String { url.lastPathComponent }

  public init(id: UUID = UUID(), url: URL, kind: FileKind, byteSize: Int64) {
    self.id = id
    self.url = url
    self.kind = kind
    self.byteSize = byteSize
  }

  /// Reads the file's kind and size. Throws if the path is missing, is a directory, or
  /// is a type the app does not handle.
  public static func load(_ url: URL, fileManager: FileManager = .default) throws -> DroppedFile {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      throw DropError.fileNotFound(url.lastPathComponent)
    }
    guard !isDirectory.boolValue else {
      throw DropError.unsupportedFile(url.lastPathComponent)
    }
    let kind = FileKind(url: url)
    guard kind != .unsupported else {
      throw DropError.unsupportedFile(url.lastPathComponent)
    }
    let attributes = try? fileManager.attributesOfItem(atPath: url.path)
    let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    return DroppedFile(url: url, kind: kind, byteSize: size)
  }
}

/// An action the user can run on the queued files.
public enum FileOperation: Codable, Equatable, Sendable {
  case convert(ImageFormat, quality: Double)
  case stripMetadata
  case mergePDFs
  case imagesToPDF

  public var summary: String {
    switch self {
    case .convert(let format, _): "Convert to \(format.displayName)"
    case .stripMetadata: "Strip metadata"
    case .mergePDFs: "Merge PDFs"
    case .imagesToPDF: "Images to PDF"
    }
  }
}

/// Where outputs are written.
public enum OutputLocation: Codable, Equatable, Sendable {
  case nextToSource
  case folder(URL)
}

/// User preferences, persisted between launches.
public struct Settings: Codable, Equatable, Sendable {
  public static let qualityRange: ClosedRange<Double> = 0.1...1.0

  public var defaultFormat: ImageFormat
  public var quality: Double {
    didSet { quality = Self.clampQuality(quality) }
  }
  public var outputLocation: OutputLocation
  public var launchAtLogin: Bool

  public init(
    defaultFormat: ImageFormat = .png,
    quality: Double = 0.85,
    outputLocation: OutputLocation = .nextToSource,
    launchAtLogin: Bool = false
  ) {
    self.defaultFormat = defaultFormat
    self.quality = Self.clampQuality(quality)
    self.outputLocation = outputLocation
    self.launchAtLogin = launchAtLogin
  }

  public static func clampQuality(_ value: Double) -> Double {
    guard value.isFinite else { return 0.85 }
    return min(max(value, qualityRange.lowerBound), qualityRange.upperBound)
  }

  public init(from decoder: any Decoder) throws {
    let defaults = Settings()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    defaultFormat = (try? c.decode(ImageFormat.self, forKey: .defaultFormat)) ?? defaults.defaultFormat
    quality = Self.clampQuality((try? c.decode(Double.self, forKey: .quality)) ?? defaults.quality)
    outputLocation =
      (try? c.decode(OutputLocation.self, forKey: .outputLocation)) ?? defaults.outputLocation
    launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? defaults.launchAtLogin
  }
}

/// One recorded run of an operation.
public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let date: Date
  public let operation: String
  public let inputCount: Int
  public let outputs: [String]
  public let errors: [String]

  public var succeeded: Bool { errors.isEmpty && !outputs.isEmpty }

  public init(
    id: UUID = UUID(), date: Date = Date(), operation: String, inputCount: Int,
    outputs: [String], errors: [String]
  ) {
    self.id = id
    self.date = date
    self.operation = operation
    self.inputCount = inputCount
    self.outputs = outputs
    self.errors = errors
  }
}

/// Errors shown to the user. Messages are written for the panel, not for logs.
public enum DropError: Error, Equatable, LocalizedError, Sendable {
  case fileNotFound(String)
  case unsupportedFile(String)
  case wrongInput(String)
  case readFailed(String)
  case writeFailed(String)

  public var errorDescription: String? {
    switch self {
    case .fileNotFound(let name): "\(name) could not be found."
    case .unsupportedFile(let name): "\(name) is not a supported file type."
    case .wrongInput(let message): message
    case .readFailed(let name): "\(name) could not be read."
    case .writeFailed(let name): "\(name) could not be written."
    }
  }
}
