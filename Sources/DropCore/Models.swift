import Foundation

/// Image formats the app can read. All but WebP can also be written.
public enum ImageFormat: String, CaseIterable, Codable, Sendable {
  case png, jpeg, heic, avif, tiff, bmp, webp

  /// Formats ImageIO can encode on macOS. WebP is read-only: macOS has no WebP encoder.
  public static var writable: [ImageFormat] { allCases.filter(\.isWritable) }

  public var isWritable: Bool { self != .webp }

  public var fileExtension: String {
    switch self {
    case .png: "png"
    case .jpeg: "jpg"
    case .heic: "heic"
    case .avif: "avif"
    case .tiff: "tiff"
    case .bmp: "bmp"
    case .webp: "webp"
    }
  }

  /// Uniform type identifier used by ImageIO.
  public var typeIdentifier: String {
    switch self {
    case .png: "public.png"
    case .jpeg: "public.jpeg"
    case .heic: "public.heic"
    case .avif: "public.avif"
    case .tiff: "public.tiff"
    case .bmp: "com.microsoft.bmp"
    case .webp: "org.webmproject.webp"
    }
  }

  public var displayName: String {
    switch self {
    case .png: "PNG"
    case .jpeg: "JPEG"
    case .heic: "HEIC"
    case .avif: "AVIF"
    case .tiff: "TIFF"
    case .bmp: "BMP"
    case .webp: "WebP"
    }
  }

  /// Whether the format takes a lossy quality setting.
  public var usesQuality: Bool { self == .jpeg || self == .heic || self == .avif }

  /// Whether the format can store transparency.
  public var supportsAlpha: Bool { self != .jpeg && self != .bmp }

  public init?(fileExtension ext: String) {
    switch ext.lowercased() {
    case "png": self = .png
    case "jpg", "jpeg": self = .jpeg
    case "heic", "heif": self = .heic
    case "avif": self = .avif
    case "tif", "tiff": self = .tiff
    case "bmp": self = .bmp
    case "webp": self = .webp
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
  case compress(quality: Double)
  case replaceBackground(BackgroundFill)
  case edit(EditRecipe)

  public var summary: String {
    switch self {
    case .convert(let format, _): "Convert to \(format.displayName)"
    case .stripMetadata: "Strip metadata"
    case .mergePDFs: "Merge PDFs"
    case .imagesToPDF: "Images to PDF"
    case .compress: "Compress"
    case .replaceBackground(.transparent): "Remove background"
    case .replaceBackground(.color): "Replace background"
    case .edit: "Edit image"
    }
  }
}

/// What goes behind the subject when the background is replaced.
public enum BackgroundFill: Codable, Equatable, Sendable {
  case transparent
  case color(RGBA)
}

/// A colour with components in 0...1.
public struct RGBA: Codable, Equatable, Hashable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public static let white = RGBA(red: 1, green: 1, blue: 1)
  public static let black = RGBA(red: 0, green: 0, blue: 0)
}

/// Light/dark override. `system` follows macOS.
public enum AppearancePreference: String, Codable, CaseIterable, Sendable {
  case system, light, dark
}

/// Where outputs are written.
public enum OutputLocation: Codable, Equatable, Sendable {
  case nextToSource
  case folder(URL)
}

/// User preferences, persisted between launches.
public struct AppSettings: Codable, Equatable, Sendable {
  public static let qualityRange: ClosedRange<Double> = 0.1...1.0

  public var defaultFormat: ImageFormat
  public var quality: Double {
    didSet { quality = Self.clampQuality(quality) }
  }
  public var outputLocation: OutputLocation
  public var launchAtLogin: Bool
  /// Holding Shift, Command or Control while dragging files opens an action wheel.
  public var wheelTriggerEnabled: Bool
  public var appearance: AppearancePreference
  public var hasCompletedOnboarding: Bool

  public init(
    defaultFormat: ImageFormat = .png,
    quality: Double = 0.85,
    outputLocation: OutputLocation = .nextToSource,
    launchAtLogin: Bool = false,
    wheelTriggerEnabled: Bool = true,
    appearance: AppearancePreference = .system,
    hasCompletedOnboarding: Bool = false
  ) {
    self.defaultFormat = defaultFormat.isWritable ? defaultFormat : .png
    self.quality = Self.clampQuality(quality)
    self.outputLocation = outputLocation
    self.launchAtLogin = launchAtLogin
    self.wheelTriggerEnabled = wheelTriggerEnabled
    self.appearance = appearance
    self.hasCompletedOnboarding = hasCompletedOnboarding
  }

  public static func clampQuality(_ value: Double) -> Double {
    guard value.isFinite else { return 0.85 }
    return min(max(value, qualityRange.lowerBound), qualityRange.upperBound)
  }

  public init(from decoder: any Decoder) throws {
    let defaults = AppSettings()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let format = (try? c.decode(ImageFormat.self, forKey: .defaultFormat)) ?? defaults.defaultFormat
    defaultFormat = format.isWritable ? format : defaults.defaultFormat
    quality = Self.clampQuality((try? c.decode(Double.self, forKey: .quality)) ?? defaults.quality)
    outputLocation =
      (try? c.decode(OutputLocation.self, forKey: .outputLocation)) ?? defaults.outputLocation
    launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? defaults.launchAtLogin
    wheelTriggerEnabled =
      (try? c.decode(Bool.self, forKey: .wheelTriggerEnabled)) ?? defaults.wheelTriggerEnabled
    appearance = (try? c.decode(AppearancePreference.self, forKey: .appearance)) ?? defaults.appearance
    hasCompletedOnboarding =
      (try? c.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? defaults.hasCompletedOnboarding
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
  case notSmaller(String)
  case noSubject(String)

  public var errorDescription: String? {
    switch self {
    case .fileNotFound(let name): "\(name) could not be found."
    case .unsupportedFile(let name): "\(name) is not a supported file type."
    case .wrongInput(let message): message
    case .readFailed(let name): "\(name) could not be read."
    case .writeFailed(let name): "\(name) could not be written."
    case .notSmaller(let name): "\(name) is already as small as it gets."
    case .noSubject(let name): "No clear subject was found in \(name)."
    }
  }
}
