import DropCore
import SwiftUI

/// The image editor: the picture fills the window and the toolbar and inspector float over
/// it as glass panels, inset from the edges.
struct EditorView: View {
  @StateObject var model: EditorModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()
      canvas
        .padding(.top, 72)
        .padding(.trailing, 260)
        .padding([.leading, .bottom], 24)
      VStack {
        toolbar
        Spacer()
        if let result = model.saveResult {
          ResultCard(result: result, operation: "Edit image")
            .frame(maxWidth: 420)
            .morphTransition(reduceMotion: reduceMotion)
        }
      }
      .padding(DesignTokens.Spacing.inset)
      HStack {
        Spacer()
        inspector
          .frame(width: 236)
          .padding(.top, 64)
          .padding(DesignTokens.Spacing.inset)
      }
    }
    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: model.tool)
    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: model.saveResult)
  }

  // MARK: Toolbar

  private var toolbar: some View {
    HStack(spacing: 8) {
      GlassEffectContainer(spacing: 4) {
        HStack(spacing: 4) {
          ForEach(EditorTool.allCases) { tool in
            Button {
              withMorph(reduceMotion: reduceMotion) { model.tool = tool }
            } label: {
              Label(tool.title, systemImage: tool.systemImage)
                .font(.callout.weight(model.tool == tool ? .semibold : .regular))
                .foregroundStyle(
                  model.tool == tool ? Color(nsColor: .alternateSelectedControlTextColor) : .primary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                  if model.tool == tool {
                    Capsule(style: .continuous).fill(Color.accentColor)
                  }
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
            .accessibilityIdentifier("tool-\(tool.rawValue)")
          }
        }
        .padding(4)
        .glassPanel(cornerRadius: 999)
      }
      Button {
        model.rotate(clockwise: false)
      } label: {
        Image(systemName: "rotate.left")
      }
      .buttonStyle(.glass)
      .accessibilityLabel("Rotate left")
      Button {
        model.rotate(clockwise: true)
      } label: {
        Image(systemName: "rotate.right")
      }
      .buttonStyle(.glass)
      .accessibilityLabel("Rotate right")
      Button {
        model.undo()
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      .buttonStyle(.glass)
      .disabled(!model.canUndo)
      .keyboardShortcut("z")
      .accessibilityLabel("Undo")
      Spacer()
      Button("Save Copy") { model.save() }
        .buttonStyle(.glassProminent)
        .disabled(model.recipe.isIdentity)
        .keyboardShortcut("s")
        .accessibilityIdentifier("saveEdit")
    }
    .padding(.leading, 70)  // Clear the window's traffic lights.
  }

  // MARK: Inspector

  private var inspector: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.tool.title).font(.headline)
      switch model.tool {
      case .adjust:
        slider("Brightness", value: binding(\.brightness), range: EditRecipe.brightnessRange)
        slider("Contrast", value: binding(\.contrast), range: EditRecipe.contrastRange)
        slider("Saturation", value: binding(\.saturation), range: EditRecipe.saturationRange)
        Button("Reset") { model.resetAdjustments() }.buttonStyle(.glass)
      case .crop:
        Text("Drag over the image to choose the area to keep.").font(.callout).foregroundStyle(
          Color.secondary)
        if !model.batch.isEmpty {
          Toggle(
            "Use this crop, as the same share of each image, for all \(model.batch.count + 1) images",
            isOn: $model.applyCropToAll
          )
          .font(.callout)
        }
        if model.recipe.crop != nil {
          Button("Clear Crop") { model.commit { $0.crop = nil } }.buttonStyle(.glass)
        }
      case .annotate:
        annotateInspector
      case .redact:
        Text("Drag over anything you want hidden.").font(.callout).foregroundStyle(
          Color.secondary)
        Picker(
          "Style",
          selection: Binding(
            get: { model.recipe.redactStyle }, set: { s in model.commit { $0.redactStyle = s } })
        ) {
          Text("Solid").tag(RedactStyle.blackout)
          Text("Pixelate").tag(RedactStyle.pixelate)
          Text("Blur").tag(RedactStyle.blur)
        }
        .pickerStyle(.segmented)
        if model.recipe.redactStyle != .blackout {
          Text("Blur and pixelate soften details. Use Solid for sensitive information.")
            .font(.caption).foregroundStyle(Color.orange)
        }
        if !model.recipe.redactions.isEmpty {
          Button("Clear Redactions") { model.commit { $0.redactions = [] } }.buttonStyle(.glass)
        }
      }
      Spacer(minLength: 0)
      Text(model.url.lastPathComponent).font(.caption).foregroundStyle(Color.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .glassCard()
  }

  private var annotateInspector: some View {
    VStack(alignment: .leading, spacing: 10) {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
        ForEach(AnnotateKind.allCases) { kind in
          Button {
            model.annotateKind = kind
          } label: {
            VStack(spacing: 2) {
              Image(systemName: kind.systemImage).font(.body)
              Text(kind.title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(
              model.annotateKind == kind ? Color(nsColor: .alternateSelectedControlTextColor) : .primary
            )
            .background(
              model.annotateKind == kind
                ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear),
              in: RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(kind.title)
          .accessibilityAddTraits(model.annotateKind == kind ? .isSelected : [])
        }
      }
      Text(model.annotateKind.hint).font(.callout).foregroundStyle(Color.secondary)
      if model.annotateKind != .magnifier && model.annotateKind != .sticker {
        ColorPicker("Colour", selection: $model.strokeColor, supportsOpacity: false)
      }
      switch model.annotateKind {
      case .draw, .arrow:
        slider("Line width", value: $model.strokeWidth, range: 0.003...0.04)
      case .rectangle, .ellipse:
        Toggle("Filled", isOn: $model.shapeFilled)
        if !model.shapeFilled { slider("Line width", value: $model.strokeWidth, range: 0.003...0.04) }
      case .text:
        TextField("Text", text: $model.textDraft, axis: .vertical).lineLimit(1...4)
        slider("Size", value: $model.textSize, range: 0.02...0.2)
      case .callout:
        Text("Next number: \(model.nextCalloutNumber)").font(.callout).monospacedDigit()
      case .magnifier:
        slider("Zoom", value: $model.magnifierZoom, range: 1.5...6)
      case .sticker:
        Button(model.stickerPath == nil ? "Choose Image…" : "Change Image…") { model.chooseSticker() }
          .buttonStyle(.glass)
        if let path = model.stickerPath {
          Text(URL(fileURLWithPath: path).lastPathComponent).font(.caption).lineLimit(1).truncationMode(
            .middle)
        }
      case .highlight:
        EmptyView()
      }
      if !model.recipe.strokes.isEmpty || !model.recipe.marks.isEmpty {
        Button("Clear Annotations") {
          model.commit {
            $0.strokes = []
            $0.marks = []
          }
        }
        .buttonStyle(.glass)
      }
    }
  }

  private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.callout)
      Slider(value: value, in: range).accessibilityLabel(title)
    }
  }

  /// A binding into the recipe that records one undo step when the slider starts moving.
  private func binding(_ keyPath: WritableKeyPath<EditRecipe, Double>) -> Binding<Double> {
    Binding(
      get: { model.recipe[keyPath: keyPath] },
      set: { model.recipe[keyPath: keyPath] = $0 })
  }

  // MARK: Canvas

  private var canvas: some View {
    GeometryReader { geo in
      if let image = model.preview {
        let fitted = fit(CGSize(width: image.width, height: image.height), in: geo.size)
        ZStack(alignment: .topLeading) {
          Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: fitted.width, height: fitted.height)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous))
          overlays(size: fitted)
        }
        .frame(width: fitted.width, height: fitted.height)
        .contentShape(Rectangle())
        .gesture(dragGesture(size: fitted))
        .position(x: geo.size.width / 2, y: geo.size.height / 2)
        .accessibilityElement()
        .accessibilityLabel("Image canvas, \(model.tool.title) tool")
      } else if let error = model.loadError {
        Text(error).foregroundStyle(Color.secondary).frame(
          maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  @ViewBuilder
  private func overlays(size: CGSize) -> some View {
    if let crop = model.dragRect.flatMap({ model.tool == .crop ? $0 : nil }) ?? model.recipe.crop {
      CropShade(rect: crop, size: size).allowsHitTesting(false)
    }
    if model.tool == .annotate, let rect = model.dragRect {
      let box = CGRect(
        x: rect.x * size.width, y: rect.y * size.height, width: rect.width * size.width,
        height: rect.height * size.height)
      Group {
        if model.annotateKind == .ellipse {
          Ellipse().stroke(model.strokeColor, lineWidth: 2)
        } else if model.annotateKind == .highlight {
          Rectangle().fill(model.strokeColor.opacity(0.35))
        } else {
          Rectangle().stroke(model.strokeColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
      }
      .frame(width: box.width, height: box.height)
      .offset(x: box.minX, y: box.minY)
      .allowsHitTesting(false)
    }
    if model.tool == .annotate, let (a, b) = model.dragLine {
      Path { p in
        p.move(to: CGPoint(x: a.x * size.width, y: a.y * size.height))
        p.addLine(to: CGPoint(x: b.x * size.width, y: b.y * size.height))
      }
      .stroke(
        model.strokeColor,
        style: StrokeStyle(
          lineWidth: 3, lineCap: .round, dash: model.annotateKind == .magnifier ? [5, 5] : [])
      )
      .allowsHitTesting(false)
    }
    if model.tool == .redact, let rect = model.dragRect {
      Rectangle()
        .fill(.black.opacity(0.6))
        .frame(width: rect.width * size.width, height: rect.height * size.height)
        .offset(x: rect.x * size.width, y: rect.y * size.height)
        .allowsHitTesting(false)
    }
    if let stroke = model.inProgressStroke {
      Path { p in
        let points = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = points.first else { return }
        p.move(to: first)
        for point in points.dropFirst() { p.addLine(to: point) }
      }
      .stroke(
        model.strokeColor,
        style: StrokeStyle(
          lineWidth: stroke.width * min(size.width, size.height), lineCap: .round, lineJoin: .round)
      )
      .allowsHitTesting(false)
    }
  }

  private func dragGesture(size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        model.dragChanged(from: norm(value.startLocation, size), to: norm(value.location, size))
      }
      .onEnded { _ in model.dragEnded() }
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

/// Dims everything outside the crop rectangle.
private struct CropShade: View {
  let rect: NormRect
  let size: CGSize

  var body: some View {
    let r = CGRect(
      x: rect.x * size.width, y: rect.y * size.height, width: rect.width * size.width,
      height: rect.height * size.height)
    ZStack(alignment: .topLeading) {
      Path { p in
        p.addRect(CGRect(origin: .zero, size: size))
        p.addRect(r)
      }
      .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
      Rectangle()
        .strokeBorder(.white, lineWidth: 1.5)
        .frame(width: r.width, height: r.height)
        .offset(x: r.minX, y: r.minY)
    }
  }
}
