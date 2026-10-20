import AppKit
import Foundation
import Testing

@testable import DropCore

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

/// Spoken audio made with macOS's `say`.
enum SpeechFixtures {
  static func say(_ text: String, to url: URL) throws -> URL {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    p.arguments = ["-o", url.path, text]
    try p.run()
    p.waitUntilExit()
    return url
  }
}

private let hasFFmpeg = ToolLocator.isAvailable(.ffmpeg) && ToolLocator.isAvailable(.ffprobe)

@Suite struct AIModelTests {
  @Test func wordsGroupIntoShortCues() {
    let words = [
      AIOps.Word(text: "Hello", start: 0, end: 0.4), AIOps.Word(text: " there.", start: 0.4, end: 0.9),
      AIOps.Word(text: " After", start: 2.5, end: 2.9), AIOps.Word(text: " a", start: 2.9, end: 3.0),
      AIOps.Word(text: " pause", start: 3.0, end: 3.5),
    ]
    let cues = AIOps.cues(from: words)
    #expect(cues.map(\.text) == ["Hello there.", "After a pause"])
    #expect(cues[1].start == 2.5 && cues[1].end == 3.5)
    let long = (0..<40).map {
      AIOps.Word(text: " word\($0)", start: Double($0) * 0.3, end: Double($0) * 0.3 + 0.25)
    }
    let split = AIOps.cues(from: long)
    #expect(split.count > 2)
    #expect(split.allSatisfy { $0.end - $0.start <= AIOps.maxCueSeconds + 0.3 })
  }

  @Test func longCuesWrapOntoTwoLines() {
    let text = "This sentence is long enough that it needs to wrap onto two lines"
    let wrapped = AIOps.wrap(text)
    #expect(wrapped.components(separatedBy: "\n").count == 2)
    #expect(wrapped.replacingOccurrences(of: "\n", with: " ") == text)
    #expect(AIOps.wrap("Short line") == "Short line")
  }

  @Test func namesAreMadeSafe() {
    #expect(AIOps.sanitizedName("\"Quarterly Revenue Report.pdf\"") == "Quarterly Revenue Report")
    #expect(AIOps.sanitizedName("Trip: Paris/Lyon 2026?") == "Trip ParisLyon 2026")
    #expect(AIOps.sanitizedName("First line\nsecond line") == "First line")
    #expect(AIOps.sanitizedName(String(repeating: "word ", count: 30)).count <= 60)
  }

  @Test func summariesBecomeMarkdown() {
    let md = AIOps.formatSummary(
      "OVERVIEW: Sales rose. Costs fell.\nPOINTS:\n- Revenue up 12%\n- Hiring in spring", title: "report.docx"
    )
    #expect(
      md.hasPrefix(
        "# Summary: report.docx\n\nSales rose. Costs fell.\n\n## Key points\n\n- Revenue up 12%\n- Hiring in spring"
      ))
    let loose = AIOps.formatSummary("Just a paragraph.", title: "x")
    #expect(loose.contains("Just a paragraph.") && !loose.contains("## Key points"))
  }

  @Test func longTextSplitsAtParagraphs() {
    let paragraph = String(repeating: "Sentence here. ", count: 100)
    let text = Array(repeating: paragraph, count: 10).joined(separator: "\n")
    let pieces = AIOps.chunks(text, size: 3_000)
    #expect(pieces.count >= 4)
    #expect(pieces.allSatisfy { $0.count <= 3_000 })
    #expect(pieces.joined(separator: "\n").count == text.count)
  }

  @Test func altTextFallsBackToDetectedFacts() {
    let facts = AIOps.ImageFacts(
      labels: ["beach", "sky", "people", "sand"], text: "OPEN", faces: 2, width: 800, height: 600)
    #expect(AIOps.fallbackAltText(facts) == "Beach, sky, people; 2 people; with the text \"OPEN\"")
    #expect(AIOps.cleanSentence("\"Image of a dog on a beach.\"") == "A dog on a beach.")
  }

  @Test func refusalsAreRecognised() {
    #expect(AIOps.isRefusal("I cannot summarise that. It contains copyrighted material."))
    #expect(AIOps.isRefusal("I’m sorry, but I can’t help with that."))
    #expect(!AIOps.isRefusal("OVERVIEW: Sales rose."))
    #expect(!AIOps.isRefusal("Icy Mountain Lake"))
  }

  @Test func renameAndUndo() throws {
    let dir = try TempDir()
    let a = dir.file("IMG_0001.png")
    try Data([1, 2, 3]).write(to: a)
    try Data([9]).write(to: dir.file("Beach Day.png"))
    let renamed = try AIOps.rename(a, to: "Beach Day")
    #expect(renamed.lastPathComponent == "Beach Day (1).png")
    #expect(!FileManager.default.fileExists(atPath: a.path))
    #expect(AIOps.undo([.init(from: a, to: renamed)]).isEmpty)
    #expect(try Data(contentsOf: a) == Data([1, 2, 3]))
  }

  @Test func aiQuickActionsParse() {
    #expect(QuickAction(spec: "transcribe") == .transcribe)
    #expect(QuickAction(spec: "summarise") == .summarize)
    #expect(QuickAction(spec: "rename-by-content")?.spec == "rename-by-content")
  }
}

/// These use the real on-device models, so they run only where they're available.
@Suite(.enabled(if: hasFFmpeg), .serialized) struct AIOpsTests {
  @Test func transcribesSpeechToSRT() async throws {
    let dir = try TempDir()
    let speech = try SpeechFixtures.say(
      "Hello and welcome to the quarterly review. Revenue grew twelve percent this year. Next we will discuss hiring plans.",
      to: dir.file("review.aiff"))
    let result = await Processor(settings: AppSettings()).run(.transcribe(.srt), on: try load(speech))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "review.srt")
    let srt = try String(contentsOf: out, encoding: .utf8)
    #expect(srt.hasPrefix("1\n00:00:00,"))
    #expect(srt.localizedCaseInsensitiveContains("quarterly review"))
    #expect(srt.localizedCaseInsensitiveContains("hiring"))
    #expect(SubtitleOps.parse(srt).count >= 2)
  }

  @Test func transcribesAVideosSoundtrack() async throws {
    let dir = try TempDir()
    let speech = try SpeechFixtures.say(
      "This clip explains the new office layout.", to: dir.file("voice.aiff"))
    let clip = dir.file("tour.mp4")
    _ = try await ToolRunner.run(
      .ffmpeg,
      [
        "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-f", "lavfi", "-i",
        "color=c=blue:s=320x240:r=15",
        "-i", speech.path, "-shortest", "-c:v", "h264_videotoolbox", "-b:v", "500k", "-c:a", "aac", clip.path,
      ])
    let result = await Processor(settings: AppSettings()).run(.transcribe(.vtt), on: try load(clip))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let vtt = try String(contentsOf: out, encoding: .utf8)
    #expect(vtt.hasPrefix("WEBVTT") && vtt.localizedCaseInsensitiveContains("office layout"))
  }

  @Test(.enabled(if: AIOps.languageModelAvailable)) func summarisesADocument() async throws {
    let dir = try TempDir()
    let text = """
      Quarterly report. Revenue grew twelve percent compared with last year, driven by strong sales in Europe. \
      Operating costs fell by three percent after the move to the new warehouse. \
      The company plans to hire twenty engineers in the spring and open an office in Lisbon. \
      Risks include higher shipping prices and a slower market in North America.
      """
    let doc = try DocFixtures.text(dir.file("q3.txt"), text)
    let result = await Processor(settings: AppSettings()).run(.summarize, on: try load(doc))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "q3 summary.md")
    let md = try String(contentsOf: out, encoding: .utf8)
    #expect(md.hasPrefix("# Summary: q3.txt"))
    #expect(md.contains("12") || md.localizedCaseInsensitiveContains("twelve"))
    #expect(md.count < text.count * 3)  // Heading and disclaimer included.
  }

  @Test(.enabled(if: AIOps.languageModelAvailable)) func writesAltText() async throws {
    let dir = try TempDir()
    let png = try DocFixtures.scannedPDF(dir.file("unused.pdf"), dir: dir)
    _ = png
    let image = dir.file("scan.png")  // Written by scannedPDF: "Invoice number 4821" on white.
    let result = await Processor(settings: AppSettings()).run(.altText, on: try load(image))
    let alt = try #require(result.notes.first, "\(result.failures)")
    #expect(!alt.isEmpty && alt.count < 220)
    #expect(!alt.lowercased().hasPrefix("image of"))
  }

  @Test(.enabled(if: AIOps.languageModelAvailable)) func renamesFromContentAndUndoes() async throws {
    let dir = try TempDir()
    let doc = try DocFixtures.text(
      dir.file("Document1.txt"),
      "Recipe for banana bread. Mash three ripe bananas, mix with flour, sugar and eggs, then bake for an hour."
    )
    let result = await Processor(settings: AppSettings()).run(.renameByContent, on: try load(doc))
    let renamed = try #require(result.outputs.first, "\(result.failures)")
    #expect(renamed.pathExtension == "txt" && renamed.lastPathComponent != "Document1.txt")
    #expect(renamed.lastPathComponent.localizedCaseInsensitiveContains("banana"))
    #expect(!FileManager.default.fileExists(atPath: doc.path))
    #expect(AIOps.undo(result.renames).isEmpty)
    #expect(FileManager.default.fileExists(atPath: doc.path))
  }
}
