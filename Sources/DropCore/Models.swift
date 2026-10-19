import Foundation

/// Image formats the app can read. SVG is read-only; WebP is written with the bundled
/// `cwebp`; everything else goes through ImageIO.
public enum ImageFormat: String, CaseIterable, Codable, Sendable {
  case png, jpeg, heic, avif, tiff, bmp, webp, gif, svg

  /// Formats the app can write right now.
  public static var writable: [ImageFormat] { allCases.filter(\.isWritable) }

  public var isWritable: Bool {
    switch self {
    case .svg: false
    case .webp: ToolLocator.isAvailable(.cwebp)
    default: true
    }
  }

  /// Written by ImageIO (as opposed to a bundled tool).
  public var isImageIOWritable: Bool { self != .svg && self != .webp }

  public var fileExtension: String {
    switch self {
    case .png: "png"
    case .jpeg: "jpg"
    case .heic: "heic"
    case .avif: "avif"
    case .tiff: "tiff"
    case .bmp: "bmp"
    case .webp: "webp"
    case .gif: "gif"
    case .svg: "svg"
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
    case .gif: "com.compuserve.gif"
    case .svg: "public.svg-image"
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
    case .gif: "GIF"
    case .svg: "SVG"
    }
  }

  /// Whether the format takes a lossy quality setting.
  public var usesQuality: Bool { self == .jpeg || self == .heic || self == .avif || self == .webp }

  /// Whether the format can store transparency.
  public var supportsAlpha: Bool { self != .jpeg && self != .bmp }

  /// Whether the format can hold several frames (an animation).
  public var supportsAnimation: Bool { self == .gif || self == .webp || self == .png || self == .heic }

  public init?(fileExtension ext: String) {
    switch ext.lowercased() {
    case "png": self = .png
    case "jpg", "jpeg": self = .jpeg
    case "heic", "heif": self = .heic
    case "avif": self = .avif
    case "tif", "tiff": self = .tiff
    case "bmp": self = .bmp
    case "webp": self = .webp
    case "gif": self = .gif
    case "svg": self = .svg
    default: return nil
    }
  }
}

/// What a dropped file is, as far as the app's operations are concerned.
public enum FileKind: Equatable, Sendable {
  case image(ImageFormat)
  case pdf
  case video(VideoFormat)
  case unsupported

  public init(url: URL) {
    let ext = url.pathExtension
    if let format = ImageFormat(fileExtension: ext) {
      self = .image(format)
    } else if let format = VideoFormat(fileExtension: ext) {
      self = .video(format)
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

  public var isVideo: Bool {
    if case .video = self { return true }
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
  /// Compress each image to at most this many bytes.
  case compressToSize(bytes: Int64)
  case replaceBackground(BackgroundFill)
  case edit(EditRecipe)
  /// The same edit (typically a crop) applied to every image.
  case batchEdit(EditRecipe)
  case editMetadata([MetadataEdit])
  case frame(FrameRecipe)
  case collage(CollageRecipe)
  case readQRCodes
  case convertVideo(VideoOutput)
  case compressVideo(VideoCompression)
  case editVideo(VideoRecipe)
  case splitVideo(SplitPlan)
  case joinVideos
  /// Save the frames at these times (seconds).
  case videoSnapshots([Double])

  /// Whether the operation is long-running media work.
  public var isMedia: Bool {
    switch self {
    case .convertVideo, .compressVideo, .editVideo, .splitVideo, .joinVideos, .videoSnapshots: true
    default: false
    }
  }

  public var summary: String {
    switch self {
    case .convert(let format, _): "Convert to \(format.displayName)"
    case .stripMetadata: "Strip metadata"
    case .mergePDFs: "Merge PDFs"
    case .imagesToPDF: "Images to PDF"
    case .compress: "Compress"
    case .compressToSize(let bytes):
      "Compress to \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    case .replaceBackground(.transparent): "Remove background"
    case .replaceBackground: "Replace background"
    case .edit: "Edit image"
    case .batchEdit: "Edit images"
    case .editMetadata: "Edit metadata"
    case .frame: "Frame image"
    case .collage: "Create collage"
    case .readQRCodes: "Read QR codes"
    case .convertVideo(let output):
      output.isAudioOnly ? "Extract \(output.displayName) audio" : "Convert to \(output.displayName)"
    case .compressVideo: "Compress video"
    case .editVideo: "Edit video"
    case .splitVideo(let plan): plan.joinKept ? "Cut video" : "Split video"
    case .joinVideos: "Join videos"
    case .videoSnapshots(let times): times.count == 1 ? "Save frame" : "Save frames"
    }
  }
}

/// What goes behind the subject when the background is replaced.
public enum BackgroundFill: Codable, Equatable, Hashable, Sendable {
  case transparent
  case color(RGBA)
  /// An image file, scaled to fill.
  case image(path: String)
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
  public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)
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
/// A modifier-key combination, stored independently of AppKit.
public struct ModifierCombo: Codable, Hashable, Sendable {
  public var shift: Bool
  public var command: Bool
  public var control: Bool
  public var option: Bool

  public init(shift: Bool = false, command: Bool = false, control: Bool = false, option: Bool = false) {
    self.shift = shift
    self.command = command
    self.control = control
    self.option = option
  }

  public var isEmpty: Bool { !(shift || command || control || option) }

  /// Key symbols in Apple's standard order: ⌃ ⌥ ⇧ ⌘.
  public var symbols: String {
    (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "")
  }

  /// Spoken or written names, in the same order.
  public var names: String {
    [control ? "control" : nil, option ? "option" : nil, shift ? "shift" : nil, command ? "command" : nil]
      .compactMap { $0 }.joined(separator: " + ")
  }

  /// The choices offered in Settings: each single key, then the common pairs.
  public static let choices: [ModifierCombo] = [
    .init(shift: true), .init(command: true), .init(control: true), .init(option: true),
    .init(shift: true, command: true), .init(control: true, option: true),
    .init(shift: true, control: true), .init(command: true, option: true),
  ]
}

/// Which modifier combination opens each wheel while dragging.
public struct WheelModifiers: Codable, Equatable, Sendable {
  public var convert: ModifierCombo
  public var tools: ModifierCombo
  public var actions: ModifierCombo

  public init(
    convert: ModifierCombo = .init(shift: true), tools: ModifierCombo = .init(command: true),
    actions: ModifierCombo = .init(control: true)
  ) {
    self.convert = convert
    self.tools = tools
    self.actions = actions
  }

  /// Two wheels sharing a combination, or an empty combination, can't work.
  public var isValid: Bool {
    let all = [convert, tools, actions]
    return Set(all).count == all.count && !all.contains(where: \.isEmpty)
  }
}

/// Defaults for one output format, set where you choose that format.
public struct FormatSettings: Codable, Equatable, Sendable {
  /// Overrides the global quality for lossy formats.
  public var quality: Double?
  public var preserveMetadata: Bool
  /// Keep pixel dimensions (needed to keep an animation).
  public var keepOriginalDimensions: Bool
  public var maxVideoHeight: Int?
  public var audioBitrateKbps: Int?
  public var audioBitDepth: Int?

  public init(
    quality: Double? = nil, preserveMetadata: Bool = true, keepOriginalDimensions: Bool = true,
    maxVideoHeight: Int? = nil, audioBitrateKbps: Int? = nil, audioBitDepth: Int? = nil
  ) {
    self.quality = quality.map(AppSettings.clampQuality)
    self.preserveMetadata = preserveMetadata
    self.keepOriginalDimensions = keepOriginalDimensions
    self.maxVideoHeight = maxVideoHeight
    self.audioBitrateKbps = audioBitrateKbps
    self.audioBitDepth = audioBitDepth
  }

  public init(from decoder: any Decoder) throws {
    let d = FormatSettings()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    quality = (try? c.decodeIfPresent(Double.self, forKey: .quality)).flatMap { $0 }.map(
      AppSettings.clampQuality)
    preserveMetadata = (try? c.decode(Bool.self, forKey: .preserveMetadata)) ?? d.preserveMetadata
    keepOriginalDimensions =
      (try? c.decode(Bool.self, forKey: .keepOriginalDimensions)) ?? d.keepOriginalDimensions
    maxVideoHeight = (try? c.decodeIfPresent(Int.self, forKey: .maxVideoHeight)).flatMap { $0 }
    audioBitrateKbps = (try? c.decodeIfPresent(Int.self, forKey: .audioBitrateKbps)).flatMap { $0 }
    audioBitDepth = (try? c.decodeIfPresent(Int.self, forKey: .audioBitDepth)).flatMap { $0 }
  }
}

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
  public var wheelModifiers: WheelModifiers
  /// The wheel's hover tick, drop pop and trackpad haptics.
  public var soundAndHaptics: Bool
  /// The app "Open Terminal" uses.
  public var terminalBundleID: String
  /// Per-output-format defaults, keyed by format identifier ("jpeg", "mp4", "mp3", …).
  public var formatSettings: [String: FormatSettings]

  public static let defaultTerminal = "com.apple.Terminal"

  /// The quality to use for `formatID`: its own setting, else the global one.
  public func quality(for formatID: String) -> Double {
    formatSettings[formatID]?.quality ?? quality
  }

  public func format(_ formatID: String) -> FormatSettings {
    formatSettings[formatID] ?? FormatSettings()
  }

  public init(
    defaultFormat: ImageFormat = .png,
    quality: Double = 0.85,
    outputLocation: OutputLocation = .nextToSource,
    launchAtLogin: Bool = false,
    wheelTriggerEnabled: Bool = true,
    appearance: AppearancePreference = .system,
    hasCompletedOnboarding: Bool = false,
    wheelModifiers: WheelModifiers = WheelModifiers(),
    soundAndHaptics: Bool = true,
    terminalBundleID: String = AppSettings.defaultTerminal,
    formatSettings: [String: FormatSettings] = [:]
  ) {
    self.defaultFormat = defaultFormat.isWritable ? defaultFormat : .png
    self.quality = Self.clampQuality(quality)
    self.outputLocation = outputLocation
    self.launchAtLogin = launchAtLogin
    self.wheelTriggerEnabled = wheelTriggerEnabled
    self.appearance = appearance
    self.hasCompletedOnboarding = hasCompletedOnboarding
    self.wheelModifiers = wheelModifiers.isValid ? wheelModifiers : WheelModifiers()
    self.soundAndHaptics = soundAndHaptics
    self.terminalBundleID = terminalBundleID.isEmpty ? Self.defaultTerminal : terminalBundleID
    self.formatSettings = formatSettings
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
    let modifiers = (try? c.decode(WheelModifiers.self, forKey: .wheelModifiers)) ?? defaults.wheelModifiers
    wheelModifiers = modifiers.isValid ? modifiers : defaults.wheelModifiers
    soundAndHaptics = (try? c.decode(Bool.self, forKey: .soundAndHaptics)) ?? defaults.soundAndHaptics
    let terminal = (try? c.decode(String.self, forKey: .terminalBundleID)) ?? defaults.terminalBundleID
    terminalBundleID = terminal.isEmpty ? defaults.terminalBundleID : terminal
    formatSettings = (try? c.decode([String: FormatSettings].self, forKey: .formatSettings)) ?? [:]
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
  case targetTooSmall(String)

  public var errorDescription: String? {
    switch self {
    case .fileNotFound(let name): "\(name) could not be found."
    case .unsupportedFile(let name): "\(name) is not a supported file type."
    case .wrongInput(let message): message
    case .readFailed(let name): "\(name) could not be read."
    case .writeFailed(let name): "\(name) could not be written."
    case .notSmaller(let name): "\(name) is already as small as it gets."
    case .noSubject(let name): "No clear subject was found in \(name)."
    case .targetTooSmall(let name): "\(name) can't get that small. Choose a larger target size."
    }
  }
}
