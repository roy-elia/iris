#if DEBUG
  import Foundation

  /// Debug-only sample files that macOS can read but not write, for the unit tests and the
  /// feature self-test.
  public enum SampleFiles {
    /// A camera-RAW DNG: an uncompressed 16-bit RGGB Bayer mosaic, red on the left half and
    /// blue on the right. ImageIO's RAW decoder ignores DNGs much smaller than this.
    public static func writeDNG(to url: URL, width: Int = 512, height: Int = 384) throws {
      struct Entry {
        let tag: UInt16
        let type: UInt16
        let count: UInt32
        let data: [UInt8]
      }
      func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
      func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) } }
      func shorts(_ tag: UInt16, _ v: [UInt16]) -> Entry {
        Entry(tag: tag, type: 3, count: UInt32(v.count), data: v.flatMap(le16))
      }
      func longs(_ tag: UInt16, _ v: [UInt32]) -> Entry {
        Entry(tag: tag, type: 4, count: UInt32(v.count), data: v.flatMap(le32))
      }
      func bytes(_ tag: UInt16, _ v: [UInt8]) -> Entry {
        Entry(tag: tag, type: 1, count: UInt32(v.count), data: v)
      }
      func ascii(_ tag: UInt16, _ s: String) -> Entry {
        let b = Array(s.utf8) + [0]
        return Entry(tag: tag, type: 2, count: UInt32(b.count), data: b)
      }
      /// RATIONAL (5) or SRATIONAL (10) values with a denominator of 10,000.
      func rationals(_ tag: UInt16, _ v: [Double], signed: Bool) -> Entry {
        let data = v.flatMap { le32(UInt32(bitPattern: Int32(($0 * 10000).rounded()))) + le32(10000) }
        return Entry(tag: tag, type: signed ? 10 : 5, count: UInt32(v.count), data: data)
      }

      var pixels: [UInt8] = []
      pixels.reserveCapacity(width * height * 2)
      for y in 0..<height {
        for x in 0..<width {
          let rgb: [UInt16] = x < width / 2 ? [40000, 8000, 4000] : [4000, 8000, 40000]
          // RGGB: even rows are R G, odd rows G B.
          pixels += le16(rgb[y % 2 == 0 ? x % 2 : 1 + x % 2])
        }
      }
      let stripOffsetIndex = 8
      var entries = [
        longs(254, [0]), longs(256, [UInt32(width)]), longs(257, [UInt32(height)]), shorts(258, [16]),
        shorts(259, [1]), shorts(262, [32803]), ascii(271, "File Drop Utility"), ascii(272, "Sample"),
        longs(273, [0]), shorts(274, [1]), shorts(277, [1]), longs(278, [UInt32(height)]),
        longs(279, [UInt32(pixels.count)]), shorts(284, [1]),
        shorts(33421, [2, 2]), bytes(33422, [0, 1, 1, 2]),
        bytes(50706, [1, 4, 0, 0]), bytes(50707, [1, 1, 0, 0]), ascii(50708, "File Drop Utility Sample"),
        longs(50717, [65535]),
        // XYZ → camera: the camera here is linear sRGB.
        rationals(
          50721, [3.2406, -1.5372, -0.4986, -0.9689, 1.8758, 0.0415, 0.0557, -0.2040, 1.0570], signed: true),
        rationals(50728, [1, 1, 1], signed: false), shorts(50778, [21]),
      ]
      // Values over 4 bytes go after the IFD, word-aligned; the pixels come last.
      let ifdEnd = 8 + 2 + entries.count * 12 + 4
      var extra: [UInt8] = []
      var offsets: [Int?] = []
      for e in entries {
        guard e.data.count > 4 else {
          offsets.append(nil)
          continue
        }
        offsets.append(ifdEnd + extra.count)
        extra += e.data
        if extra.count % 2 == 1 { extra.append(0) }
      }
      entries[stripOffsetIndex] = longs(273, [UInt32(ifdEnd + extra.count)])
      var out: [UInt8] = [0x49, 0x49, 42, 0] + le32(8) + le16(UInt16(entries.count))
      for (e, offset) in zip(entries, offsets) {
        out += le16(e.tag) + le16(e.type) + le32(e.count)
        out += offset.map { le32(UInt32($0)) } ?? (e.data + [UInt8](repeating: 0, count: 4 - e.data.count))
      }
      out += le32(0) + extra + pixels
      try Data(out).write(to: url)
    }

    /// Zips XML parts into a workbook (the layout .xlsx and .ods files use).
    static func zipParts(_ parts: [String: String], to url: URL) async throws {
      let dir = try SystemProcess.scratchDirectory()
      defer { try? FileManager.default.removeItem(at: dir) }
      for (path, text) in parts {
        let file = dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(
          at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
      }
      try? FileManager.default.removeItem(at: url)
      try await SystemProcess.run("/usr/bin/zip", ["-qrX", url.path, "."], in: dir)
    }

    /// An Excel workbook with two sheets of inline-string and number cells.
    public static func writeXLSX(to url: URL) async throws {
      let ns = "http://schemas.openxmlformats.org"
      let rel = "\(ns)/officeDocument/2006/relationships"
      let main = "application/vnd.openxmlformats-officedocument.spreadsheetml"
      func sheet(_ rows: [[String]]) -> String {
        let body = rows.enumerated().map { r, cells in
          let cs = cells.enumerated().map { c, v in
            let ref = "\(Character(UnicodeScalar(65 + c)!))\(r + 1)"
            return Double(v) != nil
              ? "<c r=\"\(ref)\"><v>\(v)</v></c>" : "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(v)</t></is></c>"
          }.joined()
          return "<row r=\"\(r + 1)\">\(cs)</row>"
        }.joined()
        return "<worksheet xmlns=\"\(ns)/spreadsheetml/2006/main\"><sheetData>\(body)</sheetData></worksheet>"
      }
      try await zipParts(
        [
          "[Content_Types].xml": """
          <Types xmlns="\(ns)/package/2006/content-types">\
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
          <Default Extension="xml" ContentType="application/xml"/>\
          <Override PartName="/xl/workbook.xml" ContentType="\(main).sheet.main+xml"/>\
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="\(main).worksheet+xml"/>\
          <Override PartName="/xl/worksheets/sheet2.xml" ContentType="\(main).worksheet+xml"/></Types>
          """,
          "_rels/.rels": """
          <Relationships xmlns="\(ns)/package/2006/relationships">\
          <Relationship Id="rId1" Type="\(rel)/officeDocument" Target="xl/workbook.xml"/></Relationships>
          """,
          "xl/_rels/workbook.xml.rels": """
          <Relationships xmlns="\(ns)/package/2006/relationships">\
          <Relationship Id="rId1" Type="\(rel)/worksheet" Target="worksheets/sheet1.xml"/>\
          <Relationship Id="rId2" Type="\(rel)/worksheet" Target="worksheets/sheet2.xml"/></Relationships>
          """,
          "xl/workbook.xml": """
          <workbook xmlns="\(ns)/spreadsheetml/2006/main" xmlns:r="\(rel)"><sheets>\
          <sheet name="Budget" sheetId="1" r:id="rId1"/><sheet name="Staff" sheetId="2" r:id="rId2"/>\
          </sheets></workbook>
          """,
          "xl/worksheets/sheet1.xml": sheet([["Item", "Cost"], ["Paper", "12.5"], ["Ink", "30"]]),
          "xl/worksheets/sheet2.xml": sheet([["Name", "Role"], ["Ada", "Lead"]]),
        ], to: url)
    }

    /// An OpenDocument spreadsheet with one sheet.
    public static func writeODS(to url: URL) async throws {
      let cell = { (v: String) in "<table:table-cell><text:p>\(v)</text:p></table:table-cell>" }
      let rows = [["Day", "Steps"], ["Mon", "4200"], ["Tue", "6100"]].map {
        "<table:table-row>\($0.map(cell).joined())</table:table-row>"
      }.joined()
      try await zipParts(
        [
          "mimetype": "application/vnd.oasis.opendocument.spreadsheet",
          "META-INF/manifest.xml": """
          <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" \
          manifest:version="1.2"><manifest:file-entry manifest:full-path="/" \
          manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>\
          <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>\
          </manifest:manifest>
          """,
          "content.xml": """
          <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" \
          xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" \
          xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"><office:body><office:spreadsheet>\
          <table:table table:name="Walks">\(rows)</table:table></office:spreadsheet></office:body>\
          </office:document-content>
          """,
        ], to: url)
    }

    /// A Keynote package holding only its saved preview, `pdf`. Without Keynote installed
    /// the app converts it from that preview.
    public static func writeKeynotePackage(to url: URL, preview pdf: URL) throws {
      let folder = url.appendingPathComponent("QuickLook")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try? FileManager.default.removeItem(at: folder.appendingPathComponent("Preview.pdf"))
      try FileManager.default.copyItem(at: pdf, to: folder.appendingPathComponent("Preview.pdf"))
    }
  }
#endif
