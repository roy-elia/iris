import Foundation

/// Audio files the app reads.
public enum AudioFormat: String, CaseIterable, Codable, Sendable {
  case mp3, wav, m4a, aac, flac, aiff, ogg, opus, wma, caf, amr, ape, ac3

  public init?(fileExtension ext: String) {
    switch ext.lowercased() {
    case "mp3": self = .mp3
    case "wav", "wave": self = .wav
    case "m4a": self = .m4a
    case "aac": self = .aac
    case "flac": self = .flac
    case "aif", "aiff": self = .aiff
    case "ogg", "oga": self = .ogg
    case "opus": self = .opus
    case "wma": self = .wma
    case "caf": self = .caf
    case "amr", "awb": self = .amr
    case "ape": self = .ape
    case "ac3": self = .ac3
    default: return nil
    }
  }

  public var displayName: String {
    switch self {
    case .aiff: "AIFF"
    case .opus: "Opus"
    case .ape: "Monkey's Audio"
    default: rawValue.uppercased()
    }
  }
}

/// Audio formats the app writes.
public enum AudioOutput: String, CaseIterable, Codable, Sendable {
  case mp3, wav, m4a, aac, flac, aiff, ogg, opus
  /// AMR narrowband (8 kHz mono speech, 12.2 kbps).
  case amr
  /// AMR wideband (16 kHz mono speech, 23.85 kbps).
  case awb
  /// Monkey's Audio (lossless), written by the bundled `mac` tool.
  case ape

  public var fileExtension: String { rawValue }

  public var displayName: String {
    switch self {
    case .aiff: "AIFF"
    case .opus: "Opus"
    case .awb: "AMR-WB"
    default: rawValue.uppercased()
    }
  }

  /// Lossless PCM-style outputs honour the bit-depth setting.
  public var usesBitDepth: Bool { self == .wav || self == .aiff || self == .flac || self == .ape }

  /// Lossy outputs honour the bitrate setting (AMR's speech modes are fixed).
  public var usesBitrate: Bool { !usesBitDepth && self != .amr && self != .awb }

  public static let bitDepths = [16, 24, 32]

  /// The bit depths this output offers.
  public var bitDepthChoices: [Int] { self == .wav ? Self.bitDepths : [16, 24] }

  /// AMR codecs only take one sample rate.
  public var fixedSampleRate: Int? {
    switch self {
    case .opus: 48000
    case .amr: 8000
    case .awb: 16000
    default: nil
    }
  }

  /// Whether the encoder is bundled.
  public var isAvailable: Bool {
    switch self {
    case .amr: VideoOps.hasEncoder("libopencore_amrnb")
    case .awb: VideoOps.hasEncoder("libvo_amrwbenc")
    case .ape: ToolLocator.isAvailable(.mac)
    default: ToolLocator.isAvailable(.ffmpeg)
    }
  }

  public var unavailableReason: String? {
    guard !isAvailable else { return nil }
    return switch self {
    case .ape: "Monkey's Audio encoder missing"
    case .amr, .awb: "AMR encoder missing"
    default: "ffmpeg is missing"
    }
  }
}

/// A time range to bleep, in source seconds.
public struct BleepRange: Codable, Equatable, Hashable, Sendable {
  public var start: Double
  public var end: Double

  public init(start: Double, end: Double) {
    self.start = min(start, end)
    self.end = max(start, end)
  }
}

public enum ChannelMode: String, Codable, CaseIterable, Sendable {
  case keep, mono, stereo

  public var title: String {
    switch self {
    case .keep: "Keep"
    case .mono: "Mono"
    case .stereo: "Stereo"
    }
  }
}

/// Loudness targets for normalising.
public enum LoudnessTarget: Double, Codable, CaseIterable, Sendable {
  case streaming = -14
  case podcast = -16
  case broadcast = -23

  public var title: String {
    switch self {
    case .streaming: "Music streaming (−14 LUFS)"
    case .podcast: "Podcast (−16 LUFS)"
    case .broadcast: "Broadcast (−23 LUFS)"
    }
  }
}

/// Edits applied to one audio file in a single pass: trim (or trim silent ends), channel
/// mix, bleeps, then loudness normalisation.
public struct AudioRecipe: Codable, Equatable, Hashable, Sendable {
  public var trimStart: Double?
  public var trimEnd: Double?
  /// Cut leading and trailing silence quieter than `silenceThreshold`.
  public var trimSilence: Bool
  /// In dBFS, e.g. −50.
  public var silenceThreshold: Double
  public var bleeps: [BleepRange]
  public var bleepAll: Bool
  public var normalize: LoudnessTarget?
  public var channels: ChannelMode
  /// Per-channel gain, 0…2 (1 is unchanged). Applies to stereo output.
  public var leftGain: Double
  public var rightGain: Double

  public static let thresholdRange: ClosedRange<Double> = -80 ... -20
  public static let gainRange: ClosedRange<Double> = 0...2

  public init(
    trimStart: Double? = nil, trimEnd: Double? = nil, trimSilence: Bool = false,
    silenceThreshold: Double = -50,
    bleeps: [BleepRange] = [], bleepAll: Bool = false, normalize: LoudnessTarget? = nil,
    channels: ChannelMode = .keep,
    leftGain: Double = 1, rightGain: Double = 1
  ) {
    self.trimStart = trimStart
    self.trimEnd = trimEnd
    self.trimSilence = trimSilence
    self.silenceThreshold = min(
      max(silenceThreshold, Self.thresholdRange.lowerBound), Self.thresholdRange.upperBound)
    self.bleeps = bleeps
    self.bleepAll = bleepAll
    self.normalize = normalize
    self.channels = channels
    self.leftGain = min(max(leftGain, Self.gainRange.lowerBound), Self.gainRange.upperBound)
    self.rightGain = min(max(rightGain, Self.gainRange.lowerBound), Self.gainRange.upperBound)
  }

  public var isIdentity: Bool {
    trimStart == nil && trimEnd == nil && !trimSilence && bleeps.isEmpty && !bleepAll && normalize == nil
      && channels == .keep && leftGain == 1 && rightGain == 1
  }
}

public enum VisualizerStyle: String, Codable, CaseIterable, Sendable {
  case wave, bars, spectrum

  public var title: String {
    switch self {
    case .wave: "Wave"
    case .bars: "Bars"
    case .spectrum: "Spectrum"
    }
  }
}

public enum VisualizerSize: String, Codable, CaseIterable, Sendable {
  case landscape, square, portrait

  public var title: String {
    switch self {
    case .landscape: "16:9"
    case .square: "1:1"
    case .portrait: "9:16"
    }
  }

  public var pixels: (width: Int, height: Int) {
    switch self {
    case .landscape: (1280, 720)
    case .square: (1080, 1080)
    case .portrait: (1080, 1920)
    }
  }
}

/// A video of the audio's waveform over a still background.
public struct VisualizerRecipe: Codable, Equatable, Hashable, Sendable {
  public var style: VisualizerStyle
  public var size: VisualizerSize
  public var color: RGBA
  /// An image file, or nil for a solid `backgroundColor`.
  public var backgroundImage: String?
  public var backgroundColor: RGBA

  public init(
    style: VisualizerStyle = .wave, size: VisualizerSize = .landscape, color: RGBA = .white,
    backgroundImage: String? = nil, backgroundColor: RGBA = RGBA(red: 0.05, green: 0.12, blue: 0.16)
  ) {
    self.style = style
    self.size = size
    self.color = color
    self.backgroundImage = backgroundImage
    self.backgroundColor = backgroundColor
  }
}
