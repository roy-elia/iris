import Foundation
import Testing

@testable import DropCore

@Suite struct DataOpsTests {
  private func convert(_ name: String, _ contents: String, to output: DataFormat) async throws -> String {
    let dir = try TempDir()
    let src = try dir.touch(name, contents: contents)
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convertData(output), on: [try DroppedFile.load(src)])
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.pathExtension == output.fileExtension)
    return try String(contentsOf: out, encoding: .utf8)
  }

  private func json(_ text: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(text.utf8))
  }

  @Test func recognisesDataFiles() async {
    #expect(FileKind(url: URL(fileURLWithPath: "/a.json")) == .data(.json))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.VCF")) == .data(.vcf))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.csv")).dataFormat == .csv)
    #expect(DataFormat.json.outputs == [.csv, .xml, .plist])
  }

  @Test func jsonToCSVFlattensAndQuotes() async throws {
    let csv = try await convert(
      "p.json",
      #"[{"name":"Lin, M","age":30,"ok":true,"tags":["a"],"addr":{"city":"Oslo"}},{"name":"Ada","extra":null}]"#,
      to: .csv)
    #expect(
      csv == "addr.city,age,name,ok,tags,extra\r\nOslo,30,\"Lin, M\",true,\"[\"\"a\"\"]\",\r\n,,Ada,,,\r\n")
  }

  @Test func jsonToCSVFindsTheRecordsArray() async throws {
    let csv = try await convert("r.json", #"{"count":1,"results":[{"id":7}]}"#, to: .csv)
    #expect(csv == "id\r\n7\r\n")
  }

  @Test func csvToJSONKeepsStrings() async throws {
    let out = try await convert("s.csv", "Name,Score,\nAda,9,x\n\"Lin, M\",08\n", to: .json)
    let records = try #require(try json(out) as? [[String: String]])
    #expect(
      records == [
        ["Name": "Ada", "Score": "9", "column 3": "x"], ["Name": "Lin, M", "Score": "08", "column 3": ""],
      ])
  }

  @Test func xmlToJSONGroupsRepeatsAndAttributes() async throws {
    let out = try await convert(
      "c.xml",
      #"<catalog><book id="1"><title>Swift</title></book><book id="2"><title>A &amp; B</title></book><note>hi</note></catalog>"#,
      to: .json)
    let root = try #require(try json(out) as? [String: Any])
    let catalog = try #require(root["catalog"] as? [String: Any])
    let books = try #require(catalog["book"] as? [[String: String]])
    #expect(books == [["@id": "1", "title": "Swift"], ["@id": "2", "title": "A & B"]])
    #expect(catalog["note"] as? String == "hi")
  }

  @Test func xmlToJSONRefusesBrokenXML() async throws {
    let dir = try TempDir()
    let src = try dir.touch("bad.xml", contents: "<a><b></a>")
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convertData(.json), on: [try DroppedFile.load(src)])
    #expect(result.failures.first?.message == "bad.xml isn't well-formed XML.")
  }

  @Test func plistRoundTripsThroughJSON() async throws {
    let dir = try TempDir()
    let plist = dir.file("s.plist")
    let date = Date(timeIntervalSince1970: 0)
    try PropertyListSerialization.data(
      fromPropertyList: ["theme": "dark", "n": 3, "when": date, "blob": Data([1, 2])], format: .binary,
      options: 0
    ).write(to: plist)
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convertData(.json), on: [try DroppedFile.load(plist)])
    let out = try String(contentsOf: try #require(result.outputs.first), encoding: .utf8)
    let object = try #require(try json(out) as? [String: Any])
    #expect(object["theme"] as? String == "dark" && object["n"] as? Int == 3)
    #expect(object["when"] as? String == "1970-01-01T00:00:00Z" && object["blob"] as? String == "AQI=")

    let back = try await convert("j.json", #"{"a":[1,null,"x"],"b":{"c":false}}"#, to: .plist)
    let value = try #require(
      try PropertyListSerialization.propertyList(from: Data(back.utf8), format: nil) as? [String: Any])
    #expect((value["a"] as? [Any])?.count == 2)
    #expect((value["b"] as? [String: Bool])?["c"] == false)
  }

  @Test func jsonToXMLUsesKeysAsElements() async throws {
    let xml = try await convert(
      "j.json", #"{"library":{"book":[{"title":"A<B"},{"title":"C"}],"2nd key":1}}"#, to: .xml)
    #expect(xml.contains("<library>"))
    #expect(xml.contains("<book>\n    <title>A&lt;B</title>\n  </book>\n  <book>"))
    #expect(xml.contains("<_2nd_key>1</_2nd_key>"))
    #expect(try xmlParses(xml))
  }

  private func xmlParses(_ xml: String) throws -> Bool { XMLParser(data: Data(xml.utf8)).parse() }

  @Test func vCardToCSV() async throws {
    let vcf = """
      BEGIN:VCARD\r
      VERSION:3.0\r
      FN:Ada Lovelace\r
      N:Lovelace;Ada;;;\r
      ORG:Analytical Engines\\, Ltd\r
      item1.EMAIL;TYPE=work:ada@example.com\r
      EMAIL:ada@home.example\r
      TEL;TYPE=cell:555-0100\r
      ADR:;;12 St James\\, Square;London;;SW1;UK\r
      NOTE:Line one\\nline two that is long enough to fold across the seventy-five byte limi\r
       t of vCard\r
      END:VCARD\r
      BEGIN:VCARD\r
      VERSION:3.0\r
      N:Turing;Alan;;;\r
      END:VCARD\r
      """
    let csv = try await convert("c.vcf", vcf, to: .csv)
    let rows = TableOps.parse(csv, separator: ",")
    #expect(rows[0].first == "Name" && rows.count == 3)
    #expect(rows[1][0] == "Ada Lovelace" && rows[1][1] == "Ada" && rows[1][2] == "Lovelace")
    #expect(rows[1][3] == "Analytical Engines, Ltd")
    #expect(rows[1][5] == "ada@example.com; ada@home.example" && rows[1][6] == "555-0100")
    #expect(rows[1][7] == "12 St James, Square, London, SW1, UK")
    #expect(
      rows[1][10]
        == "Line one\nline two that is long enough to fold across the seventy-five byte limit of vCard")
    #expect(rows[2][0] == "Alan Turing")
  }

  @Test func csvToVCardMatchesCommonHeaders() async throws {
    let out = try await convert(
      "c.csv",
      "First Name,Last Name,E-mail Address,Mobile,Company\nAda,Lovelace,a@x.org; b@x.org,555,\"Engines, Ltd\"\n,,,,\n",
      to: .vcf)
    #expect(
      out.hasPrefix(
        "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ada Lovelace\r\nN:Lovelace;Ada;;;\r\nORG:Engines\\, Ltd\r\n"))
    #expect(out.contains("EMAIL;TYPE=INTERNET:a@x.org\r\nEMAIL;TYPE=INTERNET:b@x.org\r\nTEL:555\r\n"))
    #expect(out.components(separatedBy: "BEGIN:VCARD").count == 2)
    // And back again.
    let cards = DataOps.parseVCards(out)
    #expect(cards.first?["EMAIL"] == ["a@x.org", "b@x.org"])
  }

  @Test func csvToVCardNeedsAContactColumn() async throws {
    let dir = try TempDir()
    let src = try dir.touch("scores.csv", contents: "Score,Level\n9,2\n")
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convertData(.vcf), on: [try DroppedFile.load(src)])
    #expect(result.failures.first?.message.contains("no Name, Email or Phone column") == true)
  }

  @Test func foldsLongLinesOnCharacterBoundaries() async {
    let line = "NOTE:" + String(repeating: "한", count: 40)
    let folded = DataOps.fold(line)
    #expect(folded.components(separatedBy: "\r\n ").allSatisfy { $0.utf8.count <= 75 })
    #expect(folded.replacingOccurrences(of: "\r\n ", with: "") == line)
  }

  @Test func refusesUnsupportedPairs() async throws {
    let dir = try TempDir()
    let xml = try DroppedFile.load(dir.touch("a.xml", contents: "<a/>"))
    #expect(Processor.validate(.convertData(.csv), files: [xml]) == "a.xml can't be converted to CSV.")
  }
}
