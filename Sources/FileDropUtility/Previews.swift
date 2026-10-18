import SwiftUI

#if DEBUG
  import AppKit
  import DropCore
  import SwiftUI

  // Uses `PreviewProvider` rather than `#Preview`: the macro's plugin ships only with Xcode,
  // and this project also builds with the Command Line Tools. Xcode shows both kinds.

  /// Sample state shared by previews and the snapshot harness.
  @MainActor
  enum PreviewData {
    static func model() -> AppModel {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fdu-preview-state")
      let model = AppModel(folder: folder)
      model.files = [
        DroppedFile(
          url: URL(fileURLWithPath: "/Users/me/Desktop/beach.png"), kind: .image(.png), byteSize: 2_100_000),
        DroppedFile(
          url: URL(fileURLWithPath: "/Users/me/Desktop/receipt.heic"), kind: .image(.heic), byteSize: 340_000),
      ]
      model.lastOperation = "Convert to JPEG"
      model.lastResult = OperationResult(outputs: [URL(fileURLWithPath: "/Users/me/Desktop/beach.jpg")])
      model.history = [
        HistoryEntry(operation: "Convert to JPEG", inputCount: 1, outputs: ["beach.jpg"], errors: []),
        HistoryEntry(
          operation: "Compress", inputCount: 1, outputs: [],
          errors: ["tiny.jpg is already as small as it gets."]),
      ]
      return model
    }

    /// A colourful sample photo-like image, written once to the temp folder.
    static func sampleImage() -> URL {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("fdu-sample-photo.png")
      if FileManager.default.fileExists(atPath: url.path) { return url }
      let size = CGSize(width: 1200, height: 800)
      let image = NSImage(size: size, flipped: false) { rect in
        NSGradient(colors: [.systemTeal, .systemIndigo, .systemPink])?.draw(in: rect, angle: 35)
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: 420, y: 220, width: 360, height: 360)).fill()
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: NSRect(x: 900, y: 560, width: 160, height: 160)).fill()
        return true
      }
      if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
      {
        try? png.write(to: url)
      }
      return url
    }
  }

  /// Each screen, by name, for previews and snapshots.
  @MainActor
  enum Screens {
    static let all: [(name: String, size: CGSize)] = [
      ("Panel-Files", CGSize(width: 424, height: 700)),
      ("Panel-History", CGSize(width: 424, height: 520)),
      ("Panel-Settings", CGSize(width: 424, height: 600)),
      ("Wheel-Convert", CGSize(width: 420, height: 420)),
      ("Wheel-Tools", CGSize(width: 420, height: 420)),
      ("Wheel-Actions", CGSize(width: 420, height: 420)),
      ("Onboarding-Welcome", CGSize(width: 820, height: 520)),
      ("Onboarding-Tools", CGSize(width: 820, height: 520)),
      ("Onboarding-Finish", CGSize(width: 820, height: 520)),
      ("Toast", CGSize(width: 460, height: 90)),
      ("Editor", CGSize(width: 900, height: 640)),
      ("Float", CGSize(width: 284, height: 284)),
    ]

    @ViewBuilder
    static func view(_ name: String, model: AppModel) -> some View {
      switch name {
      case "Panel-Files": PanelPreview(tab: .files).environmentObject(model)
      case "Panel-History": PanelPreview(tab: .history).environmentObject(model)
      case "Panel-Settings": PanelPreview(tab: .settings).environmentObject(model)
      case "Wheel-Convert": wheel(.convert, model)
      case "Wheel-Tools": wheel(.tools, model)
      case "Wheel-Actions": wheel(.actions, model)
      case "Onboarding-Welcome": OnboardingView(onFinish: {}, startPage: .welcome).environmentObject(model)
      case "Onboarding-Tools": OnboardingView(onFinish: {}, startPage: .tools).environmentObject(model)
      case "Onboarding-Finish": OnboardingView(onFinish: {}, startPage: .finish).environmentObject(model)
      case "Editor": EditorView(model: editorModel()).environmentObject(model)
      case "Float": FloatView(url: PreviewData.sampleImage())
      default:
        ToastPreview()
      }
    }

    private static func editorModel() -> EditorModel {
      let editor = EditorModel(url: PreviewData.sampleImage(), tool: .annotate)
      editor.recipe = EditRecipe(
        brightness: 0.05,
        redactions: [NormRect(x: 0.62, y: 0.12, width: 0.28, height: 0.12)],
        strokes: [
          Stroke(
            points: (0...20).map {
              NormPoint(x: 0.12 + Double($0) * 0.02, y: 0.7 - sin(Double($0) / 3) * 0.08)
            },
            color: RGBA(red: 0.9, green: 0.1, blue: 0.1), width: 0.012)
        ])
      return editor
    }

    private static func wheel(_ kind: WheelKind, _ model: AppModel) -> some View {
      RadialWheel(
        kind: kind, items: kind.items(for: model.files), centerText: model.totalSizeText, mode: .click
      ) {
        _, _ in
      }
      .padding(DesignTokens.Spacing.inset)
    }
  }

  /// The panel with a chosen tab, since the real panel keeps its tab in private state.
  struct PanelPreview: View {
    let tab: PanelTab
    @EnvironmentObject private var model: AppModel

    var body: some View {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.stack) {
        StatusHeader()
        FloatingTabBar(
          tabs: PanelTab.allCases, selection: .constant(tab), title: \.rawValue, systemImage: \.systemImage)
        switch tab {
        case .files: FilesTab()
        case .history: HistoryTab()
        case .settings: SettingsTab()
        }
      }
      .padding(DesignTokens.Spacing.inset)
      .frame(width: 400)
    }
  }

  struct ToastPreview: View {
    var body: some View {
      HStack(spacing: 10) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(DesignTokens.Palette.accentText)
        Text("Convert to JPEG: saved 2 files").font(.callout)
        Button("Show") {}.buttonStyle(.subtleGlass)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .glassPanel(cornerRadius: 999)
      .padding(DesignTokens.Spacing.inset)
    }
  }

  /// Every screen in light, dark, and the largest Dynamic Type size.
  struct AllScreens_Previews: PreviewProvider {
    static var previews: some View {
      ForEach(Screens.all, id: \.name) { screen in
        Group {
          Screens.view(screen.name, model: PreviewData.model())
            .preferredColorScheme(.light)
            .previewDisplayName("\(screen.name) · Light")
          Screens.view(screen.name, model: PreviewData.model())
            .preferredColorScheme(.dark)
            .previewDisplayName("\(screen.name) · Dark")
          Screens.view(screen.name, model: PreviewData.model())
            .dynamicTypeSize(.accessibility5)
            .previewDisplayName("\(screen.name) · Largest Text")
        }
        .frame(width: screen.size.width)
        .background(SnapshotBackdrop())
      }
    }
  }
#endif

/// A deliberately busy, bright backdrop for checking glass legibility.
struct SnapshotBackdrop: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [.yellow, .orange, .pink, .cyan, .white], startPoint: .topLeading, endPoint: .bottomTrailing)
      Canvas { ctx, size in
        var seed: UInt64 = 7
        func next() -> CGFloat {
          seed = seed &* 6_364_136_223_846_793_005 &+ 1
          return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
        }
        for _ in 0..<140 {
          let r = 8 + next() * 60
          let rect = CGRect(
            x: next() * size.width - r, y: next() * size.height - r, width: r * 2, height: r * 2)
          let colors: [Color] = [.white, .black, .blue, .red, .green, .purple, .yellow]
          ctx.fill(Path(ellipseIn: rect), with: .color(colors[Int(next() * 7) % 7].opacity(0.8)))
        }
        for i in 0..<30 {
          var text = ctx.resolve(Text("Busy text \(i)").font(.title.bold()))
          text.shading = .color(i % 2 == 0 ? .black : .white)
          ctx.draw(text, at: CGPoint(x: next() * size.width, y: next() * size.height))
        }
      }
    }
  }
}
