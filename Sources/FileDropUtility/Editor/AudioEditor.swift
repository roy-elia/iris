import AVFoundation
import DropCore
import SwiftUI

/// The audio editor's tools. Every tool's settings go into one saved copy.
enum AudioTool: String, CaseIterable, Identifiable {
  case trim, bleep, volume, channels
  var id: String { rawValue }

  var title: String {
    switch self {
    case .trim: "Trim"
    case .bleep: "Bleep"
    case .volume: "Volume"
    case .channels: "Channels"
    }
  }

  var systemImage: String {
    switch self {
    case .trim: "timeline.selection"
    case .bleep: "speaker.slash"
    case .volume: "speaker.wave.3"
    case .channels: "headphones"
    }
  }
}

/// State for one audio editor window: the waveform, playback (AVFoundation where it can
/// play the file), and the edits.
@MainActor
final class AudioEditorModel: ObservableObject {
  let url: URL
  @Published var tool: AudioTool
  @Published private(set) var info: MediaInfo?
  @Published private(set) var loadError: String?
  @Published private(set) var peaks: [Float] = []
  @Published private(set) var canPlay = false
  @Published var isPlaying = false
  @Published var time: Double = 0

  // Edits
  @Published var trimStart: Double = 0
  @Published var trimEnd: Double = 0
  @Published var trimSilence = false
  @Published var silenceThreshold: Double = -50
  @Published private(set) var audible: ClosedRange<Double>?
  @Published var bleeps: [BleepRange] = []
  @Published var selectedBleep: Int?
  @Published var bleepAll = false
  @Published var normalize: LoudnessTarget?
  @Published var channels: ChannelMode = .keep
  /// −1 (left only) … 1 (right only).
  @Published var balance: Double = 0

  private(set) var player: AVPlayer?
  private var timeObserver: Any?
  private var silenceTask: Task<Void, Never>?

  static let peakCount = 600

  init(url: URL, tool: AudioTool) {
    self.url = url
    self.tool = tool
    Task { await load() }
  }

  /// A model with sample data, for previews.
  init(previewURL url: URL, info: MediaInfo, peaks: [Float], tool: AudioTool) {
    self.url = url
    self.tool = tool
    self.info = info
    self.peaks = peaks
    trimEnd = info.duration
  }

  var duration: Double { info?.duration ?? 0 }

  private func load() async {
    do {
      let info = try await VideoOps.probe(url)
      guard info.hasAudio else { throw DropError.wrongInput("This file has no audio track.") }
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
      }
      peaks = (try? await AudioOps.peaks(url, count: Self.peakCount)) ?? []
    } catch {
      loadError = AppModel.message(for: error, fallback: "This audio file could not be opened.")
    }
  }

  // MARK: Playback

  private func playerMoved(to seconds: Double) {
    guard seconds.isFinite else { return }
    time = seconds
    if isPlaying, seconds >= keptRange.upperBound - 0.02 {
      player?.pause()
      isPlaying = false
    }
  }

  func togglePlay() {
    guard let player else { return }
    isPlaying.toggle()
    if isPlaying {
      if time >= keptRange.upperBound - 0.05 || time < keptRange.lowerBound { seek(to: keptRange.lowerBound) }
      player.play()
    } else {
      player.pause()
    }
  }

  func seek(to seconds: Double) {
    let t = min(max(seconds, 0), duration)
    time = t
    player?.seek(
      to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
  }

  // MARK: Trim

  /// The part that will be kept, including the silence trim once it's measured.
  var keptRange: ClosedRange<Double> {
    var start = trimStart
    var end = max(trimEnd, trimStart)
    if trimSilence, let audible {
      start = max(start, audible.lowerBound)
      end = min(end, audible.upperBound)
    }
    return start...max(end, start)
  }

  func setTrimStartToPlayhead() { trimStart = min(time, trimEnd - SplitPlan.minimumGap) }
  func setTrimEndToPlayhead() { trimEnd = max(time, trimStart + SplitPlan.minimumGap) }

  /// Measures the silent ends at the current threshold, shortly after it stops changing.
  func refreshSilence() {
    silenceTask?.cancel()
    guard trimSilence, info != nil else {
      audible = nil
      return
    }
    let source = url
    let threshold = silenceThreshold
    let total = duration
    silenceTask = Task {
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      let range = try? await AudioOps.audibleRange(source, threshold: threshold, duration: total)
      if !Task.isCancelled { audible = range }
    }
  }

  // MARK: Bleep

  func addBleepAtPlayhead() {
    let start = min(time, max(duration - 0.1, 0))
    bleeps.append(BleepRange(start: start, end: min(duration, start + 1)))
    selectedBleep = bleeps.count - 1
  }

  func updateSelectedBleep(start: Double? = nil, end: Double? = nil) {
    guard let i = selectedBleep, bleeps.indices.contains(i) else { return }
    let b = bleeps[i]
    bleeps[i] = BleepRange(
      start: min(max(start ?? b.start, 0), duration), end: min(max(end ?? b.end, 0), duration))
  }

  func deleteSelectedBleep() {
    guard let i = selectedBleep, bleeps.indices.contains(i) else { return }
    bleeps.remove(at: i)
    selectedBleep = bleeps.isEmpty ? nil : min(i, bleeps.count - 1)
  }

  // MARK: Save

  var recipe: AudioRecipe {
    AudioRecipe(
      trimStart: trimStart > 0.001 ? trimStart : nil, trimEnd: trimEnd < duration - 0.001 ? trimEnd : nil,
      trimSilence: trimSilence, silenceThreshold: silenceThreshold,
      bleeps: bleepAll ? [] : bleeps.filter { $0.end - $0.start >= 0.02 }, bleepAll: bleepAll,
      normalize: normalize, channels: channels,
      leftGain: balance > 0 ? 1 - balance : 1, rightGain: balance < 0 ? 1 + balance : 1)
  }

  var canSave: Bool { info != nil && !recipe.isIdentity }

  func save() {
    guard let file = try? DroppedFile.load(url) else { return }
    player?.pause()
    isPlaying = false
    AppModel.shared.run(.editAudio(recipe), on: [file], origin: .overlay)
  }

  func tearDown() {
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    player?.pause()
    silenceTask?.cancel()
  }
}

// MARK: - View

/// The audio editor: a large glass waveform with the toolbar on top and an inspector at the
/// side, matching the video editor's layout.
struct AudioEditorView: View {
  @StateObject var model: AudioEditorModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()
      VStack(spacing: 14) {
        if let error = model.loadError {
          ContentUnavailableView("Can't Open Audio", systemImage: "waveform.slash", description: Text(error))
        } else {
          WaveformTimeline(model: model)
        }
      }
      .padding(.top, 72)
      .padding(.trailing, 280)
      .padding([.leading, .bottom], 24)
      VStack {
        toolbar
        Spacer()
      }
      .padding(DesignTokens.Spacing.inset)
      HStack {
        Spacer()
        inspector
          .frame(width: 256)
          .padding(.top, 64)
          .padding(DesignTokens.Spacing.inset)
      }
    }
    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: model.tool)
    .onDisappear { model.tearDown() }
    .onKeyPress(.space) {
      model.togglePlay()
      return .handled
    }
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      GlassToolPicker(
        tools: AudioTool.allCases, selection: $model.tool, title: \.title,
        systemImage: \.systemImage, identifier: { "audioTool-\($0.rawValue)" })
      Button {
        model.togglePlay()
      } label: {
        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
      }
      .buttonStyle(.glass)
      .disabled(!model.canPlay)
      .help(
        model.canPlay
          ? "Play the kept part (Space)"
          : "Playback is unavailable for this format. You can still edit and save."
      )
      .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
      Text("\(formatTime(model.time)) / \(formatTime(model.duration))")
        .font(.callout.monospacedDigit())
        .foregroundStyle(Color.secondary)
      Spacer()
      Button("Save Edited Copy") { model.save() }
        .buttonStyle(.glassProminent)
        .disabled(!model.canSave)
        .keyboardShortcut("s")
        .accessibilityIdentifier("saveAudio")
    }
    .padding(.leading, 70)  // Clear the traffic lights.
  }

  // MARK: Inspector

  private var inspector: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.tool.title).font(.headline)
      switch model.tool {
      case .trim: trimInspector
      case .bleep: bleepInspector
      case .volume: volumeInspector
      case .channels: channelsInspector
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxHeight: .infinity, alignment: .top)
    .glassPanel(cornerRadius: DesignTokens.Radius.window)
  }

  @ViewBuilder private var trimInspector: some View {
    Text("Drag the ends of the waveform, or set them at the playhead.")
      .font(.callout).foregroundStyle(Color.secondary)
    HStack {
      Button("Start at Playhead") { model.setTrimStartToPlayhead() }.buttonStyle(.glass)
      Button("End") { model.setTrimEndToPlayhead() }.buttonStyle(.glass).help("End at the playhead")
    }
    LabeledContent("Keeps", value: formatTime(model.keptRange.upperBound - model.keptRange.lowerBound))
      .font(.callout.monospacedDigit())
    Divider()
    Toggle("Trim silent ends", isOn: $model.trimSilence)
      .onChange(of: model.trimSilence) { model.refreshSilence() }
    if model.trimSilence {
      VStack(alignment: .leading, spacing: 4) {
        Text("Silence below \(Int(model.silenceThreshold)) dB").font(.callout.monospacedDigit())
        Slider(value: $model.silenceThreshold, in: AudioRecipe.thresholdRange, step: 1)
          .onChange(of: model.silenceThreshold) { model.refreshSilence() }
          .accessibilityLabel("Silence threshold")
        Text("Raise it to cut more background hiss.").font(.caption)
          .foregroundStyle(Color.secondary)
      }
    }
  }

  @ViewBuilder private var bleepInspector: some View {
    Toggle("Bleep the whole file", isOn: $model.bleepAll)
    if !model.bleepAll {
      Text("Add a bleep at the playhead, then drag its ends on the waveform.")
        .font(.callout).foregroundStyle(Color.secondary)
      Button("Add Bleep") { model.addBleepAtPlayhead() }.buttonStyle(.glass)
      ForEach(Array(model.bleeps.enumerated()), id: \.offset) { index, bleep in
        Button {
          model.selectedBleep = index
        } label: {
          HStack {
            Image(systemName: "speaker.slash.fill")
            Text("\(formatTime(bleep.start)) – \(formatTime(bleep.end))").monospacedDigit()
            Spacer()
          }
          .font(.callout)
          .padding(.horizontal, 10).padding(.vertical, 6)
          .background(
            model.selectedBleep == index
              ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quinary),
            in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
      }
      if model.selectedBleep != nil {
        Button("Delete Bleep", role: .destructive) { model.deleteSelectedBleep() }.buttonStyle(.glass)
      }
    }
  }

  @ViewBuilder private var volumeInspector: some View {
    Toggle(
      "Normalize loudness",
      isOn: Binding(get: { model.normalize != nil }, set: { model.normalize = $0 ? .podcast : nil }))
    if model.normalize != nil {
      Picker(
        "Target", selection: Binding(get: { model.normalize ?? .podcast }, set: { model.normalize = $0 })
      ) {
        ForEach(LoudnessTarget.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .labelsHidden()
    }
    Text("Evens out loudness to a standard level (EBU R128), so files play back at the same volume.")
      .font(.callout).foregroundStyle(Color.secondary)
  }

  @ViewBuilder private var channelsInspector: some View {
    Picker("Output", selection: $model.channels) {
      ForEach(ChannelMode.allCases, id: \.self) { Text($0.title).tag($0) }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    if let info = model.info {
      Text(info.audioChannels == 1 ? "The file is mono." : "The file has \(info.audioChannels) channels.")
        .font(.callout).foregroundStyle(Color.secondary)
    }
    if model.channels != .mono {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("L")
          Slider(value: $model.balance, in: -1...1)
            .accessibilityLabel("Balance")
            .accessibilityValue(balanceText)
          Text("R")
        }
        .font(.callout.weight(.semibold))
        HStack {
          Text(balanceText).font(.caption.monospacedDigit()).foregroundStyle(
            Color.secondary)
          Spacer()
          Button("Centre") { model.balance = 0 }.buttonStyle(.glass).controlSize(.small)
            .disabled(model.balance == 0)
        }
      }
    }
  }

  private var balanceText: String {
    let pct = Int((abs(model.balance) * 100).rounded())
    if pct == 0 { return "Centred" }
    return model.balance < 0 ? "\(pct)% left" : "\(pct)% right"
  }
}

/// The waveform, with trim handles, bleep ranges and the playhead drawn over it.
struct WaveformTimeline: View {
  @ObservedObject var model: AudioEditorModel

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let duration = max(model.duration, 0.001)
      let x: (Double) -> CGFloat = { CGFloat($0 / duration) * w }
      ZStack(alignment: .topLeading) {
        WaveformShape(peaks: model.peaks)
          .fill(
            LinearGradient(
              colors: [Color.accentColor, Color.accentColor], startPoint: .top,
              endPoint: .bottom)
          )
          .frame(width: w, height: h)
          .accessibilityHidden(true)

        let kept = model.keptRange
        dim(from: 0, to: x(kept.lowerBound), height: h)
        dim(from: x(kept.upperBound), to: w, height: h)

        if model.bleepAll {
          bleepBand(from: 0, to: w, height: h, selected: true)
        } else {
          ForEach(Array(model.bleeps.enumerated()), id: \.offset) { index, b in
            bleepBand(from: x(b.start), to: x(b.end), height: h, selected: model.selectedBleep == index)
              .onTapGesture { model.selectedBleep = index }
              .accessibilityLabel("Bleep \(index + 1)")
          }
        }

        switch model.tool {
        case .trim:
          handle(at: x(model.trimStart), height: h, width: w, label: "Trim start") { t in
            model.trimStart = min(max(t * duration, 0), model.trimEnd - SplitPlan.minimumGap)
          }
          handle(at: x(model.trimEnd), height: h, width: w, label: "Trim end") { t in
            model.trimEnd = max(min(t * duration, duration), model.trimStart + SplitPlan.minimumGap)
          }
          .offset(x: -10)
        case .bleep:
          if !model.bleepAll, let i = model.selectedBleep, model.bleeps.indices.contains(i) {
            let b = model.bleeps[i]
            // Thin handles just outside the band, so a short bleep stays visible.
            handle(at: x(b.start) - 6, height: h, width: w, thickness: 6, label: "Bleep start") { t in
              model.updateSelectedBleep(start: min(t * duration, b.end - 0.05))
            }
            handle(at: x(b.end), height: h, width: w, thickness: 6, label: "Bleep end") { t in
              model.updateSelectedBleep(end: max(t * duration, b.start + 0.05))
            }
          }
        case .volume, .channels:
          EmptyView()
        }

        Capsule().fill(.white).frame(width: 2, height: h + 10).offset(x: x(model.time) - 1, y: -5)
          .shadow(color: .black.opacity(0.4), radius: 2).allowsHitTesting(false)
      }
      .coordinateSpace(name: "waveform")
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0).onChanged { v in
          model.seek(to: Double(min(max(v.location.x / w, 0), 1)) * duration)
        }
      )
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Waveform. Drag to move the playhead.")
      .accessibilityValue(formatTime(model.time))
    }
    .padding(16)
    .glassPanel(cornerRadius: 24)
  }

  private func dim(from a: CGFloat, to b: CGFloat, height: CGFloat) -> some View {
    Rectangle().fill(.black.opacity(0.5)).frame(width: max(b - a, 0), height: height).offset(x: a)
      .allowsHitTesting(false)
  }

  private func bleepBand(from a: CGFloat, to b: CGFloat, height: CGFloat, selected: Bool) -> some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(Color.orange.opacity(selected ? 0.4 : 0.25))
      .overlay(alignment: .top) {
        Image(systemName: "speaker.slash.fill").font(.caption).foregroundStyle(.white).padding(6)
      }
      .frame(width: max(b - a, 6), height: height)
      .offset(x: a)
  }

  private func handle(
    at xPos: CGFloat, height: CGFloat, width: CGFloat, thickness: CGFloat = 10, label: String,
    onDrag: @escaping (Double) -> Void
  ) -> some View {
    Color.clear
      .frame(width: thickness, height: height + 6)
      .glassEffect(.regular.interactive(), in: Capsule())
      .offset(x: xPos, y: -3)
      .highPriorityGesture(
        DragGesture(coordinateSpace: .named("waveform")).onChanged { v in
          onDrag(Double(min(max(v.location.x / max(width, 1), 0), 1)))
        }
      )
      .accessibilityLabel(label)
  }
}

/// Mirrored bars, one per peak.
struct WaveformShape: Shape {
  let peaks: [Float]

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard !peaks.isEmpty else {
      path.addRect(CGRect(x: 0, y: rect.midY - 0.5, width: rect.width, height: 1))
      return path
    }
    let step = rect.width / CGFloat(peaks.count)
    let barWidth = max(step * 0.6, 1)
    for (i, peak) in peaks.enumerated() {
      let height = max(CGFloat(peak) * rect.height * 0.92, 1.5)
      let bar = CGRect(
        x: CGFloat(i) * step + (step - barWidth) / 2, y: rect.midY - height / 2, width: barWidth,
        height: height)
      path.addRoundedRect(in: bar, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
    }
    return path
  }
}
