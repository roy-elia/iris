import AppKit
import DropCore
import ImageIO
import PDFKit
import SwiftUI

// MARK: Shared chrome

/// A tool window's floating glass panel: title, the files it acts on, the tool's
/// controls, and Cancel plus a primary action.
struct ToolPanel<Content: View>: View {
  let title: String
  let urls: [URL]
  let primaryTitle: String
  var primaryDisabled = false
  let onPrimary: () -> Void
  @ViewBuilder let content: Content

  @Environment(\.dismissToolWindow) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.title3.weight(.semibold))
        Text(subtitle).font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
          .lineLimit(1).truncationMode(.middle)
      }
      content
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .buttonStyle(.glass)
          .keyboardShortcut(.cancelAction)
        Button(primaryTitle) {
          onPrimary()
          dismiss()
        }
        .buttonStyle(.glassProminent)
        .tint(DesignTokens.Palette.accentFill)
        .disabled(primaryDisabled)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .glassPanel(cornerRadius: DesignTokens.Radius.window)
    .padding(DesignTokens.Spacing.inset)
  }

  private var subtitle: String {
    urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
  }
}

private struct DismissToolWindowKey: EnvironmentKey {
  static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
  /// Closes the tool window this view is in. (Written by hand: no `@Entry` without Xcode.)
  var dismissToolWindow: @MainActor () -> Void {
    get { self[DismissToolWindowKey.self] }
    set { self[DismissToolWindowKey.self] = newValue }
  }
}

/// Runs an operation from a tool window; the result shows as a toast.
@MainActor
private func runTool(_ operation: FileOperation, on urls: [URL]) {
  let files = urls.compactMap { try? DroppedFile.load($0) }
  AppModel.shared.run(operation, on: files, origin: .overlay)
}

/// Small previews, loaded off the main thread.
enum Thumbnailer {
  static func thumbnail(_ url: URL, maxPixels: Int) -> CGImage? {
    guard let readable = try? ImageInput.readableURL(for: url),
      let source = CGImageSourceCreateWithURL(readable as CFURL, nil)
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// Writes a thumbnail to the temp folder, for renderers that take file URLs.
  static func thumbnailFile(_ url: URL, maxPixels: Int) -> URL? {
    guard let image = thumbnail(url, maxPixels: maxPixels) else { return nil }
    let out = FileManager.default.temporaryDirectory
      .appendingPathComponent("fdu-thumb-\(UUID().uuidString)").appendingPathExtension("png")
    return (try? ImageOps.write(image, as: .png, quality: 1, to: out)).map { out }
  }
}

/// A still "loading" line for tool windows, which size themselves to their content.
struct LoadingLabel: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Label("\(text)…", systemImage: "hourglass")
      .font(.callout)
      .foregroundStyle(DesignTokens.Palette.secondaryText)
  }
}

/// A rendered preview in a rounded frame, with a spinner until it's ready.
private struct PreviewImage: View {
  let image: CGImage?
  var height: CGFloat = 240

  var body: some View {
    ZStack {
      if let image {
        Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
      } else {
        LoadingLabel("Rendering preview")
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .background(
      .black.opacity(0.12),
      in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
    )
    .accessibilityLabel("Preview")
  }
}

extension Color {
  var rgba: RGBA {
    let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
    return RGBA(
      red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent),
      alpha: Double(ns.alphaComponent))
  }

  init(_ rgba: RGBA) {
    self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
  }
}

// MARK: Compress

struct CompressView: View {
  enum Mode: String, CaseIterable {
    case preset = "Preset"
    case target = "Target size"
  }
  enum Preset: Double, CaseIterable, Identifiable {
    case smaller = 0.45
    case balanced = 0.6
    case quality = 0.8
    var id: Double { rawValue }
    var title: String {
      switch self {
      case .smaller: "Smallest"
      case .balanced: "Balanced"
      case .quality: "Best quality"
      }
    }
    var detail: String {
      switch self {
      case .smaller: "Much smaller files; some visible softening."
      case .balanced: "Smaller files with little visible change."
      case .quality: "Modest savings with no visible change."
      }
    }
  }
  enum Unit: Int64, CaseIterable {
    case kb = 1024
    case mb = 1_048_576
  }

  let urls: [URL]
  @State private var mode: Mode = .preset
  @State private var preset: Preset = .balanced
  @State private var strength: VideoStrength = .medium

  private var isVideo: Bool { urls.allSatisfy { FileKind(url: $0).isVideo } }
  @State private var amount: Double = 500
  @State private var unit: Unit = .kb

  private var originalTotal: Int64 { urls.reduce(0) { $0 + CompressOpsSize.of($1) } }
  private var targetBytes: Int64 { Int64(amount * Double(unit.rawValue)) }
  private var targetError: String? {
    guard mode == .target else { return nil }
    if targetBytes < TargetSizeOps.minimumTarget { return "Enter a target size of at least 1 KB." }
    if let smallest = urls.map(CompressOpsSize.of).min(), targetBytes >= smallest {
      return "Target size cannot exceed the original file size."
    }
    return nil
  }

  var body: some View {
    ToolPanel(
      title: "Compress", urls: urls, primaryTitle: "Compress", primaryDisabled: targetError != nil
    ) {
      switch (isVideo, mode) {
      case (true, .preset): runTool(.compressVideo(.strength(strength)), on: urls)
      case (true, .target): runTool(.compressVideo(.target(bytes: targetBytes)), on: urls)
      case (false, .preset): runTool(.compress(quality: preset.rawValue), on: urls)
      case (false, .target): runTool(.compressToSize(bytes: targetBytes), on: urls)
      }
    } content: {
      Picker("Mode", selection: $mode) {
        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      if mode == .preset && isVideo {
        Picker("Strength", selection: $strength) {
          ForEach(VideoStrength.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        Text(
          "Re-encodes with Apple's hardware H.264 encoder. Stronger means smaller files with more visible loss."
        )
        .font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
      } else if mode == .preset {
        Picker("Preset", selection: $preset) {
          ForEach(Preset.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        Text(preset.detail).font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
      } else {
        HStack {
          TextField("Size", value: $amount, format: .number.precision(.fractionLength(0...1)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            .accessibilityLabel("Target file size")
          Picker("Unit", selection: $unit) {
            Text("KB").tag(Unit.kb)
            Text("MB").tag(Unit.mb)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
        }
        Text("Each file is compressed to this size or below, separately.")
          .font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
        if let targetError {
          Text(targetError).font(.callout).foregroundStyle(DesignTokens.Palette.errorText)
        }
      }
      Text("Original: \(ByteCountFormatter.string(fromByteCount: originalTotal, countStyle: .file))")
        .font(.caption).foregroundStyle(DesignTokens.Palette.secondaryText)
    }
    .frame(width: 400)
  }
}

enum CompressOpsSize {
  static func of(_ url: URL) -> Int64 {
    ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
  }
}

// MARK: Metadata

struct MetadataView: View {
  let urls: [URL]
  @State private var fields: [MetadataField] = []
  @State private var values: [String: String] = [:]
  @State private var original: [String: String] = [:]
  @State private var removeLocation = false
  @State private var loading = true
  @State private var showAll = false

  private var canEdit: Bool { ToolLocator.isAvailable(.exiftool) }
  private var hasLocation: Bool {
    fields.contains { $0.group.hasPrefix("GPS") || $0.group == "Composite" && $0.tag.hasPrefix("GPS") }
  }
  private var edits: [MetadataEdit] {
    var list = EditableField.all.compactMap { field -> MetadataEdit? in
      let new = values[field.tag, default: ""]
      return new == original[field.tag, default: ""] ? nil : MetadataEdit(tag: field.tag, value: new)
    }
    if removeLocation { list.append(.removeLocation) }
    return list
  }

  var body: some View {
    ToolPanel(title: "Metadata", urls: urls, primaryTitle: "Save Copy", primaryDisabled: edits.isEmpty) {
      runTool(.editMetadata(edits), on: urls)
    } content: {
      if loading {
        LoadingLabel("Loading file details").frame(maxWidth: .infinity)
      } else {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
          ForEach(EditableField.all) { field in
            GridRow {
              Text(field.label).font(.callout)
              TextField(field.label, text: binding(field.tag))
                .textFieldStyle(.roundedBorder)
                .disabled(!canEdit)
                .accessibilityLabel(field.label)
            }
          }
        }
        Toggle("Remove location", isOn: $removeLocation)
          .disabled(!hasLocation || !canEdit)
        if urls.count > 1 {
          Text("Changes apply to all \(urls.count) files. Values shown are from the first.")
            .font(.caption).foregroundStyle(DesignTokens.Palette.secondaryText)
        }
        DisclosureGroup("All metadata (\(fields.count) fields)", isExpanded: $showAll) {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
              ForEach(fields) { field in
                HStack(alignment: .firstTextBaseline) {
                  Text("\(field.group) · \(field.tag)").font(.caption.weight(.medium)).frame(
                    width: 150, alignment: .leading)
                  Text(field.value).font(.caption).textSelection(.enabled).lineLimit(3)
                  Spacer(minLength: 0)
                }
              }
            }
          }
          .frame(height: 180)
        }
        .font(.callout)
        Button("Strip All Metadata") {
          runTool(.stripMetadata, on: urls)
        }
        .buttonStyle(.glass)
      }
    }
    .frame(width: 440)
    .task { await load() }
  }

  private func binding(_ tag: String) -> Binding<String> {
    Binding(get: { values[tag, default: ""] }, set: { values[tag] = $0 })
  }

  private func load() async {
    guard let first = urls.first else { return }
    let read = (try? await MetadataOps.read(first)) ?? []
    fields = read
    for field in EditableField.all {
      let value = MetadataOps.value(of: field, in: read) ?? ""
      values[field.tag] = value
      original[field.tag] = value
    }
    loading = false
  }
}

// MARK: Background

struct BackgroundView: View {
  enum Mode: String, CaseIterable {
    case remove = "Remove"
    case color = "Colour"
    case image = "Image"
  }
  let urls: [URL]
  @State private var mode: Mode = .remove
  @State private var color: Color = .white
  @State private var imagePath: String?

  private var fill: BackgroundFill? {
    switch mode {
    case .remove: .transparent
    case .color: .color(color.rgba)
    case .image: imagePath.map { .image(path: $0) }
    }
  }

  var body: some View {
    ToolPanel(
      title: "Background", urls: urls,
      primaryTitle: mode == .remove ? "Remove Background" : "Save with Background",
      primaryDisabled: fill == nil
    ) {
      if let fill { runTool(.replaceBackground(fill), on: urls) }
    } content: {
      Picker("Background", selection: $mode) {
        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      switch mode {
      case .remove:
        Text("Lifts the subject onto a transparent background (PNG).")
          .font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
      case .color:
        ColorPicker("Colour", selection: $color, supportsOpacity: false)
      case .image:
        HStack {
          Button(imagePath == nil ? "Choose Image…" : "Change Image…") { chooseImage() }.buttonStyle(.glass)
          if let imagePath {
            Text(URL(fileURLWithPath: imagePath).lastPathComponent).font(.callout).lineLimit(1)
              .truncationMode(.middle)
          }
        }
      }
    }
    .frame(width: 380)
  }

  private func chooseImage() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.message = "Choose a background image."
    NSApp.activate()
    if panel.runModal() == .OK, let url = panel.url { imagePath = url.path }
  }
}

// MARK: Frame

struct FrameView: View {
  let urls: [URL]
  @State private var recipe = FrameRecipe()
  @State private var preview: CGImage?
  @State private var source: CGImage?
  @State private var presetName = FramePreset.all[0].name

  var body: some View {
    ToolPanel(title: "Frame", urls: urls, primaryTitle: "Save Framed Copy") {
      runTool(.frame(recipe), on: urls)
    } content: {
      PreviewImage(image: preview)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(FramePreset.all) { preset in
            Button {
              presetName = preset.name
              recipe.background = preset.background
            } label: {
              VStack(spacing: 4) {
                Circle().fill(swatch(preset.background)).frame(width: 30, height: 30)
                  .overlay {
                    if presetName == preset.name {
                      Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .shadow(radius: 1)
                    }
                  }
                Text(preset.name).font(.caption2)
              }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(preset.name) background")
            .accessibilityAddTraits(presetName == preset.name ? .isSelected : [])
          }
        }
      }
      LabeledSlider(title: "Padding", value: $recipe.padding, range: 0...0.3)
      LabeledSlider(title: "Corners", value: $recipe.cornerRadius, range: 0...0.2)
      HStack {
        Toggle("Shadow", isOn: $recipe.shadow)
        Spacer()
        Picker("Shape", selection: $recipe.ratio) {
          ForEach(FrameRatio.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        .fixedSize()
      }
    }
    .frame(width: 440)
    .task {
      let url = urls[0]
      source = await Task.detached { Thumbnailer.thumbnail(url, maxPixels: 700) }.value
      render()
    }
    .onChange(of: recipe) { render() }
  }

  private func render() {
    guard let source else { return }
    let recipe = recipe
    Task {
      preview = await Task.detached { try? FrameOps.render(source, recipe: recipe) }.value
    }
  }

  private func swatch(_ background: FrameBackground) -> AnyShapeStyle {
    switch background {
    case .transparent: AnyShapeStyle(Color.gray.opacity(0.3))
    case .solid(let c): AnyShapeStyle(Color(c))
    case .linear(let a, let b):
      AnyShapeStyle(
        LinearGradient(colors: [Color(a), Color(b)], startPoint: .topLeading, endPoint: .bottomTrailing))
    case .radial(let a, let b):
      AnyShapeStyle(
        RadialGradient(colors: [Color(a), Color(b)], center: .center, startRadius: 0, endRadius: 20))
    case .image: AnyShapeStyle(Color.gray)
    }
  }
}

// MARK: Split PDF

struct SplitPDFView: View {
  enum Mode: String, CaseIterable {
    case every = "Every page"
    case ranges = "Page ranges"
  }

  let urls: [URL]
  @State private var mode: Mode = .every
  @State private var ranges = ""
  @State private var pageCount: Int?

  private var plan: PDFSplit { mode == .every ? .everyPage : .ranges(ranges) }
  /// Why the ranges can't be used, checked against the first PDF's page count.
  private var problem: String? {
    guard mode == .ranges, let pageCount else { return nil }
    do {
      _ = try plan.groups(pageCount: pageCount)
      return nil
    } catch {
      return (error as? LocalizedError)?.errorDescription ?? "Check the page ranges."
    }
  }

  var body: some View {
    ToolPanel(title: "Split PDF", urls: urls, primaryTitle: "Split", primaryDisabled: problem != nil) {
      runTool(.splitPDF(plan), on: urls)
    } content: {
      Picker("Mode", selection: $mode) {
        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      if mode == .ranges {
        TextField("Pages, such as 1-3, 7, 9-", text: $ranges)
          .textFieldStyle(.roundedBorder)
        Text(problem ?? "Each range becomes its own PDF. A range ending in \"-\" runs to the last page.")
          .font(.callout)
          .foregroundStyle(
            problem == nil ? DesignTokens.Palette.secondaryText : DesignTokens.Palette.errorText)
      } else if let pageCount {
        Text("Makes \(pageCount) PDF\(pageCount == 1 ? "" : "s"), one per page.")
          .font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
      }
    }
    .frame(width: 400)
    .task {
      let url = urls[0]
      pageCount = await Task.detached { PDFDocument(url: url)?.pageCount }.value
    }
  }
}

// MARK: Resize

struct ResizeView: View {
  enum Mode: String, CaseIterable {
    case edge = "Longest side"
    case percent = "Percentage"
  }

  let urls: [URL]
  @State private var mode: Mode = .edge
  @State private var edge = 1600
  @State private var percent = 50.0
  @State private var sourceSize: (width: Int, height: Int)?

  private var spec: ResizeSpec { mode == .edge ? .maxEdge(edge) : .percent(percent) }
  private var isValid: Bool {
    mode == .edge ? ResizeSpec.edgeRange.contains(edge) : ResizeSpec.percentRange.contains(percent)
  }

  var body: some View {
    ToolPanel(title: "Resize", urls: urls, primaryTitle: "Save Resized Copy", primaryDisabled: !isValid) {
      runTool(.resize(spec), on: urls)
    } content: {
      Picker("Mode", selection: $mode) {
        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      HStack {
        if mode == .edge {
          TextField("Pixels", value: $edge, format: .number).frame(width: 90)
          Text("px")
        } else {
          TextField("Percent", value: $percent, format: .number).frame(width: 90)
          Text("%")
        }
        Spacer()
        if let size = sourceSize, isValid {
          let new = spec.size(width: size.width, height: size.height)
          Text("\(size.width)×\(size.height) → \(new.width)×\(new.height)")
            .font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
        }
      }
      .textFieldStyle(.roundedBorder)
    }
    .frame(width: 400)
    .task {
      let url = urls[0]
      sourceSize = await Task.detached {
        (try? ImageInput.readableURL(for: url)).flatMap { try? ImageOps.loadOriented($0) }
          .map { ($0.width, $0.height) }
      }.value
    }
  }
}

private struct LabeledSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>

  var body: some View {
    HStack {
      Text(title).font(.callout).frame(width: 70, alignment: .leading)
      Slider(value: $value, in: range).accessibilityLabel(title)
    }
  }
}

// MARK: Collage

struct CollageView: View {
  let urls: [URL]
  @State private var recipe = CollageRecipe()
  @State private var autoColumns = true
  @State private var columns = 2
  @State private var background: Color = .white
  @State private var thumbs: [URL] = []
  @State private var preview: CGImage?

  var body: some View {
    ToolPanel(title: "Collage", urls: urls, primaryTitle: "Create Collage") {
      runTool(.collage(effectiveRecipe), on: urls)
    } content: {
      PreviewImage(image: preview, height: 260)
      HStack {
        Toggle("Automatic grid", isOn: $autoColumns)
        Spacer()
        Stepper("\(columns) columns", value: $columns, in: 1...max(urls.count, 1))
          .disabled(autoColumns)
          .fixedSize()
      }
      LabeledSlider(title: "Spacing", value: $recipe.spacing, range: 0...0.08)
      LabeledSlider(title: "Corners", value: $recipe.cornerRadius, range: 0...0.3)
      HStack {
        Picker("Images", selection: $recipe.fill) {
          Text("Fill cells").tag(CollageFill.fill)
          Text("Fit whole images").tag(CollageFill.fit)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        ColorPicker("Background", selection: $background, supportsOpacity: true).labelsHidden()
      }
      HStack {
        Toggle("Order by name", isOn: $recipe.orderByName)
        Spacer()
        Picker("Width", selection: $recipe.width) {
          Text("1200 px").tag(1200)
          Text("2400 px").tag(2400)
          Text("4000 px").tag(4000)
        }
        .pickerStyle(.menu)
        .fixedSize()
      }
    }
    .frame(width: 460)
    .task {
      let urls = urls
      thumbs = await Task.detached { urls.compactMap { Thumbnailer.thumbnailFile($0, maxPixels: 500) } }.value
      render()
    }
    .onChange(of: effectiveRecipe) { render() }
  }

  private var effectiveRecipe: CollageRecipe {
    var r = recipe
    r.columns = autoColumns ? nil : columns
    r.background = background.rgba
    return r
  }

  private func render() {
    guard thumbs.count >= 2 else { return }
    var r = effectiveRecipe
    r.width = 900
    // Thumbnails have temp names; keep the user's order setting by mapping names.
    let ordered =
      r.orderByName
      ? zip(urls, thumbs).sorted {
        $0.0.lastPathComponent.localizedStandardCompare($1.0.lastPathComponent) == .orderedAscending
      }.map(\.1)
      : thumbs
    r.orderByName = false
    let recipe = r
    Task { preview = await Task.detached { try? CollageOps.render(ordered, recipe: recipe) }.value }
  }
}

// MARK: QR results

struct QRResultsView: View {
  let codes: [String]
  @Environment(\.dismissToolWindow) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(codes.count == 1 ? "QR Code" : "\(codes.count) QR Codes").font(.title3.weight(.semibold))
      ForEach(Array(codes.enumerated()), id: \.offset) { _, code in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "qrcode").foregroundStyle(DesignTokens.Palette.accentText).accessibilityHidden(
            true)
          Text(code).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
          if let url = URL(string: code), url.scheme?.hasPrefix("http") == true {
            Button("Open") { NSWorkspace.shared.open(url) }.buttonStyle(.glass)
          }
          Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
          }
          .buttonStyle(.glass)
        }
        .padding(10)
        .background(
          .black.opacity(0.06),
          in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous))
      }
      HStack {
        Spacer()
        Button("Done") { dismiss() }.buttonStyle(.glassProminent).tint(DesignTokens.Palette.accentFill)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 420)
    .glassPanel(cornerRadius: DesignTokens.Radius.window)
    .padding(DesignTokens.Spacing.inset)
  }
}

// MARK: Join

struct JoinView: View {
  @State var urls: [URL]

  init(urls: [URL]) {
    _urls = State(initialValue: urls)
  }

  var body: some View {
    ToolPanel(title: "Join Videos", urls: urls, primaryTitle: "Join", primaryDisabled: urls.count < 2) {
      runTool(.joinVideos, on: urls)
    } content: {
      Text("Plays in this order. Different sizes are fitted to the first video's frame.")
        .font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
      VStack(spacing: 6) {
        ForEach(Array(urls.enumerated()), id: \.element) { index, url in
          HStack(spacing: 10) {
            Text("\(index + 1)").font(.callout.monospacedDigit().weight(.semibold)).frame(width: 18)
            Image(systemName: "film").foregroundStyle(DesignTokens.Palette.accentText).accessibilityHidden(
              true)
            Text(url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button {
              urls.swapAt(index, index - 1)
            } label: {
              Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain).disabled(index == 0).accessibilityLabel("Move \(url.lastPathComponent) up")
            Button {
              urls.swapAt(index, index + 1)
            } label: {
              Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain).disabled(index == urls.count - 1).accessibilityLabel(
              "Move \(url.lastPathComponent) down")
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(.black.opacity(0.06), in: Capsule(style: .continuous))
        }
      }
    }
    .frame(width: 420)
  }
}

// MARK: Visualizer

struct VisualizerView: View {
  enum Backdrop: String, CaseIterable {
    case color = "Colour"
    case image = "Image"
  }
  let urls: [URL]
  @State private var style: VisualizerStyle = .wave
  @State private var size: VisualizerSize = .landscape
  @State private var waveColor: Color = .white
  @State private var backdrop: Backdrop = .color
  @State private var backgroundColor = Color(red: 0.05, green: 0.12, blue: 0.16)
  @State private var imagePath: String?

  private var recipe: VisualizerRecipe {
    VisualizerRecipe(
      style: style, size: size, color: waveColor.rgba, backgroundImage: backdrop == .image ? imagePath : nil,
      backgroundColor: backgroundColor.rgba)
  }

  var body: some View {
    ToolPanel(
      title: "Visualizer", urls: urls, primaryTitle: urls.count == 1 ? "Make Video" : "Make Videos",
      primaryDisabled: backdrop == .image && imagePath == nil
    ) {
      runTool(.audioVisualizer(recipe), on: urls)
    } content: {
      Text("Makes an MP4 of the sound moving over a still background.")
        .font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
        GridRow {
          Text("Style")
          Picker("Style", selection: $style) {
            ForEach(VisualizerStyle.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented).labelsHidden()
        }
        GridRow {
          Text("Shape")
          Picker("Shape", selection: $size) {
            ForEach(VisualizerSize.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented).labelsHidden()
        }
        GridRow {
          Text("Wave")
          ColorPicker("Wave colour", selection: $waveColor, supportsOpacity: false).labelsHidden()
            .disabled(style == .spectrum)
            .help(style == .spectrum ? "The spectrum uses its own colours." : "")
        }
        GridRow {
          Text("Behind")
          Picker("Background", selection: $backdrop) {
            ForEach(Backdrop.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented).labelsHidden()
        }
      }
      switch backdrop {
      case .color:
        ColorPicker("Background colour", selection: $backgroundColor, supportsOpacity: false)
      case .image:
        HStack {
          Button(imagePath == nil ? "Choose Image…" : "Change Image…") { chooseImage() }.buttonStyle(.glass)
          if let imagePath {
            Text(URL(fileURLWithPath: imagePath).lastPathComponent).font(.callout).lineLimit(1)
              .truncationMode(.middle)
          }
        }
      }
    }
    .frame(width: 400)
  }

  private func chooseImage() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.message = "Choose an image to show behind the waveform."
    NSApp.activate()
    if panel.runModal() == .OK, let url = panel.url { imagePath = url.path }
  }
}
