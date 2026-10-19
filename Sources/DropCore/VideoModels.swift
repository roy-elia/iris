import Foundation

/// Video containers the app reads.
public enum VideoFormat: String, CaseIterable, Codable, Sendable {
  case mp4, mov, m4v, webm, mkv, avi
  case wmv, flv, mpeg, ts, m2ts, ogv, vob
  case threeGP = "3gp"

  public init?(fileExtension ext: String) {
    switch ext.lowercased() {
    case "mp4": self = .mp4
    case "mov", "qt": self = .mov
    case "m4v": self = .m4v
    case "webm": self = .webm
    case "mkv": self = .mkv
    case "avi": self = .avi
    case "wmv", "asf": self = .wmv
    case "flv": self = .flv
    case "mpg", "mpeg", "m1v", "m2v", "mpe": self = .mpeg
    case "ts": self = .ts
    case "m2ts", "mts": self = .m2ts
    case "ogv": self = .ogv
    case "vob": self = .vob
    case "3gp", "3g2": self = .threeGP
    default: return nil
    }
  }

  public var displayName: String {
    switch self {
    case .webm: "WebM"
    case .ogv: "OGV"
    default: rawValue.uppercased()
    }
  }
}

/// What a video can be converted to: another container, an animated GIF, or its audio.
public enum VideoOutput: String, CaseIterable, Codable, Sendable {
  case mp4, mov, m4v, webm, mkv, avi, gif, mp3, m4a
  /// MP4 with HEVC (H.265) video from Apple's hardware encoder.
  case hevc
  /// MP4 (H.264) scaled down to at most 720 pixels high.
  case mp4720 = "mp4-720"

  public var fileExtension: String {
    switch self {
    case .hevc, .mp4720: "mp4"
    default: rawValue
    }
  }

  public var displayName: String {
    switch self {
    case .webm: "WebM"
    case .m4a: "M4A"
    case .hevc: "HEVC"
    case .mp4720: "720p"
    default: rawValue.uppercased()
    }
  }

  /// Added to the output's name, so these MP4s don't read as plain MP4 conversions.
  public var nameSuffix: String {
    switch self {
    case .hevc: "HEVC"
    case .mp4720: "720p"
    default: ""
    }
  }

  /// The tallest frame this output allows.
  public var maxHeight: Int? { self == .mp4720 ? 720 : nil }

  public var isAudioOnly: Bool { self == .mp3 || self == .m4a }

  /// Outputs whose Settings defaults (maximum height, bitrate) apply. GIF has its own
  /// size rule and shares its settings key with the GIF image format.
  public var usesVideoDefaults: Bool { !isAudioOnly && self != .gif }

  /// Outputs encoded with VideoToolbox, which take a bitrate setting.
  public var usesBitrate: Bool {
    switch self {
    case .mp4, .m4v, .mov, .mkv, .hevc, .mp4720: true
    default: false
    }
  }

  /// WebM needs a VP8/VP9 encoder, which the bundled LGPL ffmpeg doesn't include.
  public var isAvailable: Bool {
    guard ToolLocator.isAvailable(.ffmpeg) else { return false }
    switch self {
    case .webm: return VideoOps.hasEncoder("libvpx-vp9")
    case .hevc: return VideoOps.hasEncoder("hevc_videotoolbox")
    default: return true
    }
  }

  public var unavailableReason: String? {
    guard !isAvailable else { return nil }
    guard ToolLocator.isAvailable(.ffmpeg) else { return "ffmpeg is missing" }
    return self == .hevc ? "Needs an HEVC encoder" : "Needs a VP9 encoder"
  }
}

/// How hard to compress a video.
public enum VideoStrength: String, CaseIterable, Codable, Sendable {
  case light, medium, strong

  public var title: String {
    switch self {
    case .light: "Light"
    case .medium: "Medium"
    case .strong: "Strong"
    }
  }

  /// VideoToolbox constant-quality value (0–100, higher is better).
  var quality: Int {
    switch self {
    case .light: 62
    case .medium: 50
    case .strong: 38
    }
  }
}

public enum VideoCompression: Codable, Equatable, Hashable, Sendable {
  case strength(VideoStrength)
  /// At most this many bytes per file.
  case target(bytes: Int64)
}

/// A rectangle hidden during part of a video. Times are in source seconds.
public struct TimedRedaction: Codable, Equatable, Hashable, Sendable {
  public var rect: NormRect
  public var start: Double
  public var end: Double
  public var style: RedactStyle

  public init(rect: NormRect, start: Double, end: Double, style: RedactStyle = .blackout) {
    self.rect = rect
    self.start = min(start, end)
    self.end = max(start, end)
    self.style = style
  }
}

/// Edits applied to one video in a single encode: trim, redact, crop, scale, speed.
public struct VideoRecipe: Codable, Equatable, Hashable, Sendable {
  /// Keep only this range (source seconds).
  public var trimStart: Double?
  public var trimEnd: Double?
  public var speed: Double
  public var crop: NormRect?
  public var redactions: [TimedRedaction]
  public var maxHeight: Int?
  public var mute: Bool

  public static let speedRange: ClosedRange<Double> = 0.25...4

  public init(
    trimStart: Double? = nil, trimEnd: Double? = nil, speed: Double = 1, crop: NormRect? = nil,
    redactions: [TimedRedaction] = [], maxHeight: Int? = nil, mute: Bool = false
  ) {
    self.trimStart = trimStart
    self.trimEnd = trimEnd
    self.speed = min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
    self.crop = crop
    self.redactions = redactions
    self.maxHeight = maxHeight
    self.mute = mute
  }

  public var isIdentity: Bool {
    trimStart == nil && trimEnd == nil && speed == 1 && (crop == nil || crop == .full) && redactions.isEmpty
      && maxHeight == nil && !mute
  }

  /// The output's duration for a source of `duration` seconds.
  public func outputDuration(source duration: Double) -> Double {
    let start = max(trimStart ?? 0, 0)
    let end = min(trimEnd ?? duration, duration)
    return max(end - start, 0) / speed
  }
}

/// Split points cut a video into clips; removed clips are dropped. The kept clips are
/// saved separately, or joined into one video.
public struct SplitPlan: Codable, Equatable, Hashable, Sendable {
  public var points: [Double]
  public var removed: Set<Int>
  public var joinKept: Bool

  public static let minimumGap = 0.05

  public init(points: [Double], removed: Set<Int> = [], joinKept: Bool = false) {
    self.points = points.sorted()
    self.removed = removed
    self.joinKept = joinKept
  }

  /// The clips as (start, end) ranges for a video of `duration` seconds.
  public func clips(duration: Double) -> [ClosedRange<Double>] {
    let bounds = [0] + points.filter { $0 > 0 && $0 < duration } + [duration]
    return zip(bounds, bounds.dropFirst()).map { $0...$1 }
  }

  /// A message if the plan can't work, else nil.
  public func validate(duration: Double) -> String? {
    let inside = points.filter { $0 > 0 && $0 < duration }
    if inside.count != points.count
      || points.contains(where: { $0 < Self.minimumGap || $0 > duration - Self.minimumGap })
    {
      return "Add split points inside the video, at least 0.05 seconds from either end."
    }
    if zip(points, points.dropFirst()).contains(where: { $1 - $0 < Self.minimumGap }) {
      return "Split points must be at least 0.05 seconds apart."
    }
    let kept = clips(duration: duration).indices.filter { !removed.contains($0) }
    if kept.isEmpty { return "Keep at least one clip." }
    if points.isEmpty && removed.isEmpty { return "Add at least one split point." }
    return nil
  }
}

/// Facts about a media file, from ffprobe.
public struct MediaInfo: Equatable, Sendable {
  public var duration: Double
  /// Display size, after rotation.
  public var width: Int
  public var height: Int
  public var hasVideo: Bool
  public var hasAudio: Bool
  public var frameRate: Double
  public var audioChannels: Int
  public var sampleRate: Int

  public init(
    duration: Double, width: Int = 0, height: Int = 0, hasVideo: Bool = false, hasAudio: Bool = false,
    frameRate: Double = 0, audioChannels: Int = 0, sampleRate: Int = 0
  ) {
    self.duration = duration
    self.width = width
    self.height = height
    self.hasVideo = hasVideo
    self.hasAudio = hasAudio
    self.frameRate = frameRate
    self.audioChannels = audioChannels
    self.sampleRate = sampleRate
  }
}
