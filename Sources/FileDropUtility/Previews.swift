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

    /// A short test-pattern clip with a tone, made once with the bundled ffmpeg.
    static func sampleVideo() -> URL {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("fdu-sample-clip.mp4")
      if FileManager.default.fileExists(atPath: url.path) { return url }
      guard let ffmpeg = ToolLocator.url(for: .ffmpeg) else { return url }
      let p = Process()
      p.executableURL = ffmpeg
      p.arguments = [
        "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-f", "lavfi", "-i",
        "testsrc2=size=1280x720:rate=30:duration=8", "-f", "lavfi", "-i", "sine=frequency=330:duration=8",
        "-c:v", "h264_videotoolbox", "-b:v", "3000k", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest",
        url.path,
      ]
      try? p.run()
      p.waitUntilExit()
      return url
    }

    /// A video editor with sample edits for the given tool.
    @MainActor
    static func videoEditor(_ tool: VideoTool) -> VideoEditorModel {
      let model = VideoEditorModel(url: sampleVideo(), tool: tool)
      model.trimStart = 1.2
      model.splitPoints = [2.5, 5.5]
      model.removedClips = [1]
      model.frameTimes = [1.5, 4.0]
      model.redactions = [
        TimedRedaction(rect: NormRect(x: 0.55, y: 0.2, width: 0.3, height: 0.25), start: 0, end: 6)
      ]
      model.selectedRedaction = 0
      return model
    }
  }

  extension PreviewData {
    /// An audio editor with a made-up, speech-like waveform and sample edits.
    @MainActor
    static func audioEditor(_ tool: AudioTool) -> AudioEditorModel {
      let count = AudioEditorModel.peakCount
      let peaks: [Float] = (0..<count).map { i in
        let t = Double(i) / Double(count)
        if t < 0.06 || t > 0.93 { return 0.01 }
        let phrase = 0.55 + 0.45 * sin(t * 37)
        let syllable = abs(sin(t * 260)) * 0.7 + 0.3
        return Float(min(max(phrase * syllable * (0.75 + 0.25 * sin(t * 9)), 0.04), 1))
      }
      let model = AudioEditorModel(
        previewURL: URL(fileURLWithPath: "/tmp/Interview.m4a"),
        info: MediaInfo(duration: 42, hasAudio: true, audioChannels: 2, sampleRate: 44100), peaks: peaks,
        tool: tool)
      model.seek(to: 15.5)
      switch tool {
      case .trim:
        model.trimStart = 1.8
        model.trimEnd = 39
        model.trimSilence = true
      case .bleep:
        model.bleeps = [BleepRange(start: 12.2, end: 13.1), BleepRange(start: 27.4, end: 28.6)]
        model.selectedBleep = 1
      case .volume:
        model.normalize = .podcast
      case .channels:
        model.channels = .stereo
        model.balance = -0.3
      }
      return model
    }
  }

  extension PreviewData {
    /// Made-up page thumbnails: a title bar and lines of "text".
    static func samplePages(_ count: Int) -> [NSImage] {
      (0..<count).map { n in
        NSImage(size: NSSize(width: 170, height: 220), flipped: true) { rect in
          NSColor.white.setFill()
          rect.fill()
          NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.55, alpha: 1).setFill()
          NSRect(x: 16, y: 18, width: 90 + CGFloat(n % 3) * 14, height: 12).fill()
          NSColor(white: 0.78, alpha: 1).setFill()
          for line in 0..<12 {
            let width = line % 4 == 3 ? 80 : 138
            NSRect(x: 16, y: 44 + CGFloat(line) * 13, width: CGFloat(width), height: 5).fill()
          }
          return true
        }
      }
    }

    @MainActor
    static func organizer() -> PDFOrganizerModel {
      let model = PDFOrganizerModel(
        previewURL: URL(fileURLWithPath: "/tmp/Proposal.pdf"), thumbnails: samplePages(7))
      model.pages[2] = PDFPageRef(index: 2, rotation: 90)
      model.pages.remove(at: 5)
      model.selection = [2]
      return model
    }

    static func documentFiles(_ names: [String]) -> [DroppedFile] {
      names.map {
        DroppedFile(
          url: URL(fileURLWithPath: "/tmp/\($0)"), kind: FileKind(url: URL(fileURLWithPath: $0)),
          byteSize: 1000)
      }
    }
  }

  /// Each screen, by name, for previews and snapshots.
  @MainActor
  enum Screens {
    static let all: [(name: String, size: CGSize)] = [
      ("Panel-Files", CGSize(width: 424, height: 700)),
      ("Panel-History", CGSize(width: 424, height: 520)),
      ("Panel-Settings", CGSize(width: 424, height: 720)),
      ("Wheel-Convert", CGSize(width: 420, height: 420)),
      ("Wheel-Tools", CGSize(width: 420, height: 420)),
      ("Wheel-Actions", CGSize(width: 420, height: 420)),
      ("Wheel-DropHover", CGSize(width: 420, height: 420)),
      ("Onboarding-Welcome", CGSize(width: 820, height: 520)),
      ("Onboarding-Tools", CGSize(width: 820, height: 520)),
      ("Onboarding-Files", CGSize(width: 820, height: 520)),
      ("Onboarding-Finish", CGSize(width: 820, height: 520)),
      ("Toast", CGSize(width: 460, height: 90)),
      ("MenuBar-Icon", CGSize(width: 460, height: 120)),
      ("Editor", CGSize(width: 900, height: 640)),
      ("Float-Collapsed", CGSize(width: 140, height: 160)),
      ("Float-Expanded", CGSize(width: 280, height: 360)),
      ("Tool-Compress", CGSize(width: 424, height: 330)),
      ("Tool-Metadata", CGSize(width: 464, height: 520)),
      ("Tool-Background", CGSize(width: 404, height: 230)),
      ("Tool-Frame", CGSize(width: 464, height: 560)),
      ("Tool-Collage", CGSize(width: 484, height: 600)),
      ("Tool-QR", CGSize(width: 444, height: 230)),
      ("Tool-Join", CGSize(width: 444, height: 300)),
      ("Tool-Resize", CGSize(width: 424, height: 300)),
      ("Tool-SplitPDF", CGSize(width: 424, height: 300)),
      ("Wheel-VideoTools", CGSize(width: 420, height: 420)),
      ("Wheel-VideoConvert", CGSize(width: 420, height: 420)),
      ("Video-Trim", CGSize(width: 1000, height: 640)),
      ("Video-Split", CGSize(width: 1000, height: 640)),
      ("Video-Redact", CGSize(width: 1000, height: 640)),
      ("Wheel-AudioConvert", CGSize(width: 420, height: 420)),
      ("Wheel-AudioTools", CGSize(width: 420, height: 420)),
      ("Audio-Trim", CGSize(width: 960, height: 440)),
      ("Audio-Bleep", CGSize(width: 960, height: 440)),
      ("Audio-Channels", CGSize(width: 960, height: 440)),
      ("Tool-Visualizer", CGSize(width: 424, height: 340)),
      ("Wheel-DocConvert", CGSize(width: 420, height: 420)),
      ("Wheel-ThemeLight", CGSize(width: 420, height: 420)),
      ("Wheel-ThemeTinted", CGSize(width: 420, height: 420)),
      ("Wheel-PDFConvert", CGSize(width: 420, height: 420)),
      ("Wheel-PDFTools", CGSize(width: 420, height: 420)),
      ("PDF-Organizer", CGSize(width: 900, height: 600)),
    ]

    @ViewBuilder
    static func view(_ name: String, model: AppModel) -> some View {
      switch name {
      case "Panel-Files": PanelView(initialTab: .files).environmentObject(model)
      case "Panel-History": PanelView(initialTab: .history).environmentObject(model)
      case "Panel-Settings": PanelView(initialTab: .settings).environmentObject(model)
      case "Wheel-Convert": wheel(.convert, model)
      case "Wheel-Tools": wheel(.tools, model)
      case "Wheel-Actions": wheel(.actions, model)
      case "Wheel-DropHover": dropHover(model)
      case "MenuBar-Icon":
        // Idle, just started, a third done and nearly done, enlarged so the ring is visible.
        HStack(spacing: 28) {
          ForEach([nil, 0, 0.35, 0.8] as [Double?], id: \.self) { progress in
            Image(nsImage: MenuBarIcon.image(progress: progress))
              .resizable()
              .frame(width: 54, height: 54)
          }
        }
        .padding(20)
        .glassPanel()
      case "Onboarding-Welcome": OnboardingView(onFinish: {}, startPage: .welcome).environmentObject(model)
      case "Onboarding-Tools": OnboardingView(onFinish: {}, startPage: .tools).environmentObject(model)
      case "Onboarding-Files": OnboardingView(onFinish: {}, startPage: .fileTypes).environmentObject(model)
      case "Onboarding-Finish": OnboardingView(onFinish: {}, startPage: .finish).environmentObject(model)
      case "Editor": EditorView(model: editorModel()).environmentObject(model)
      case "Float-Collapsed": floatPreview(expanded: false)
      case "Float-Expanded": floatPreview(expanded: true)
      case "Tool-Compress": CompressView(urls: [PreviewData.sampleImage()])
      case "Tool-Resize": ResizeView(urls: [PreviewData.sampleImage()])
      case "Tool-SplitPDF": SplitPDFView(urls: [URL(fileURLWithPath: "/tmp/Deck.pdf")])
      case "Tool-Metadata": MetadataView(urls: [PreviewData.sampleImage()])
      case "Tool-Background": BackgroundView(urls: [PreviewData.sampleImage()])
      case "Tool-Frame": FrameView(urls: [PreviewData.sampleImage()])
      case "Tool-Collage":
        CollageView(urls: [PreviewData.sampleImage(), PreviewData.sampleImage(), PreviewData.sampleImage()])
      case "Tool-Join":
        JoinView(urls: [
          PreviewData.sampleVideo(), URL(fileURLWithPath: "/tmp/Intro.mov"),
          URL(fileURLWithPath: "/tmp/Outro.mp4"),
        ])
      case "Wheel-VideoTools":
        RadialWheel(
          kind: .tools, items: WheelKind.tools.videoItems(count: 1), centerText: "8.0 s", mode: .click
        ) { _, _ in }
        .padding(DesignTokens.Spacing.inset)
      case "Wheel-VideoConvert":
        RadialWheel(
          kind: .convert, items: WheelKind.convert.videoItems(count: 1), centerText: "3.1 MB", mode: .click
        ) { _, _ in }
        .padding(DesignTokens.Spacing.inset)
      case "Video-Trim": VideoEditorView(model: PreviewData.videoEditor(.trim)).environmentObject(model)
      case "Video-Split": VideoEditorView(model: PreviewData.videoEditor(.split)).environmentObject(model)
      case "Video-Redact": VideoEditorView(model: PreviewData.videoEditor(.redact)).environmentObject(model)
      case "Wheel-AudioConvert":
        RadialWheel(
          kind: .convert, items: WheelKind.convert.audioItems(count: 1), centerText: "4.2 MB", mode: .click
        ) { _, _ in }
        .padding(DesignTokens.Spacing.inset)
      case "Wheel-AudioTools":
        RadialWheel(
          kind: .tools, items: WheelKind.tools.audioItems(count: 1), centerText: "0:42", mode: .click
        ) { _, _ in }
        .padding(DesignTokens.Spacing.inset)
      case "Audio-Trim": AudioEditorView(model: PreviewData.audioEditor(.trim)).environmentObject(model)
      case "Audio-Bleep": AudioEditorView(model: PreviewData.audioEditor(.bleep)).environmentObject(model)
      case "Audio-Channels":
        AudioEditorView(model: PreviewData.audioEditor(.channels)).environmentObject(model)
      case "Wheel-ThemeLight":
        RadialWheel(
          kind: .tools, items: WheelKind.tools.items(for: []), centerText: "2.4 MB", mode: .drop,
          hotID: "crop"
        ) { _, _ in }
        .environment(\.wheelTheme, .light)
        .padding(DesignTokens.Spacing.inset)
      case "Wheel-ThemeTinted":
        RadialWheel(
          kind: .tools, items: WheelKind.tools.items(for: []), centerText: "2.4 MB", mode: .drop,
          hotID: "crop"
        ) { _, _ in }
        .environment(\.wheelTheme, .tinted)
        .padding(DesignTokens.Spacing.inset)
      case "Wheel-DocConvert":
        RadialWheel(
          kind: .convert, items: WheelKind.convert.items(for: PreviewData.documentFiles(["Notes.docx"])),
          centerText: "48 KB", mode: .click
        ) { _, _ in }
        .padding(DesignTokens.Spacing.inset)
      case "Wheel-PDFConvert":
        RadialWheel(
          kind: .convert, items: WheelKind.convert.items(for: PreviewData.documentFiles(["Deck.pdf"])),
          centerText: "2.4 MB", mode: .click
        ) { _, _ in }
        .padding(DesignTokens.Spacing.inset)
      case "Wheel-PDFTools":
        RadialWheel(
          kind: .tools, items: WheelKind.tools.items(for: PreviewData.documentFiles(["Deck.pdf"])),
          centerText: "2.4 MB", mode: .click
        ) { _, _ in }
        .padding(DesignTokens.Spacing.inset)
      case "PDF-Organizer": PDFOrganizerView(model: PreviewData.organizer()).environmentObject(model)
      case "Tool-Visualizer": VisualizerView(urls: [URL(fileURLWithPath: "/tmp/Episode 12.mp3")])
      case "Tool-QR": QRResultsView(codes: ["https://example.com/menu", "WIFI:S:Studio;T:WPA;P:example;;"])
      default:
        ToastPreview()
      }
    }

    private static func floatPreview(expanded: Bool) -> some View {
      let names = ["Hero shot.png", "Brief.pdf", "Interview.m4a", "Notes.md"]
      let urls = names.map { URL(fileURLWithPath: "/Users/me/Desktop/\($0)") }
      let pages = PreviewData.samplePages(urls.count)
      var thumbs = Dictionary(uniqueKeysWithValues: zip(urls, pages))
      if let image = NSImage(contentsOf: PreviewData.sampleImage()) { thumbs[urls[0]] = image }
      let manager = FloatManager(folder: FileManager.default.temporaryDirectory)
      let stack = FloatStack(urls: urls.reversed(), edge: .right)
      manager.preview(stack, expanded: expanded, thumbnails: thumbs)
      let size = manager.size(for: stack, expanded: expanded)
      return FloatTabView(id: stack.id).environmentObject(manager)
        .frame(width: size.width, height: size.height)
        .padding(DesignTokens.Spacing.inset)
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

    /// A file being dragged over the Actions wheel, with Terminal lit as in a live drag.
    private static func dropHover(_ model: AppModel) -> some View {
      let items = WheelKind.actions.items(for: [])
      return RadialWheel(
        kind: .actions, items: items, centerText: "5 KB", mode: .drop, hotID: items.last?.id,
        pointer: CGPoint(x: -150, y: -30)
      ) { _, _ in }
      .padding(DesignTokens.Spacing.inset)
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

  struct ToastPreview: View {
    var body: some View {
      HStack(spacing: 10) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
        Text("Convert to JPEG: saved 2 files").font(.callout)
        Button("Show") {}.buttonStyle(.borderless).fontWeight(.semibold)
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
