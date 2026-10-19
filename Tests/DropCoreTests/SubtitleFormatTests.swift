import Foundation
import Testing

@testable import DropCore

@Suite struct SubtitleFormatTests {
  private let cues = [
    SubtitleCue(start: 1, end: 2.5, text: "Hello <i>there</i>"),
    SubtitleCue(start: 3, end: 4.25, text: "Two\nlines"),
  ]

  @Test func recognisesExtensions() async {
    for (ext, format) in [
      ("ass", SubtitleFormat.ass), ("SSA", .ssa), ("smi", .smi), ("sami", .smi), ("lrc", .lrc),
    ] {
      #expect(FileKind(url: URL(fileURLWithPath: "/a.\(ext)")) == .subtitle(format), "\(ext)")
    }
    #expect(SubtitleFormat.smi.displayName == "SAMI")
  }

  @Test(arguments: [SubtitleFormat.ass, .ssa, .smi])
  func roundTripsTimingAndText(format: SubtitleFormat) async {
    let back = SubtitleOps.parse(SubtitleOps.write(cues, as: format), as: format)
    #expect(back == cues, "\(format): \(back)")
  }

  @Test func lrcRoundTripsAsOneLinePerCue() async {
    let text = SubtitleOps.write(cues, as: .lrc)
    #expect(text.hasPrefix("[00:01.00]Hello there\n[00:02.50]\n[00:03.00]Two / lines\n"))
    let back = SubtitleOps.parse(text, as: .lrc)
    #expect(back.map(\.start) == [1, 3] && back.map(\.end) == [2.5, 4.25])
  }

  @Test func readsASSWithItsOwnFieldOrderAndOverrides() async {
    let ass = """
      [Script Info]
      Title: Test

      [Events]
      Format: Layer, Start, End, Style, Actor, MarginL, MarginR, MarginV, Effect, Text
      Comment: 0,0:00:00.00,0:00:05.00,Default,,0,0,0,,not shown
      Dialogue: 0,0:00:02.00,0:00:03.00,Default,,0,0,0,,{\\pos(10,20)}Second, with a comma
      Dialogue: 0,0:00:01.00,0:00:01.50,Default,Bob,0,0,0,,{\\i1}First{\\i0}\\Nline two
      """
    let parsed = SubtitleOps.parse(ass, as: .ass)
    #expect(parsed.map(\.text) == ["<i>First</i>\nline two", "Second, with a comma"])
    #expect(parsed.first?.start == 1 && parsed.first?.end == 1.5)
  }

  @Test func readsSAMIFirstLanguageAndClears() async {
    let sami = """
      <SAMI><BODY>
      <SYNC Start=1000><P Class=KRCC>안녕하세요<br>둘째 줄
      <P Class=ENCC>Hello
      <SYNC Start=2500><P Class=KRCC>&nbsp;
      <SYNC Start=3000><P Class=KRCC>다음 &amp; 끝
      </BODY></SAMI>
      """
    let parsed = SubtitleOps.parse(sami, as: .smi)
    #expect(parsed.count == 2)
    #expect(parsed.first == SubtitleCue(start: 1, end: 2.5, text: "안녕하세요\n둘째 줄"))
    #expect(parsed.last?.text == "다음 & 끝")
  }

  @Test func readsLRCWithSharedStampsAndOffset() async {
    let lrc =
      "[ar:Someone]\n[offset:+500]\n[00:10.00][00:20.00]Chorus\n[00:15.50]<00:15.50>Verse <00:16.00>words\n"
    let parsed = SubtitleOps.parse(lrc, as: .lrc)
    #expect(parsed.map(\.text) == ["Chorus", "Verse words", "Chorus"])
    #expect(parsed.map(\.start) == [9.5, 15, 19.5])
    #expect(parsed[0].end == 15)
  }

  @Test func decodesLegacyKoreanFiles() async throws {
    let text = "<SAMI><BODY><SYNC Start=0><P>자막 테스트<SYNC Start=1500><P>&nbsp;</BODY></SAMI>"
    let cp949 = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
    let data = try #require(text.data(using: cp949))
    #expect(String(data: data, encoding: .utf8) == nil)
    #expect(try SubtitleOps.decode(data) == text)

    let dir = try TempDir()
    let smi = dir.file("drama.smi")
    try data.write(to: smi)
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convertSubtitles(.srt), on: [try DroppedFile.load(smi)])
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(try String(contentsOf: out, encoding: .utf8) == "1\n00:00:00,000 --> 00:00:01,500\n자막 테스트\n")
  }

  @Test func decodesUTF16AndWestern() async throws {
    let utf16 = Data([0xFF, 0xFE]) + "[00:01.00]Hi".data(using: .utf16LittleEndian)!
    #expect(try SubtitleOps.decode(utf16) == "[00:01.00]Hi")
    #expect(try SubtitleOps.decode(Data([0x43, 0x61, 0x66, 0xE9])) == "Café")
  }
}
