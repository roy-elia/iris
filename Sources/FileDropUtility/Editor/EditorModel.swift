import AppKit
import DropCore
import ImageIO
import SwiftUI

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
  @Published var saveResult: OperationResult?
  @Published var loadError: String?

  private var history: [EditRecipe] = []
  private var previewSource: URL?
  private var renderTask: Task<Void, Never>?

  init(url: URL, tool: EditorTool) {
    self.url = url
    self.tool = tool
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

  func dragChanged(from start: NormPoint, to current: NormPoint) {
    switch tool {
    case .crop, .redact:
      dragRect = NormRect(from: start, to: current)
    case .annotate:
      if inProgressStroke == nil {
        inProgressStroke = Stroke(points: [start], color: rgba(strokeColor), width: strokeWidth)
      }
      inProgressStroke?.points.append(current)
    case .adjust:
      break
    }
  }

  func dragEnded() {
    switch tool {
    case .crop:
      if let rect = dragRect, !rect.isEmpty { commit { $0.crop = rect } }
    case .redact:
      if let rect = dragRect, !rect.isEmpty { commit { $0.redactions.append(rect) } }
    case .annotate:
      if let stroke = inProgressStroke { commit { $0.strokes.append(stroke) } }
    case .adjust:
      break
    }
    dragRect = nil
    inProgressStroke = nil
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
    AppModel.shared.run(.edit(recipe), on: [file], origin: .panel)
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
