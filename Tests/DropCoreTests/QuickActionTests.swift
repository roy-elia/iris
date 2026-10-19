import Foundation
import ImageIO
import Testing

@testable import DropCore

@Suite struct QuickActionTests {
  @Test func specsRoundTrip() {
    let actions: [QuickAction] = [
      .convertImage(.png), .convertImage(.jpeg), .convertAudio(.mp3), .convertVideo(.mp4720),
      .convertDocument(.pdf), .compress, .resize(.percent(50)), .resize(.percent(12.5)),
      .resize(.maxEdge(1920)), .makePDF,
    ]
    for action in actions {
      #expect(QuickAction(spec: action.spec) == action, "\(action.spec)")
    }
  }

  @Test func parsesSpecVariants() {
    #expect(QuickAction(spec: "Convert-Image:HEIC") == .convertImage(.heic))
    #expect(QuickAction(spec: "resize:800px") == .resize(.maxEdge(800)))
    #expect(QuickAction(spec: "convert-video:mp4-720") == .convertVideo(.mp4720))
  }

  @Test func rejectsBadSpecs() {
    for spec in [
      "", "compress:9", "make-pdf:x", "convert-image", "convert-image:svg", "convert-image:nope",
      "convert-audio:png", "resize", "resize:0", "resize:999%", "resize:abc", "zip",
    ] {
      #expect(QuickAction(spec: spec) == nil, "\(spec)")
    }
  }

  @Test func planUsesSettingsQualityAndPicksPDFOperation() throws {
    let dir = try TempDir()
    let img = try DroppedFile.load(Fixtures.writeImage(to: dir.file("a.jpg")))
    let pdf = try DroppedFile.load(Fixtures.writePDF(to: dir.file("a.pdf"), pages: 1))
    let settings = AppSettings(quality: 0.5, formatSettings: ["jpeg": FormatSettings(quality: 0.3)])

    #expect(
      QuickAction.convertImage(.jpeg).plan(for: [img], settings: settings).steps
        == [.init(operation: .convert(.jpeg, quality: 0.3), files: [img])])
    #expect(QuickAction.makePDF.plan(for: [img], settings: settings).steps.map(\.operation) == [.imagesToPDF])
    #expect(
      QuickAction.makePDF.plan(for: [pdf, pdf], settings: settings).steps.map(\.operation) == [.mergePDFs])
    #expect(QuickAction.resize(.percent(50)).plan(for: [], settings: settings).steps.isEmpty)
  }

  @Test func compressSplitsByKind() throws {
    let dir = try TempDir()
    let img = try DroppedFile.load(Fixtures.writeImage(to: dir.file("a.jpg")))
    let pdf = try DroppedFile.load(Fixtures.writePDF(to: dir.file("b.pdf"), pages: 1))
    let movie = DroppedFile(url: dir.file("c.mov"), kind: FileKind(url: dir.file("c.mov")), byteSize: 1)
    let text = DroppedFile(url: dir.file("d.txt"), kind: FileKind(url: dir.file("d.txt")), byteSize: 1)

    let plan = QuickAction.compress.plan(for: [img, movie, pdf, text], settings: AppSettings(quality: 0.6))
    #expect(
      plan.steps == [
        .init(operation: .compress(quality: 0.6), files: [img, pdf]),
        .init(operation: .compressVideo(.strength(.medium)), files: [movie]),
      ])
    #expect(plan.rejected.map(\.file) == ["d.txt"])
  }

  @Test func runnerConvertsAndReportsBadInputs() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("photo.png"), type: "public.png")
    let missing = dir.file("gone.png")
    let out = dir.file("out")
    let result = await QuickActionRunner.run(
      .convertImage(.jpeg), on: [src, missing], settings: AppSettings(outputLocation: .folder(out)),
      engine: JobEngine())

    #expect(result.outputs.map(\.lastPathComponent) == ["photo.jpg"])
    #expect(result.outputs.allSatisfy { $0.path.hasPrefix(out.path) })
    #expect(result.failures.map(\.file) == ["gone.png"])
  }

  @Test func runnerResizesAndMakesPDF() async throws {
    let dir = try TempDir()
    let a = try Fixtures.writeImage(to: dir.file("a.png"), type: "public.png", width: 200, height: 100)
    let b = try Fixtures.writeImage(to: dir.file("b.png"), type: "public.png")
    let engine = JobEngine()

    let resized = await QuickActionRunner.run(
      .resize(.maxEdge(50)), on: [a], settings: AppSettings(), engine: engine)
    #expect(resized.failures.isEmpty)
    let output = try #require(resized.outputs.first)
    let props = Fixtures.properties(of: output)
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 50)

    let pdf = await QuickActionRunner.run(.makePDF, on: [a, b], settings: AppSettings(), engine: engine)
    #expect(pdf.failures.isEmpty)
    #expect(pdf.outputs.count == 1)
    #expect(pdf.outputs.first?.pathExtension == "pdf")
  }

  @Test func runnerReportsValidationMessage() async throws {
    let dir = try TempDir()
    let pdf = try Fixtures.writePDF(to: dir.file("a.pdf"), pages: 1)
    let result = await QuickActionRunner.run(.resize(.percent(50)), on: [pdf], settings: AppSettings())
    #expect(result.outputs.isEmpty)
    #expect(result.failures.count == 1)
    #expect(result.failures.first?.file == "")

    let none = await QuickActionRunner.run(.compress, on: [], settings: AppSettings())
    #expect(none.failures.map(\.message) == ["No files were given."])
  }

  @Test func parsesCommandLine() throws {
    let cwd = URL(fileURLWithPath: "/tmp/work", isDirectory: true)
    #expect(try QuickActionCommand.parse(["app"], currentDirectory: cwd) == nil)

    let command = try #require(
      try QuickActionCommand.parse(
        ["app", "--run", "convert-image:png", "a.jpg", "--out", "../out", "/x/b.heic"], currentDirectory: cwd)
    )
    #expect(command.action == .convertImage(.png))
    #expect(command.files.map(\.path) == ["/tmp/work/a.jpg", "/x/b.heic"])
    #expect(command.outputFolder?.path == "/tmp/out")

    #expect(throws: DropError.self) { try QuickActionCommand.parse(["app", "--run"], currentDirectory: cwd) }
    #expect(throws: DropError.self) {
      try QuickActionCommand.parse(["app", "--run", "explode", "a.png"], currentDirectory: cwd)
    }
    #expect(throws: DropError.self) {
      try QuickActionCommand.parse(["app", "--run", "compress"], currentDirectory: cwd)
    }
    #expect(throws: DropError.self) {
      try QuickActionCommand.parse(["app", "--run", "compress", "a.png", "--out"], currentDirectory: cwd)
    }
  }

  /// The Finder services in scripts/bundle.sh name their action by spec; each must parse.
  @Test func bundleServiceSpecsParse() throws {
    let script = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("scripts/bundle.sh")
    let lines = try String(contentsOf: script, encoding: .utf8).split(separator: "\n")
    let specs = lines.compactMap { line -> String? in
      let words = line.trimmingCharacters(in: .whitespaces).split(separator: "\"")
      guard words.first == "service ", words.count >= 3 else { return nil }
      return words[2].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)
    }
    #expect(specs.count >= 8)
    for spec in specs {
      #expect(QuickAction(spec: spec) != nil, "\(spec)")
    }
  }

  @Test func queueRunsRequestsInOrder() {
    var queue = QuickActionQueue()
    #expect(queue.isEmpty)
    #expect(queue.next() == nil)
    let a = URL(fileURLWithPath: "/tmp/a.png")
    let b = URL(fileURLWithPath: "/tmp/b.mov")
    queue.enqueue(.convertImage(.jpeg), on: [a])
    queue.enqueue(.compress, on: [a, b])
    queue.enqueue(.makePDF, on: [b])
    #expect(queue.next() == .init(action: .convertImage(.jpeg), urls: [a]))
    queue.enqueue(.resize(.percent(50)), on: [a])
    #expect(queue.next() == .init(action: .compress, urls: [a, b]))
    #expect(queue.next() == .init(action: .makePDF, urls: [b]))
    #expect(queue.next() == .init(action: .resize(.percent(50)), urls: [a]))
    #expect(queue.next() == nil)
    #expect(queue.isEmpty)
  }

  @Test func queueRemoveAllDropsWaitingRequests() {
    var queue = QuickActionQueue()
    queue.enqueue(.compress, on: [URL(fileURLWithPath: "/tmp/a")])
    queue.enqueue(.makePDF, on: [URL(fileURLWithPath: "/tmp/b")])
    queue.removeAll()
    #expect(queue.isEmpty)
    #expect(queue.next() == nil)
  }
}
