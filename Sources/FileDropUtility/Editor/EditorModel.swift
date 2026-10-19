import AppKit
import DropCore
import ImageIO
import SwiftUI

/// What a drag does in the Annotate tool.
enum AnnotateKind: String, CaseIterable, Identifiable {
  case draw, arrow, rectangle, ellipse, highlight, text, callout, magnifier, sticker
  var id: String { rawValue }

  var title: String {
    switch self {
    case .draw: "Draw"
    case .arrow: "Arrow"
    case .rectangle: "Rectangle"
    case .ellipse: "Ellipse"
    case .highlight: "Highlight"
    case .text: "Text"
    case .callout: "Number"
    case .magnifier: "Magnifier"
    case .sticker: "Image"
    }
  }

  var systemImage: String {
    switch self {
    case .draw: "scribble"
    case .arrow: "arrow.up.right"
    case .rectangle: "rectangle"
    case .ellipse: "circle"
    case .highlight: "highlighter"
    case .text: "textformat"
    case .callout: "1.circle.fill"
    case .magnifier: "plus.magnifyingglass"
    case .sticker: "photo.badge.plus"
    }
  }

  var hint: String {
    switch self {
    case .draw: "Drag on the image to draw."
    case .arrow: "Drag from the tail toward the arrowhead."
    case .rectangle, .ellipse: "Drag to draw the shape."
    case .highlight: "Drag over the image to highlight."
    case .text: "Type your text, then click where it goes."
    case .callout: "Click to add numbered callouts."
    case .magnifier: "Drag from the detail to where the bubble goes."
    case .sticker: "Choose an image, then drag where to place it."
    }
  }
}

/// State for one editor window. The preview is rendered from a downscaled copy; the saved
/// file is rendered from the original at full size with the same normalised recipe.
@MainActor
final class EditorModel: ObservableObject {
  let url: URL
  @Published var tool: EditorTool
  @Published var recipe = EditRecipe() {
    didSet { schedulePreview() }
  }
  @Published private(set) var preview: CGImage?
  @Published var strokeColor: Color = .red
  @Published var strokeWidth: Double = 0.012
  @Published var inProgressStroke: Stroke?
  @Published var dragRect: NormRect?
  /// Start and current point of a line-like drag (arrow, magnifier).
  @Published var dragLine: (NormPoint, NormPoint)?
  @Published var annotateKind: AnnotateKind = .draw
  @Published var shapeFilled = false
  @Published var textDraft = ""
  @Published var textSize: Double = 0.06
  @Published var magnifierZoom: Double = 2.5
  @Published var stickerPath: String?
  /// Other images dropped with this one; Crop can apply to all of them.
  let batch: [URL]
  @Published var applyCropToAll = true
  @Published var saveResult: OperationResult?
  @Published var loadError: String?

  private var history: [EditRecipe] = []
  private var previewSource: URL?
  private var renderTask: Task<Void, Never>?

  init(url: URL, tool: EditorTool, batch: [URL] = []) {
    self.url = url
    self.tool = tool
    self.batch = batch.filter { $0 != url }
    preparePreviewSource()
  }

  var canUndo: Bool { !history.isEmpty }

  /// The recipe shown on the canvas. Crop is drawn as an overlay, not applied.
  private var previewRecipe: EditRecipe {
    var r = recipe
    r.crop = nil
    return r
  }

  // MARK: Editing

  func commit(_ change: (inout EditRecipe) -> Void) {
    history.append(recipe)
    if history.count > 50 { history.removeFirst() }
    change(&recipe)
  }

  func undo() {
    guard let last = history.popLast() else { return }
    recipe = last
  }

  func rotate(clockwise: Bool) {
    commit {
      $0.quarterTurns += clockwise ? 1 : -1
      // Rects and strokes refer to the old orientation; clear them rather than guess.
      $0.redactions = []
      $0.strokes = []
      $0.marks = []
      $0.crop = nil
    }
  }

  func resetAdjustments() {
    commit {
      $0.brightness = 0
      $0.contrast = 1
      $0.saturation = 1
    }
  }

  // MARK: Canvas gestures (normalised points)

  var nextCalloutNumber: Int {
    recipe.marks.reduce(0) { n, mark in
      if case .callout(let number, _, _, _) = mark { return max(n, number) }
      return n
    } + 1
  }

  func dragChanged(from start: NormPoint, to current: NormPoint) {
    switch tool {
    case .crop, .redact:
      dragRect = NormRect(from: start, to: current)
    case .annotate:
      switch annotateKind {
      case .draw:
        if inProgressStroke == nil {
          inProgressStroke = Stroke(points: [start], color: rgba(strokeColor), width: strokeWidth)
        }
        inProgressStroke?.points.append(current)
      case .arrow, .magnifier:
        dragLine = (start, current)
      case .rectangle, .ellipse, .highlight, .sticker:
        dragRect = NormRect(from: start, to: current)
      case .text, .callout:
        dragLine = (current, current)
      }
    case .adjust:
      break
    }
  }

  func dragEnded() {
    defer {
      dragRect = nil
      dragLine = nil
      inProgressStroke = nil
    }
    switch tool {
    case .crop:
      if let rect = dragRect, !rect.isEmpty { commit { $0.crop = rect } }
    case .redact:
      if let rect = dragRect, !rect.isEmpty { commit { $0.redactions.append(rect) } }
    case .annotate:
      if let mark = pendingMark() { commit { $0.marks.append(mark) } }
      if let stroke = inProgressStroke { commit { $0.strokes.append(stroke) } }
    case .adjust:
      break
    }
  }

  /// The mark the finished drag describes, if any.
  private func pendingMark() -> Mark? {
    let color = rgba(strokeColor)
    switch annotateKind {
    case .draw:
      return nil
    case .arrow:
      guard let (a, b) = dragLine, hypot(b.x - a.x, b.y - a.y) > 0.01 else { return nil }
      return .arrow(from: a, to: b, color: color, width: strokeWidth)
    case .rectangle:
      guard let r = dragRect, !r.isEmpty else { return nil }
      return .rectangle(r, color: color, width: strokeWidth, filled: shapeFilled)
    case .ellipse:
      guard let r = dragRect, !r.isEmpty else { return nil }
      return .ellipse(r, color: color, width: strokeWidth, filled: shapeFilled)
    case .highlight:
      guard let r = dragRect, !r.isEmpty else { return nil }
      return .highlight(r, color: color)
    case .text:
      let text = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let (p, _) = dragLine, !text.isEmpty else { return nil }
      return .text(text, at: p, color: color, size: textSize, boxWidth: min(0.6, 1 - p.x))
    case .callout:
      guard let (p, _) = dragLine else { return nil }
      return .callout(number: nextCalloutNumber, at: p, color: color, radius: 0.035)
    case .magnifier:
      guard let (source, bubble) = dragLine, hypot(bubble.x - source.x, bubble.y - source.y) > 0.02 else {
        return nil
      }
      return .magnifier(source: source, at: bubble, radius: 0.12, zoom: magnifierZoom)
    case .sticker:
      guard let r = dragRect, !r.isEmpty, let stickerPath else { return nil }
      return .sticker(path: stickerPath, rect: r)
    }
  }

  func chooseSticker() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.message = "Choose an image to place on the canvas."
    NSApp.activate()
    if panel.runModal() == .OK, let url = panel.url { stickerPath = url.path }
  }

  // MARK: Save

  func save() {
    let recipe = recipe
    let file: DroppedFile
    do { file = try DroppedFile.load(url) } catch {
      saveResult = OperationResult(failures: [
        .init(file: "", message: AppModel.message(for: error, fallback: ""))
      ])
      return
    }
    let others = tool == .crop && applyCropToAll ? batch.compactMap { try? DroppedFile.load($0) } : []
    AppModel.shared.run(
      others.isEmpty ? .edit(recipe) : .batchEdit(recipe), on: [file] + others, origin: .panel)
    // Mirror the shared result into this window once it lands.
    Task {
      while AppModel.shared.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
      saveResult = AppModel.shared.lastResult
    }
  }

  // MARK: Preview

  private func preparePreviewSource() {
    let url = url
    Task.detached(priority: .userInitiated) {
      let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("fdu-preview-\(UUID().uuidString).png")
      do {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
          throw DropError.readFailed(url.lastPathComponent)
        }
        let options: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 1600,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
          throw DropError.readFailed(url.lastPathComponent)
        }
        try ImageOps.write(thumb, as: .png, quality: 1, to: temp)
        await MainActor.run {
          self.previewSource = temp
          self.schedulePreview()
        }
      } catch {
        let message = AppModel.message(for: error, fallback: "This image could not be opened.")
        await MainActor.run { self.loadError = message }
      }
    }
  }

  private func schedulePreview() {
    guard let source = previewSource else { return }
    let recipe = previewRecipe
    renderTask?.cancel()
    renderTask = Task {
      let image = await Task.detached(priority: .userInitiated) {
        try? EditOps.render(source, recipe: recipe)
      }.value
      if !Task.isCancelled, let image { preview = image }
    }
  }

  private func rgba(_ color: Color) -> RGBA {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? .red
    return RGBA(
      red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent),
      alpha: Double(ns.alphaComponent))
  }

  deinit {
    if let previewSource { try? FileManager.default.removeItem(at: previewSource) }
  }
}
