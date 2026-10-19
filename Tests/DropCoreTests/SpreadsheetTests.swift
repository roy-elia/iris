import Foundation
import PDFKit
import Testing

@testable import DropCore

/// Small workbooks written from XML parts and zipped with /usr/bin/zip.
enum SheetFixtures {
  static func zip(_ parts: [String: String], to url: URL) async throws -> URL {
    let dir = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
    for (path, text) in parts {
      let file = dir.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: file)
    }
    try await SystemProcess.run("/usr/bin/zip", ["-qr", url.path, "."], in: dir)
    try FileManager.default.removeItem(at: dir)
    return url
  }

  /// Two sheets: "Scores" (shared, inline, boolean and numeric cells, a gap at B2 and a
  /// skipped row 3) and an empty "Notes".
  static func xlsx(_ url: URL) async throws -> URL {
    let ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    return try await zip(
      [
        "xl/workbook.xml": """
        <workbook xmlns="\(ns)" xmlns:r="\(rel)"><sheets>
        <sheet name="Scores" sheetId="1" r:id="rId7"/><sheet name="Notes" sheetId="2" r:id="rId8"/>
        </sheets></workbook>
        """,
        "xl/_rels/workbook.xml.rels": """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId7" Target="worksheets/first.xml"/>
        <Relationship Id="rId8" Target="/xl/worksheets/second.xml"/>
        </Relationships>
        """,
        "xl/sharedStrings.xml": """
        <sst xmlns="\(ns)"><si><t>Name</t></si><si><t>Score</t></si>
        <si><r><t>Ada, </t></r><r><t>L.</t></r><rPh><t>ignored</t></rPh></si></sst>
        """,
        "xl/worksheets/first.xml": """
        <worksheet xmlns="\(ns)"><sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="b"><v>1</v></c></row>
        <row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2"><f>1+8.5</f><v>9.5</v></c></row>
        <row r="4"><c r="A4" t="inlineStr"><is><t>Lin "Q"</t></is></c></row>
        </sheetData></worksheet>
        """,
        "xl/worksheets/second.xml": "<worksheet xmlns=\"\(ns)\"><sheetData/></worksheet>",
      ], to: url)
  }

  /// One sheet with repeated cells and rows, spaces, an annotation and trailing padding.
  static func ods(_ url: URL) async throws -> URL {
    try await zip(
      [
        "mimetype": "application/vnd.oasis.opendocument.spreadsheet",
        "content.xml": """
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" \
        xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" \
        xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"><office:body><office:spreadsheet>
        <table:table table:name="Plan">
        <table:table-row><table:table-cell><text:p>a<text:s text:c="2"/>b</text:p></table:table-cell>
        <table:table-cell table:number-columns-repeated="2"><text:p>x</text:p></table:table-cell></table:table-row>
        <table:table-row table:number-rows-repeated="2"><table:table-cell table:number-columns-repeated="1024"/></table:table-row>
        <table:table-row><table:table-cell office:value-type="float" office:value="3">\
        <office:annotation><text:p>note</text:p></office:annotation><text:p>3.0</text:p></table:table-cell>
        <table:table-cell/><table:table-cell office:value-type="boolean" office:boolean-value="true"/>\
        <table:table-cell table:number-columns-repeated="16000"/></table:table-row>
        <table:table-row table:number-rows-repeated="1048570"><table:table-cell/></table:table-row>
        </table:table></office:spreadsheet></office:body></office:document-content>
        """,
      ], to: url)
  }
}

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

@Suite struct SpreadsheetTests {
  @Test func cellReferences() {
    #expect(SpreadsheetOps.column(of: "A1") == 0)
    #expect(SpreadsheetOps.column(of: "Z9") == 25)
    #expect(SpreadsheetOps.column(of: "AB12") == 27)
    #expect(SpreadsheetOps.row(of: "AB12") == 12)
    #expect(SpreadsheetOps.column(of: "12") == nil)
    #expect(SpreadsheetOps.fileSafe("Q1/Q2: totals") == "Q1-Q2- totals")
    #expect(SpreadsheetOps.padded([["a"], ["b", "c"]]) == [["a", ""], ["b", "c"]])
  }

  @Test func readsExcelSheets() async throws {
    let dir = try TempDir()
    let book = try await SheetFixtures.xlsx(dir.file("Book.xlsx"))
    let sheets = try await SpreadsheetOps.read(book, format: .xlsx)
    #expect(sheets.map(\.name) == ["Scores", "Notes"])
    #expect(
      sheets[0].rows == [["Name", "Score", "TRUE"], ["Ada, L.", "", "9.5"], [], ["Lin \"Q\""]])
    #expect(sheets[1].isEmpty)
  }

  @Test func readsOpenDocumentSheets() async throws {
    let dir = try TempDir()
    let book = try await SheetFixtures.ods(dir.file("Plan.ods"))
    let sheets = try await SpreadsheetOps.read(book, format: .ods)
    #expect(sheets.map(\.name) == ["Plan"])
    #expect(sheets[0].rows == [["a  b", "x", "x"], [], [], ["3.0", "", "TRUE"]])
  }

  @Test func savesEachSheetAsCSV() async throws {
    let dir = try TempDir()
    let book = try await SheetFixtures.xlsx(dir.file("Book.xlsx"))
    let files = try load(book)
    #expect(files[0].kind.isSpreadsheet)
    #expect(Processor.validate(.sheetsToCSV, files: files) == nil)
    let result = await Processor(settings: AppSettings()).run(.sheetsToCSV, on: files)
    let out = try #require(result.outputs.first, "\(result.failures)")
    // Only "Scores" has cells, so the CSV takes the workbook's own name.
    #expect(result.outputs.map(\.lastPathComponent) == ["Book.csv"])
    let text = try String(contentsOf: out, encoding: .utf8)
    #expect(text == "Name,Score,TRUE\r\n\"Ada, L.\",,9.5\r\n,,\r\n\"Lin \"\"Q\"\"\",,\r\n")
  }

  @Test func namesOneFilePerSheetWhenSeveralHaveCells() async throws {
    let dir = try TempDir()
    let row = "<row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>x</t></is></c></row>"
    let book = try await SheetFixtures.zip(
      [
        "xl/workbook.xml":
          "<workbook><sheets><sheet name=\"Jan\"/><sheet name=\"Feb/Mar\"/></sheets></workbook>",
        "xl/worksheets/sheet1.xml": "<worksheet><sheetData>\(row)</sheetData></worksheet>",
        "xl/worksheets/sheet2.xml": "<worksheet><sheetData>\(row)</sheetData></worksheet>",
      ], to: dir.file("Months.xlsx"))
    let result = await Processor(settings: AppSettings()).run(.sheetsToCSV, on: try load(book))
    #expect(result.outputs.map(\.lastPathComponent) == ["Months Jan.csv", "Months Feb-Mar.csv"])
  }

  @Test func refusesOtherFilesAndEmptyWorkbooks() async throws {
    let dir = try TempDir()
    let csv = try DocFixtures.text(dir.file("t.csv"), "a,b\n")
    #expect(Processor.validate(.sheetsToCSV, files: try load(csv))?.contains("spreadsheets") == true)
    let empty = try await SheetFixtures.zip(
      ["xl/workbook.xml": "<workbook><sheets><sheet name=\"A\"/></sheets></workbook>"], to: dir.file("E.xlsx")
    )
    let result = await Processor(settings: AppSettings()).run(.sheetsToCSV, on: try load(empty))
    #expect(result.outputs.isEmpty)
    #expect(result.failures.first?.message.contains("no cells") == true)
    let broken = try DocFixtures.text(dir.file("B.xlsx"), "not a zip")
    let bad = await Processor(settings: AppSettings()).run(.sheetsToCSV, on: try load(broken))
    #expect(bad.failures.first?.message.contains("Excel workbook") == true)
    if !IWorkApp.numbers.isInstalled {
      #expect(SpreadsheetOps.problem(.numbers) == "Needs Numbers")
      #expect(SpreadsheetOps.problem(.xlsx) == nil)
    }
  }

  @Test func stopsAToolThatHangs() async throws {
    let start = Date()
    await #expect(throws: (any Error).self) {
      try await SystemProcess.run("/bin/sleep", ["30"], timeout: 0.5)
    }
    #expect(Date().timeIntervalSince(start) < 10)
  }

  @Test func sampleWorkbooksAreReadable() async throws {
    let dir = try TempDir()
    let xlsx = dir.file("s.xlsx")
    try await SampleFiles.writeXLSX(to: xlsx)
    #expect(try await SpreadsheetOps.read(xlsx, format: .xlsx).map(\.name) == ["Budget", "Staff"])
    let ods = dir.file("s.ods")
    try await SampleFiles.writeODS(to: ods)
    #expect(try await SpreadsheetOps.read(ods, format: .ods).first?.rows.count == 3)
  }

  @Test(.enabled(if: !IWorkApp.numbers.isInstalled)) func odsToPDFWithoutNumbers() async throws {
    let dir = try TempDir()
    let book = try await SheetFixtures.ods(dir.file("Plan.ods"))
    let result = await Processor(settings: AppSettings()).run(.convertDocument(.pdf), on: try load(book))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let text = PDFDocument(url: out)?.string ?? ""
    #expect(text.contains("Plan") && text.contains("3.0") && text.contains("TRUE"))
  }

  @Test func sheetTablesEscapeText() {
    let html = SpreadsheetOps.html([Sheet(name: "A<B", rows: [["x", "<y>"], ["z"]])], title: "t")
    #expect(html.contains("<h2>A&lt;B</h2>") && html.contains("<td>&lt;y&gt;</td>") == false)
    #expect(html.contains("<th>&lt;y&gt;</th>") && html.contains("<tr><td>z</td><td></td></tr>"))
  }
}
