import CoreGraphics
import Foundation
import Testing

@testable import DropCore

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

@Suite struct FormatSupportTests {
  @Test func webpIsWritableOnlyWithTheBundledEncoder() async {
    #expect(ImageFormat.webp.isWritable == ToolLocator.isAvailable(.cwebp))
    #expect(!ImageFormat.svg.isWritable)
    #expect(!ImageFormat.webp.isImageIOWritable)
    #expect(FileKind(url: URL(fileURLWithPath: "/a.webp")) == .image(.webp))
  }

  @Test func convertToSVGIsRefused() async throws {
    let dir = try TempDir()
    let files = try load(Fixtures.writeImage(to: dir.file("a.png"), type: "public.png"))
    #expect(
      Processor.validate(.convert(.svg, quality: 1), files: files) == "SVG can't be written on this Mac.")
    let webp = Processor.validate(.convert(.webp, quality: 1), files: files)
    #expect((webp == nil) == ToolLocator.isAvailable(.cwebp))
  }

  @Test func alphaSupport() async {
    #expect(!ImageFormat.jpeg.supportsAlpha)
    #expect(!ImageFormat.bmp.supportsAlpha)
    #expect(ImageFormat.png.supportsAlpha && ImageFormat.heic.supportsAlpha)
  }

  @Test func settingsCoerceUnwritableDefaultAndRoundTripNewFields() async throws {
    #expect(AppSettings(defaultFormat: .svg).defaultFormat == .png)
    let s = AppSettings(wheelTriggerEnabled: false, hasCompletedOnboarding: true)
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    #expect(back == s)
    let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"quality":0.5}"#.utf8))
    #expect(old.wheelTriggerEnabled && !old.hasCompletedOnboarding)
    // Settings saved while the app had its own Appearance option still load; the key is ignored.
    let withAppearance = try JSONDecoder().decode(
      AppSettings.self, from: Data(#"{"quality":0.5,"appearance":"dark","launchAtLogin":true}"#.utf8))
    #expect(withAppearance.launchAtLogin)
  }
}

@Suite struct EditOpsTests {
  private func source(_ dir: TempDir, width: Int = 80, height: Int = 40) throws -> URL {
    try Fixtures.writeImage(to: dir.file("src.png"), type: "public.png", width: width, height: height)
  }

  @Test func normRectClampsAndOrders() async {
    let r = NormRect(from: NormPoint(x: 1.2, y: 0.8), to: NormPoint(x: 0.2, y: -0.1))
    #expect(r == NormRect(x: 0.2, y: 0, width: 0.8, height: 0.8))
    #expect(NormRect(x: 0, y: 0, width: 0.001, height: 1).isEmpty)
  }

  @Test func identityAndTurns() async {
    #expect(EditRecipe().isIdentity)
    #expect(EditRecipe(quarterTurns: 4).isIdentity)
    #expect(EditRecipe(quarterTurns: -1).normalizedTurns == 3)
    #expect(!EditRecipe(brightness: 0.1).isIdentity)
  }

  @Test func rotateSwapsDimensions() async throws {
    let dir = try TempDir()
    let image = try EditOps.render(source(dir), recipe: EditRecipe(quarterTurns: 1))
    #expect(image.width == 40 && image.height == 80)
  }

  @Test func rotateMovesTopLeftToTopRight() async throws {
    let dir = try TempDir()
    // Mark the top-left corner black.
    let base = Fixtures.image(width: 40, height: 20)
    let marked = try EditOps.draw(
      on: base, recipe: EditRecipe(redactions: [NormRect(x: 0, y: 0, width: 0.25, height: 0.5)]))
    let url = try Fixtures.writeCGImage(marked, to: dir.file("m.png"))
    let turned = try EditOps.render(url, recipe: EditRecipe(quarterTurns: 1))
    // Clockwise: the old top-left ends up top-right.
    #expect(Fixtures.pixel(turned, x: turned.width - 2, y: 1)[0] < 20)
    #expect(Fixtures.pixel(turned, x: 1, y: 1)[0] > 200)
  }

  @Test func cropUsesNormalisedTopLeftRect() async throws {
    let dir = try TempDir()
    let image = try EditOps.render(
      source(dir), recipe: EditRecipe(crop: NormRect(x: 0.5, y: 0, width: 0.5, height: 0.5)))
    #expect(image.width == 40 && image.height == 20)
  }

  @Test func blackoutRedactionIsBlack() async throws {
    let dir = try TempDir()
    let image = try EditOps.render(
      source(dir), recipe: EditRecipe(redactions: [NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)]))
    #expect(Array(Fixtures.pixel(image, x: 40, y: 20).prefix(3)) == [0, 0, 0])
    #expect(Fixtures.pixel(image, x: 2, y: 2)[0] > 200)  // Outside stays orange.
  }

  @Test func pixelateRedactionHidesDetail() async throws {
    let dir = try TempDir()
    let noisy = try Fixtures.writeCGImage(Fixtures.noisyImage(width: 200, height: 200), to: dir.file("n.png"))
    let image = try EditOps.render(
      noisy,
      recipe: EditRecipe(redactions: [NormRect(x: 0, y: 0, width: 1, height: 1)], redactStyle: .pixelate))
    // Neighbouring pixels inside one block match after pixelation.
    #expect(Fixtures.pixel(image, x: 1, y: 1) == Fixtures.pixel(image, x: 2, y: 1))
  }

  @Test func strokeDrawsInItsColour() async throws {
    let dir = try TempDir()
    let stroke = Stroke(
      points: [NormPoint(x: 0, y: 0.5), NormPoint(x: 1, y: 0.5)], color: RGBA(red: 0, green: 0, blue: 1),
      width: 0.2)
    let image = try EditOps.render(source(dir), recipe: EditRecipe(strokes: [stroke]))
    let p = Fixtures.pixel(image, x: 40, y: 20)
    #expect(p[2] > 240 && p[0] < 20)
  }

  @Test func brightnessRaisesValues() async throws {
    let dir = try TempDir()
    let url = try source(dir)
    let before = Fixtures.pixel(try ImageOps.loadOriented(url), x: 10, y: 10)
    let after = Fixtures.pixel(try EditOps.render(url, recipe: EditRecipe(brightness: 0.3)), x: 10, y: 10)
    #expect(after[2] > before[2])
  }

  @Test func processorEditNamesOutputAndValidates() async throws {
    let dir = try TempDir()
    let a = try source(dir)
    let b = try Fixtures.writeImage(to: dir.file("b.jpg"))
    #expect(
      Processor.validate(.edit(EditRecipe()), files: try load(a, b)) == "Edit works on one image at a time.")
    let result = await Processor(settings: AppSettings()).run(
      .edit(EditRecipe(quarterTurns: 1)), on: try load(a))
    #expect(result.outputs.map(\.lastPathComponent) == ["src edited.png"])
  }
}

@Suite struct CompressOpsTests {
  @Test func targetFormats() async {
    #expect(CompressOps.targetFormat(for: .jpeg, hasAlpha: false) == .jpeg)
    #expect(CompressOps.targetFormat(for: .avif, hasAlpha: true) == .avif)
    #expect(CompressOps.targetFormat(for: .png, hasAlpha: false) == .jpeg)
    #expect(CompressOps.targetFormat(for: .png, hasAlpha: true) == .heic)
    #expect(CompressOps.targetFormat(for: .bmp, hasAlpha: false) == .jpeg)
  }

  @Test func noisyPNGBecomesSmallerJPEG() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeCGImage(Fixtures.noisyImage(width: 300, height: 300), to: dir.file("n.png"))
    let result = await Processor(settings: AppSettings()).run(.compress(quality: 0.5), on: try load(src))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "n compressed.jpg")
    #expect(CompressOps.fileSize(out) < CompressOps.fileSize(src))
  }

  @Test func alreadySmallFileIsReportedAndNothingLeftBehind() async throws {
    let dir = try TempDir()
    let src = dir.file("tiny.jpg")
    try ImageOps.convert(
      try Fixtures.writeImage(to: dir.file("t.png"), type: "public.png"), to: .jpeg, quality: 0.1,
      destination: src)
    let result = await Processor(settings: AppSettings()).run(.compress(quality: 1.0), on: try load(src))
    #expect(result.outputs.isEmpty)
    #expect(result.failures.first?.message == "tiny.jpg is already as small as it gets.")
    #expect(!FileManager.default.fileExists(atPath: dir.file("tiny compressed.jpg").path))
  }

  @Test func imageHeavyPDFGetsSmaller() async throws {
    let dir = try TempDir()
    let img = try Fixtures.writeCGImage(Fixtures.noisyImage(width: 800, height: 800), to: dir.file("big.png"))
    let pdf = dir.file("doc.pdf")
    try PDFOps.imagesToPDF([img], destination: pdf)
    let result = await Processor(settings: AppSettings()).run(.compress(quality: 0.6), on: try load(pdf))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "doc compressed.pdf")
    #expect(PDFOps.pageCount(of: out) == 1)
  }
}

@Suite struct BackgroundOpsTests {
  @Test func compositeFillsTransparentAreas() async throws {
    // Transparent canvas with an opaque square in the middle.
    let ctx = try EditOps.context(width: 20, height: 20, like: Fixtures.image())
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 5, y: 5, width: 10, height: 10))
    let subject = try EditOps.make(ctx)

    let onBlue = try BackgroundOps.composite(subject: subject, over: .color(RGBA(red: 0, green: 0, blue: 1)))
    #expect(Array(Fixtures.pixel(onBlue, x: 1, y: 1).prefix(3)) == [0, 0, 255])
    #expect(Array(Fixtures.pixel(onBlue, x: 10, y: 10).prefix(3)) == [255, 0, 0])

    let clear = try BackgroundOps.composite(subject: subject, over: .transparent)
    #expect(Fixtures.pixel(clear, x: 1, y: 1)[3] == 0)
  }

  @Test func outputFormats() async {
    #expect(BackgroundOps.outputFormat(for: URL(fileURLWithPath: "/a.jpg"), fill: .transparent) == .png)
    #expect(BackgroundOps.outputFormat(for: URL(fileURLWithPath: "/a.jpg"), fill: .color(.white)) == .jpeg)
    #expect(BackgroundOps.outputFormat(for: URL(fileURLWithPath: "/a.webp"), fill: .color(.white)) == .png)
  }

  @Test func runsOnARealImageOrReportsNoSubject() async throws {
    let dir = try TempDir()
    // A dark disc on a plain light background.
    let ctx = try EditOps.context(width: 256, height: 256, like: Fixtures.image())
    ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
    ctx.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 64, y: 64, width: 128, height: 128))
    let src = try Fixtures.writeCGImage(try EditOps.make(ctx), to: dir.file("disc.png"))

    let result = await Processor(settings: AppSettings()).run(
      .replaceBackground(.transparent), on: try load(src))
    if let out = result.outputs.first {
      #expect(out.lastPathComponent == "disc no-bg.png")
      #expect(Fixtures.pixel(try ImageOps.loadOriented(out), x: 2, y: 2)[3] == 0)
    } else {
      #expect(result.failures.first?.message == "No clear subject was found in disc.png.")
      #expect(!FileManager.default.fileExists(atPath: dir.file("disc no-bg.png").path))
    }
  }
}

@Suite struct FileActionsTests {
  @Test func moveRenamesOnCollisionAndSkipsSameFolder() async throws {
    let dir = try TempDir()
    let a = try dir.touch("a.txt", contents: "A")
    let dest = dir.file("dest")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: dest.appendingPathComponent("a.txt"))
    let already = dest.appendingPathComponent("b.txt")
    try Data("B".utf8).write(to: already)

    let (moved, failures) = FileActions.move([a, already], to: dest)
    #expect(failures.isEmpty)
    #expect(moved.map(\.lastPathComponent) == ["a (1).txt", "b.txt"])
    #expect(!FileManager.default.fileExists(atPath: a.path))
    #expect(try String(contentsOf: dest.appendingPathComponent("a.txt"), encoding: .utf8) == "old")
  }

  @Test func moveReportsMissingFile() async throws {
    let dir = try TempDir()
    let (moved, failures) = FileActions.move([dir.file("ghost.txt")], to: dir.file("d"))
    #expect(moved.isEmpty)
    #expect(failures == [.init(file: "ghost.txt", message: "could not be moved.")])
  }

  @Test func pathTextAndCommonFolder() async {
    let files = [URL(fileURLWithPath: "/u/a/x/1.png"), URL(fileURLWithPath: "/u/a/y/2.png")]
    #expect(FileActions.pathText(for: files) == "/u/a/x/1.png\n/u/a/y/2.png")
    #expect(FileActions.commonFolder(of: files)?.path == "/u/a")
    #expect(FileActions.commonFolder(of: [URL(fileURLWithPath: "/u/a/1.png")])?.path == "/u/a")
    #expect(FileActions.commonFolder(of: []) == nil)
  }
}

@Suite struct WheelHitTestTests {
  // Six segments, outer radius 170, as in the drag overlay.
  private func hit(_ dx: Double, _ dy: Double) -> Int? {
    WheelHitTest.segment(dx: dx, dy: dy, outerRadius: 170, count: 6)
  }

  @Test func topIsFirstSegmentAndOrderIsClockwise() async {
    #expect(hit(0, -120) == 0)  // top
    #expect(hit(104, -60) == 1)  // upper right
    #expect(hit(104, 60) == 2)  // lower right
    #expect(hit(0, 120) == 3)  // bottom
    #expect(hit(-104, 60) == 4)  // lower left
    #expect(hit(-104, -60) == 5)  // upper left
  }

  @Test func centreHoleAndOutsideMissEverySegment() async {
    #expect(hit(0, 0) == nil)
    #expect(hit(30, -40) == nil)  // inside the centre pill
    #expect(hit(0, -200) == nil)  // past the rim
    #expect(hit(0, -185) == 0)  // just past the rim still counts
  }

  @Test func boundariesFallOnOneSide() async {
    // The edge between segments 0 and 1 is at -60°; just either side of it.
    let r = 120.0
    let a0 = (-60.5) * .pi / 180
    let a1 = (-59.5) * .pi / 180
    #expect(hit(r * cos(a0), r * sin(a0)) == 0)
    #expect(hit(r * cos(a1), r * sin(a1)) == 1)
    #expect(WheelHitTest.segment(dx: 0, dy: -100, outerRadius: 170, count: 0) == nil)
  }
}

@Suite struct DragTriggerTests {
  enum K: Equatable, Sendable { case convert, tools }
  typealias T = DragTrigger<K>

  /// Presses, then starts a drag (pasteboard bump), with no modifier yet.
  private func dragging() -> (T, TimeInterval) {
    var t = T(graceInterval: 0.2)
    _ = t.update(.init(time: 0, buttonDown: false, pasteboardChangeCount: 10, kind: nil))
    _ = t.update(.init(time: 0.1, buttonDown: true, pasteboardChangeCount: 10, kind: nil))
    _ = t.update(.init(time: 0.2, buttonDown: true, pasteboardChangeCount: 11, kind: nil))
    return (t, 0.2)
  }

  @Test func modifierDuringDragOpensWheelWithoutMouseMovement() async {
    var (t, now) = dragging()
    #expect(t.isDragging)
    #expect(
      t.update(.init(time: now + 0.02, buttonDown: true, pasteboardChangeCount: 11, kind: .convert))
        == .show(.convert))
    now += 0.02
    #expect(
      t.update(.init(time: now + 0.02, buttonDown: true, pasteboardChangeCount: 11, kind: .convert)) == .none)
  }

  @Test func modifierWithoutDragDoesNothing() async {
    var t = T()
    _ = t.update(.init(time: 0, buttonDown: false, pasteboardChangeCount: 5, kind: nil))
    #expect(t.update(.init(time: 0.1, buttonDown: true, pasteboardChangeCount: 5, kind: .convert)) == .none)
    #expect(t.update(.init(time: 0.2, buttonDown: false, pasteboardChangeCount: 5, kind: .convert)) == .none)
  }

  @Test func switchingModifierSwitchesWheel() async {
    var (t, now) = dragging()
    _ = t.update(.init(time: now, buttonDown: true, pasteboardChangeCount: 11, kind: .convert))
    #expect(
      t.update(.init(time: now + 0.05, buttonDown: true, pasteboardChangeCount: 11, kind: .tools))
        == .show(.tools))
  }

  @Test func releasingModifierClosesAfterGraceUnlessInside() async {
    var (t, now) = dragging()
    _ = t.update(.init(time: now, buttonDown: true, pasteboardChangeCount: 11, kind: .convert))
    #expect(t.update(.init(time: now + 0.1, buttonDown: true, pasteboardChangeCount: 11, kind: nil)) == .none)
    #expect(t.update(.init(time: now + 0.3, buttonDown: true, pasteboardChangeCount: 11, kind: nil)) == .hide)

    var (u, later) = dragging()
    _ = u.update(.init(time: later, buttonDown: true, pasteboardChangeCount: 11, kind: .convert))
    later += 1
    #expect(
      u.update(
        .init(time: later, buttonDown: true, pasteboardChangeCount: 11, kind: nil, dragInsideWheel: true))
        == .none)
    #expect(u.shownKind == .convert)
  }

  @Test func escapeClosesForTheRestOfTheDrag() async {
    var (t, now) = dragging()
    _ = t.update(.init(time: now, buttonDown: true, pasteboardChangeCount: 11, kind: .convert))
    #expect(
      t.update(
        .init(time: now + 0.05, buttonDown: true, pasteboardChangeCount: 11, kind: .convert, escapeDown: true)
      )
        == .hide)
    #expect(
      t.update(.init(time: now + 0.1, buttonDown: true, pasteboardChangeCount: 11, kind: .convert)) == .none)
  }

  @Test func releaseHidesAfterDropAndResets() async {
    var (t, now) = dragging()
    _ = t.update(.init(time: now, buttonDown: true, pasteboardChangeCount: 11, kind: .convert))
    #expect(
      t.update(.init(time: now + 0.05, buttonDown: false, pasteboardChangeCount: 11, kind: .convert))
        == .hideAfterDrop)
    #expect(!t.isDragging)
    // A plain click with the modifier afterwards doesn't reopen it.
    #expect(
      t.update(.init(time: now + 0.2, buttonDown: true, pasteboardChangeCount: 11, kind: .convert)) == .none)
  }

  @Test func readableNonFileDragIsIgnored() async {
    var t = T()
    _ = t.update(.init(time: 0, buttonDown: false, pasteboardChangeCount: 1, kind: nil))
    _ = t.update(.init(time: 0.1, buttonDown: true, pasteboardChangeCount: 1, kind: .convert))
    #expect(
      t.update(
        .init(time: 0.2, buttonDown: true, pasteboardChangeCount: 2, mayHoldFiles: false, kind: .convert))
        == .none)
    #expect(!t.isDragging)
  }

  @Test func mouseDownMonitorCountWinsOverLateSample() async {
    var t = T()
    t.mouseDown(pasteboardChangeCount: 7)
    // The first timer sample arrives after the drag already bumped the count.
    #expect(
      t.update(.init(time: 0.1, buttonDown: true, pasteboardChangeCount: 8, kind: .tools)) == .show(.tools))
  }
}
