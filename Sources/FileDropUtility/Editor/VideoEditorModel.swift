import AVFoundation
import AppKit
import DropCore
import SwiftUI

/// The video editor's tools.
enum VideoTool: String, CaseIterable, Identifiable {
  case trim, split, speed, frames, crop, redact
  var id: String { rawValue }

  var title: String {
    switch self {
    case .trim: "Trim"
    case .split: "Split"
    case .speed: "Speed"
    case .frames: "Frames"
    case .crop: "Crop"
    case .redact: "Redact"
    }
  }

  var systemImage: String {
    switch self {
    case .trim: "timeline.selection"
    case .split: "scissors"
    case .speed: "gauge.with.dots.needle.67percent"
    case .frames: "camera.viewfinder"
    case .crop: "crop"
    case .redact: "eye.slash"
    }
  }
}

/// State for one video editor window: playback (AVFoundation where it can play the file,
/// otherwise still frames from ffmpeg), the thumbnail timeline, and each tool's edits.
@MainActor
final class VideoEditorModel: ObservableObject {
  let url: URL
  @Published var tool: VideoTool
  @Published private(set) var info: MediaInfo?
  @Published private(set) var loadError: String?
  @Published private(set) var thumbnails: [CGImage] = []
  @Published private(set) var stillFrame: CGImage?
  @Published private(set) var canPlay = false
  @Published var isPlaying = false
  @Published var time: Double = 0

  // Edits
  @Published var trimStart: Double = 0
  @Published var trimEnd: Double = 0
  @Published var speed: Double = 1
  @Published var crop: NormRect?
  @Published var redactions: [TimedRedaction] = []
  @Published var selectedRedaction: Int?
  @Published var splitPoints: [Double] = []
  @Published var removedClips: Set<Int> = []
  @Published var joinKept = false
  @Published var frameTimes: [Double] = []
  @Published var dragRect: NormRect?

  private(set) var player: AVPlayer?
  private var timeObserver: Any?
  private var frameTask: Task<Void, Never>?
  private let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(
    "fdu-video-\(UUID().uuidString)")

  static let thumbnailCount = 12

  init(url: URL, tool: VideoTool) {
    self.url = url
    self.tool = tool
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    Task { await load() }
  }

  var duration: Double { info?.duration ?? 0 }

  // MARK: Loading

  private func load() async {
    do {
      let info = try await VideoOps.probe(url)
      guard info.hasVideo else { throw DropError.wrongInput("This file has no playable video track.") }
      self.info = info
      trimEnd = info.duration
      let asset = AVURLAsset(url: url)
      canPlay = (try? await asset.load(.isPlayable)) ?? false
      if canPlay {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.actionAtItemEnd = .pause
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
          forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600), queue: .main
        ) { [weak self] t in
          MainActor.assumeIsolated { self?.playerMoved(to: t.seconds) }
        }
      } else {
        refreshStillFrame()
      }
      thumbnails = await makeThumbnails(info: info)
    } catch {
      loadError = AppModel.message(for: error, fallback: "This video could not be opened.")
    }
  }

  private func makeThumbnails(info: MediaInfo) async -> [CGImage] {
    let pattern = scratch.appendingPathComponent("thumb%02d.png").path
    let rate = Double(Self.thumbnailCount) / max(info.duration, 0.1)
    _ = try? await ToolRunner.run(
      .ffmpeg,
      [
        "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-i", url.path, "-vf",
        "fps=\(rate),scale=-2:96", "-frames:v", "\(Self.thumbnailCount)", pattern,
      ])
    return (1...Self.thumbnailCount).compactMap { i in
      let file = scratch.appendingPathComponent(String(format: "thumb%02d.png", i))
      return try? ImageOps.loadOriented(file)
    }
  }

  // MARK: Playback

  private func playerMoved(to seconds: Double) {
    guard seconds.isFinite else { return }
    time = seconds
    // Loop inside the trimmed range while playing.
    if isPlaying, seconds >= trimEnd - 0.02 {
      seek(to: trimStart)
      player?.rate = Float(speed)
    }
  }

  func togglePlay() {
    guard let player else { return }
    isPlaying.toggle()
    if isPlaying {
      if time >= trimEnd - 0.05 || time < trimStart { seek(to: trimStart) }
      player.rate = Float(speed)
    } else {
      player.pause()
    }
  }

  func seek(to seconds: Double) {
    let t = min(max(seconds, 0), duration)
    time = t
    if let player {
      player.seek(
        to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    } else {
      refreshStillFrame()
    }
  }

  /// ffmpeg frame for files AVFoundation can't play, fetched shortly after scrubbing stops.
  private func refreshStillFrame() {
    frameTask?.cancel()
    let t = time
    let out = scratch.appendingPathComponent("frame-\(UUID().uuidString).png")
    let source = url
    frameTask = Task {
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      _ = try? await ToolRunner.run(
        .ffmpeg,
        [
          "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-ss", String(format: "%.3f", t), "-i",
          source.path,
          "-frames:v", "1", "-vf", "scale=-2:720", out.path,
        ])
      if !Task.isCancelled, let image = try? ImageOps.loadOriented(out) { stillFrame = image }
      try? FileManager.default.removeItem(at: out)
    }
  }

  // MARK: Tool actions

  func setTrimStartToPlayhead() { trimStart = min(time, trimEnd - SplitPlan.minimumGap) }
  func setTrimEndToPlayhead() { trimEnd = max(time, trimStart + SplitPlan.minimumGap) }

  func addSplitAtPlayhead() {
    let t = time
    guard t > SplitPlan.minimumGap, t < duration - SplitPlan.minimumGap,
      !splitPoints.contains(where: { abs($0 - t) < SplitPlan.minimumGap })
    else { return }
    splitPoints = (splitPoints + [t]).sorted()
    removedClips = []
  }

  func removeSplit(_ point: Double) {
    splitPoints.removeAll { $0 == point }
    removedClips = []
  }

  var clips: [ClosedRange<Double>] { SplitPlan(points: splitPoints).clips(duration: duration) }

  func toggleClip(_ index: Int) {
    if removedClips.contains(index) { removedClips.remove(index) } else { removedClips.insert(index) }
  }

  func addFrameAtPlayhead() {
    guard !frameTimes.contains(where: { abs($0 - time) < 0.02 }) else { return }
    frameTimes = (frameTimes + [time]).sorted()
  }

  func addRedactionAtPlayhead() {
    let start = time
    let end = min(duration, time + 2)
    redactions.append(
      TimedRedaction(
        rect: NormRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3), start: start, end: end, style: redactStyle)
    )
    selectedRedaction = redactions.count - 1
  }

  @Published var redactStyle: RedactStyle = .blackout {
    didSet { for i in redactions.indices { redactions[i].style = redactStyle } }
  }

  func updateSelected(_ change: (inout TimedRedaction) -> Void) {
    guard let i = selectedRedaction, redactions.indices.contains(i) else { return }
    change(&redactions[i])
  }

  func deleteSelectedRedaction() {
    guard let i = selectedRedaction, redactions.indices.contains(i) else { return }
    redactions.remove(at: i)
    selectedRedaction = redactions.isEmpty ? nil : min(i, redactions.count - 1)
  }

  /// Redactions showing at the playhead.
  var activeRedactions: [(Int, TimedRedaction)] {
    redactions.enumerated().filter { time >= $0.element.start && time <= $0.element.end }.map {
      ($0.offset, $0.element)
    }
  }

  // MARK: Preview gestures

  func previewDragChanged(from a: NormPoint, to b: NormPoint) {
    guard tool == .crop || tool == .redact else { return }
    dragRect = NormRect(from: a, to: b)
  }

  func previewDragEnded() {
    defer { dragRect = nil }
    guard let rect = dragRect, !rect.isEmpty else { return }
    switch tool {
    case .crop: crop = rect
    case .redact:
      if selectedRedaction == nil || !activeRedactions.contains(where: { $0.0 == selectedRedaction }) {
        redactions.append(
          TimedRedaction(rect: rect, start: time, end: min(duration, time + 2), style: redactStyle))
        selectedRedaction = redactions.count - 1
      } else {
        updateSelected { $0.rect = rect }
      }
    default: break
    }
  }

  // MARK: Save

  var recipe: VideoRecipe {
    VideoRecipe(
      trimStart: trimStart > 0.001 ? trimStart : nil, trimEnd: trimEnd < duration - 0.001 ? trimEnd : nil,
      speed: speed, crop: crop, redactions: redactions)
  }

  var saveTitle: String {
    switch tool {
    case .split: joinKept ? "Save Joined Video" : "Export Clips"
    case .frames: frameTimes.count == 1 ? "Save Frame" : "Save Frames"
    default: "Save Edited Copy"
    }
  }

  var canSave: Bool {
    guard info != nil else { return false }
    switch tool {
    case .split:
      return SplitPlan(points: splitPoints, removed: removedClips, joinKept: joinKept).validate(
        duration: duration) == nil
    case .frames: return !frameTimes.isEmpty
    default: return !recipe.isIdentity
    }
  }

  func save() {
    guard let file = try? DroppedFile.load(url) else { return }
    let operation: FileOperation =
      switch tool {
      case .split: .splitVideo(SplitPlan(points: splitPoints, removed: removedClips, joinKept: joinKept))
      case .frames: .videoSnapshots(frameTimes)
      default: .editVideo(recipe)
      }
    player?.pause()
    isPlaying = false
    AppModel.shared.run(operation, on: [file], origin: .overlay)
  }

  deinit {
    try? FileManager.default.removeItem(at: scratch)
  }

  func tearDown() {
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    player?.pause()
    frameTask?.cancel()
  }
}

/// "1:05.25"-style time.
func formatTime(_ seconds: Double) -> String {
  let s = max(seconds, 0)
  let m = Int(s) / 60
  return String(format: "%d:%05.2f", m, s - Double(m * 60))
}
