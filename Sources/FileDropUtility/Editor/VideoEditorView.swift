import AVKit
import DropCore
import SwiftUI

/// The video editor: the picture fills the window, a glass timeline of thumbnails sits
/// under it, and the toolbar and inspector float as glass panels.
struct VideoEditorView: View {
  @StateObject var model: VideoEditorModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()
      VStack(spacing: 14) {
        preview
        VideoTimeline(model: model)
          .frame(height: 64)
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

  // MARK: Toolbar

  private var toolbar: some View {
    HStack(spacing: 8) {
      GlassToolPicker(
        tools: VideoTool.allCases, selection: $model.tool, title: \.title,
        systemImage: \.systemImage, identifier: { "videoTool-\($0.rawValue)" })
      Button {
        model.togglePlay()
      } label: {
        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
      }
      .buttonStyle(.glass)
      .disabled(!model.canPlay)
      .help(
        model.canPlay
          ? "Play or pause the timeline preview (Space)"
          : "Playback is unavailable for this video. You can still scrub the timeline and export."
      )
      .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
      Text("\(formatTime(model.time)) / \(formatTime(model.duration))")
        .font(.callout.monospacedDigit())
        .foregroundStyle(Color.secondary)
      Spacer()
      Button(model.saveTitle) { model.save() }
        .buttonStyle(.glassProminent)
        .disabled(!model.canSave)
        .keyboardShortcut("s")
        .accessibilityIdentifier("saveVideo")
    }
    .padding(.leading, 70)  // Clear the traffic lights.
  }

  // MARK: Preview

  private var preview: some View {
    GeometryReader { geo in
      if let info = model.info {
        let size = fit(CGSize(width: info.width, height: info.height), in: geo.size)
        ZStack(alignment: .topLeading) {
          Group {
            if let player = model.player {
              PlayerLayerView(player: player)
            } else if let frame = model.stillFrame {
              Image(decorative: frame, scale: 1).resizable()
            } else {
              Color.black
            }
          }
          .frame(width: size.width, height: size.height)
          .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous))
          overlays(size: size)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 2)
            .onChanged { v in
              model.previewDragChanged(from: norm(v.startLocation, size), to: norm(v.location, size))
            }
            .onEnded { _ in model.previewDragEnded() }
        )
        .position(x: geo.size.width / 2, y: geo.size.height / 2)
        .accessibilityElement()
        .accessibilityLabel("Video preview, \(model.tool.title) tool")
      } else if let error = model.loadError {
        Text(error).foregroundStyle(Color.secondary).frame(
          maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ProgressView("Loading video").frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  /// Crop and redactions are previewed only where saving applies them (not Split or
  /// Frames, which export the original picture).
  private var showsEdits: Bool { model.tool != .split && model.tool != .frames }

  @ViewBuilder
  private func overlays(size: CGSize) -> some View {
    if showsEdits { editOverlays(size: size) }
  }

  @ViewBuilder
  private func editOverlays(size: CGSize) -> some View {
    if let crop = (model.tool == .crop ? model.dragRect : nil) ?? model.crop {
      VideoCropShade(rect: crop, size: size).allowsHitTesting(false)
    }
    ForEach(model.activeRedactions, id: \.0) { index, r in
      let box = rect(r.rect, size)
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(r.style == .blackout ? AnyShapeStyle(.black) : AnyShapeStyle(.ultraThinMaterial))
        .overlay {
          if model.tool == .redact && model.selectedRedaction == index {
            RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(
              Color.accentColor, lineWidth: 2)
          }
        }
        .frame(width: box.width, height: box.height)
        .offset(x: box.minX, y: box.minY)
        .allowsHitTesting(false)
    }
    if model.tool == .redact, let r = model.dragRect {
      let box = rect(r, size)
      Rectangle().fill(.black.opacity(0.6)).frame(width: box.width, height: box.height)
        .offset(x: box.minX, y: box.minY).allowsHitTesting(false)
    }
  }

  // MARK: Inspector

  private var inspector: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.tool.title).font(.headline)
      switch model.tool {
      case .trim:
        hint("Drag the ends of the timeline to trim, or set them from the playhead.")
        LabeledContent("Start", value: formatTime(model.trimStart)).monospacedDigit()
        LabeledContent("End", value: formatTime(model.trimEnd)).monospacedDigit()
        HStack {
          Button("Set Start") { model.setTrimStartToPlayhead() }.buttonStyle(.glass)
          Button("Set End") { model.setTrimEndToPlayhead() }.buttonStyle(.glass)
        }
        LabeledContent("Length", value: formatTime(model.trimEnd - model.trimStart)).monospacedDigit()
      case .split:
        hint("Add split points, then click a clip in the timeline to remove it.")
        Button("Add Split at Playhead") { model.addSplitAtPlayhead() }.buttonStyle(.glass)
        ForEach(Array(model.clips.enumerated()), id: \.offset) { index, clip in
          Toggle(
            isOn: Binding(get: { !model.removedClips.contains(index) }, set: { _ in model.toggleClip(index) })
          ) {
            Text("Clip \(index + 1)  \(formatTime(clip.lowerBound))–\(formatTime(clip.upperBound))")
              .monospacedDigit()
          }
        }
        Toggle("Join kept clips into one video", isOn: $model.joinKept)
        if !model.splitPoints.isEmpty {
          Button("Clear Split Points") {
            model.splitPoints = []
            model.removedClips = []
          }
          .buttonStyle(.glass)
        }
      case .speed:
        HStack {
          Slider(value: $model.speed, in: VideoRecipe.speedRange).accessibilityLabel("Speed")
          Text(String(format: "%.2g×", model.speed)).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
        HStack {
          ForEach([0.5, 1, 1.5, 2], id: \.self) { s in
            Button(String(format: "%g×", s)) { model.speed = s }.buttonStyle(.glass)
          }
        }
        LabeledContent("New length", value: formatTime((model.trimEnd - model.trimStart) / model.speed))
          .monospacedDigit()
      case .frames:
        hint("Scrub to a moment and add it. Each frame is saved as a PNG.")
        Button("Add Frame at Playhead") { model.addFrameAtPlayhead() }.buttonStyle(.glass)
        ForEach(model.frameTimes, id: \.self) { t in
          HStack {
            Text(formatTime(t)).monospacedDigit()
            Spacer()
            Button {
              model.frameTimes.removeAll { $0 == t }
            } label: {
              Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove frame at \(formatTime(t))")
          }
        }
      case .crop:
        hint("Drag over the video to choose the area to keep.")
        if model.crop != nil {
          Button("Clear Crop") { model.crop = nil }.buttonStyle(.glass)
        }
      case .redact:
        hint("Draw a rectangle over the area to hide. It shows for the time range below.")
        Button("Add Redaction at Playhead") { model.addRedactionAtPlayhead() }.buttonStyle(.glass)
        Picker("Style", selection: $model.redactStyle) {
          Text("Solid").tag(RedactStyle.blackout)
          Text("Pixelate").tag(RedactStyle.pixelate)
          Text("Blur").tag(RedactStyle.blur)
        }
        .pickerStyle(.segmented)
        if model.redactStyle != .blackout {
          Text("Blur softens details. Use Solid for sensitive information.")
            .font(.caption).foregroundStyle(Color.orange)
        }
        if let i = model.selectedRedaction, model.redactions.indices.contains(i) {
          let r = model.redactions[i]
          LabeledContent("From", value: formatTime(r.start)).monospacedDigit()
          LabeledContent("To", value: formatTime(r.end)).monospacedDigit()
          HStack {
            Button("Set Start") { model.updateSelected { $0.start = min(model.time, $0.end) } }.buttonStyle(
              .glass)
            Button("Set End") { model.updateSelected { $0.end = max(model.time, $0.start) } }.buttonStyle(
              .glass)
          }
          HStack {
            Button("Entire Video") {
              model.updateSelected {
                $0.start = 0
                $0.end = model.duration
              }
            }
            .buttonStyle(.glass)
            Button("Delete", role: .destructive) { model.deleteSelectedRedaction() }.buttonStyle(.glass)
          }
        }
      }
      Spacer(minLength: 0)
      Text(model.url.lastPathComponent).font(.caption).foregroundStyle(Color.secondary)
        .lineLimit(1).truncationMode(.middle)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .glassCard()
  }

  private func hint(_ text: String) -> some View {
    Text(text).font(.callout).foregroundStyle(Color.secondary)
  }

  // MARK: Geometry

  private func rect(_ r: NormRect, _ size: CGSize) -> CGRect {
    CGRect(
      x: r.x * size.width, y: r.y * size.height, width: r.width * size.width, height: r.height * size.height)
  }

  private func norm(_ p: CGPoint, _ size: CGSize) -> NormPoint {
    NormPoint(x: min(max(p.x / size.width, 0), 1), y: min(max(p.y / size.height, 0), 1))
  }

  private func fit(_ image: CGSize, in box: CGSize) -> CGSize {
    guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return .zero }
    let scale = min(box.width / image.width, box.height / image.height)
    return CGSize(width: image.width * scale, height: image.height * scale)
  }
}

/// The thumbnail strip with the playhead and each tool's marks. Drag to scrub.
struct VideoTimeline: View {
  @ObservedObject var model: VideoEditorModel

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let duration = max(model.duration, 0.001)
      let x: (Double) -> CGFloat = { CGFloat($0 / duration) * w }
      ZStack(alignment: .topLeading) {
        HStack(spacing: 0) {
          ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, thumb in
            Image(decorative: thumb, scale: 1).resizable().scaledToFill()
              .frame(width: w / CGFloat(max(model.thumbnails.count, 1)), height: h).clipped()
          }
        }
        .frame(width: w, height: h)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        switch model.tool {
        case .trim, .speed:
          dim(from: 0, to: x(model.trimStart), height: h)
          dim(from: x(model.trimEnd), to: w, height: h)
          handle(at: x(model.trimStart), height: h, width: w) { t in
            model.trimStart = min(max(t * duration, 0), model.trimEnd - SplitPlan.minimumGap)
          }
          handle(at: x(model.trimEnd), height: h, width: w) { t in
            model.trimEnd = max(min(t * duration, duration), model.trimStart + SplitPlan.minimumGap)
          }
          .offset(x: -10)
        case .split:
          ForEach(Array(model.clips.enumerated()), id: \.offset) { index, clip in
            Rectangle()
              .fill(model.removedClips.contains(index) ? Color.red.opacity(0.45) : Color.clear)
              .frame(width: max(x(clip.upperBound) - x(clip.lowerBound), 1), height: h)
              .offset(x: x(clip.lowerBound))
              .contentShape(Rectangle())
              .onTapGesture { model.toggleClip(index) }
              .accessibilityLabel(
                "Clip \(index + 1), \(model.removedClips.contains(index) ? "removed" : "kept")")
          }
          ForEach(model.splitPoints, id: \.self) { p in
            Capsule().fill(.white).frame(width: 3, height: h + 8).offset(x: x(p) - 1.5, y: -4).shadow(
              radius: 2
            )
            .allowsHitTesting(false)
          }
        case .frames:
          ForEach(model.frameTimes, id: \.self) { t in
            Image(systemName: "camera.fill").font(.caption2).foregroundStyle(.white).padding(3)
              .background(Color.accentColor, in: Circle())
              .offset(x: x(t) - 9, y: h - 20).allowsHitTesting(false)
          }
        case .redact:
          ForEach(Array(model.redactions.enumerated()), id: \.offset) { index, r in
            Capsule(style: .continuous)
              .fill(Color.accentColor.opacity(model.selectedRedaction == index ? 0.95 : 0.55))
              .frame(width: max(x(r.end) - x(r.start), 6), height: 12)
              .offset(x: x(r.start), y: h - 16)
              .onTapGesture { model.selectedRedaction = index }
              .accessibilityLabel("Redaction \(index + 1)")
          }
        case .crop:
          EmptyView()
        }

        // Playhead
        Capsule().fill(.white).frame(width: 2, height: h + 10).offset(x: x(model.time) - 1, y: -5)
          .shadow(color: .black.opacity(0.4), radius: 2).allowsHitTesting(false)
      }
      .coordinateSpace(name: "timeline")
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0).onChanged { v in
          model.seek(to: Double(min(max(v.location.x / w, 0), 1)) * duration)
        }
      )
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Video timeline. Drag to scrub.")
      .accessibilityValue(formatTime(model.time))
    }
    .padding(6)
    .glassPanel(cornerRadius: 20)
  }

  private func dim(from a: CGFloat, to b: CGFloat, height: CGFloat) -> some View {
    Rectangle().fill(.black.opacity(0.55)).frame(width: max(b - a, 0), height: height).offset(x: a)
      .allowsHitTesting(false)
  }

  /// A glass pill on the timeline; dragging reports the position as 0…1.
  private func handle(at xPos: CGFloat, height: CGFloat, width: CGFloat, onDrag: @escaping (Double) -> Void)
    -> some View
  {
    GeometryReader { _ in
      Color.clear
        .frame(width: 10, height: height + 6)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
    .frame(width: 10, height: height + 6)
    .offset(x: xPos, y: -3)
    .highPriorityGesture(
      DragGesture(coordinateSpace: .named("timeline")).onChanged { v in
        onDrag(Double(min(max(v.location.x / max(width, 1), 0), 1)))
      }
    )
    .accessibilityLabel("Drag the ends to trim")
  }
}

/// AVPlayer output without controls.
struct PlayerLayerView: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .none
    view.videoGravity = .resizeAspect
    view.player = player
    return view
  }

  func updateNSView(_ view: AVPlayerView, context: Context) {
    if view.player !== player { view.player = player }
  }
}

/// Dims everything outside the crop rectangle.
struct VideoCropShade: View {
  let rect: NormRect
  let size: CGSize

  var body: some View {
    let r = CGRect(
      x: rect.x * size.width, y: rect.y * size.height, width: rect.width * size.width,
      height: rect.height * size.height)
    Path { p in
      p.addRect(CGRect(origin: .zero, size: size))
      p.addRect(r)
    }
    .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
  }
}
