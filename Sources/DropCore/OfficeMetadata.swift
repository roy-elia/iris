import Foundation

/// Metadata in Word, Excel and PowerPoint files (Office Open XML): a zip of XML parts, with
/// the document properties in `docProps/` and people's names inside comments, tracked
/// changes and settings.
extension MetadataOps {
  /// Writes a copy of `source` with no document properties (author, company, template,
  /// edit time, dates, custom properties, thumbnail), with names on comments and tracked
  /// changes replaced by "Author" as Office's own Remove Personal Information does, no
  /// template path or printer names, and zeroed timestamps inside the zip.
  public static func stripOffice(_ source: URL, destination: URL) async throws {
    try await rewriteOffice(source, destination: destination) { package in
      try removeDocumentProperties(in: package)
      try removePersonalInformation(in: package)
    }
  }

  /// Writes a copy of `target` with `source`'s document properties in place of its own.
  /// Application statistics (page and word counts, the app's name) only go across between
  /// files of the same type, since each app writes its own.
  static func copyOffice(from source: URL, onto target: URL, destination: URL) async throws {
    guard MetadataSupport(FileKind(url: source)) == .office else {
      throw DropError.wrongInput(
        "Word, Excel and PowerPoint files can only take metadata from another Word, Excel or PowerPoint file."
      )
    }
    let sourcePackage = try await unpack(source)
    defer { try? FileManager.default.removeItem(at: sourcePackage) }
    let sameType = source.pathExtension.lowercased() == target.pathExtension.lowercased()
    try await rewriteOffice(target, destination: destination) { package in
      try removeDocumentProperties(in: package)
      for part in DocumentPart.allCases where part != .thumbnail && (sameType || part != .app) {
        let from = sourcePackage.appendingPathComponent(part.path)
        guard FileManager.default.fileExists(atPath: from.path) else { continue }
        let to = package.appendingPathComponent(part.path)
        try FileManager.default.createDirectory(
          at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: from, to: to)
        try insert(
          #"<Relationship Id="rIdFDU\#(part.rawValue)" Type="\#(part.relationship)" Target="\#(part.path)"/>"#,
          before: "</Relationships>", in: package.appendingPathComponent("_rels/.rels"))
        try insert(
          #"<Override PartName="/\#(part.path)" ContentType="\#(part.contentType)"/>"#,
          before: "</Types>", in: package.appendingPathComponent("[Content_Types].xml"))
      }
    }
  }

  /// The parts under `docProps/`.
  enum DocumentPart: String, CaseIterable {
    case core, app, custom, thumbnail

    var path: String { self == .thumbnail ? "docProps/thumbnail.jpeg" : "docProps/\(rawValue).xml" }

    var relationship: String {
      switch self {
      case .core: "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"
      case .app: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties"
      case .custom: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties"
      case .thumbnail: "http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"
      }
    }

    var contentType: String {
      switch self {
      case .core: "application/vnd.openxmlformats-package.core-properties+xml"
      case .app: "application/vnd.openxmlformats-officedocument.extended-properties+xml"
      case .custom: "application/vnd.openxmlformats-officedocument.custom-properties+xml"
      case .thumbnail: "image/jpeg"
      }
    }
  }

  // MARK: Package edits

  /// Deletes `docProps/` and every reference to it.
  static func removeDocumentProperties(in package: URL) throws {
    try edit(package.appendingPathComponent("_rels/.rels")) {
      $0.replacing(#/<Relationship\b[^>]*Target="/?docProps/[^"]*"[^>]*/>/#, with: "")
    }
    try edit(package.appendingPathComponent("[Content_Types].xml")) {
      $0.replacing(#/<Override\b[^>]*PartName="/docProps/[^"]*"[^>]*/>/#, with: "")
    }
    try? FileManager.default.removeItem(at: package.appendingPathComponent("docProps"))
  }

  /// Names and IDs of the people who commented or edited, the template's path (which
  /// usually holds a user name) and printer names.
  static func removePersonalInformation(in package: URL) throws {
    let paths = FileManager.default.subpaths(atPath: package.path) ?? []
    for path in paths where path.hasSuffix(".xml") || path.hasSuffix(".rels") {
      try edit(package.appendingPathComponent(path)) { xml in
        var xml = xml
        if path.hasPrefix("word/") {
          // Comments, tracked changes and the list of people.
          xml = xml.replacing(#/(w(?:15)?:author)="[^"]*"/#) { #"\#($0.1)="Author""# }
          xml = xml.replacing(#/(w:initials)="[^"]*"/#) { #"\#($0.1)="A""# }
          xml = xml.replacing(#/<w15:presenceInfo\b[^>]*/>/#, with: "")
          xml = xml.replacing(#/<w:attachedTemplate\b[^>]*/>/#, with: "")
        }
        if path == "word/_rels/settings.xml.rels" {
          xml = xml.replacing(#/<Relationship\b[^>]*attachedTemplate"[^>]*/>/#, with: "")
        }
        if path.hasPrefix("xl/comments") {
          xml = xml.replacing(#/<author>[^<]*</author>/#, with: "<author>Author</author>")
        }
        if path.hasPrefix("xl/persons/") || path == "ppt/authors.xml" || path == "ppt/commentAuthors.xml" {
          xml = xml.replacing(#/\b(displayName|name)="[^"]*"/#) { #"\#($0.1)="Author""# }
          xml = xml.replacing(#/\binitials="[^"]*"/#, with: #"initials="A""#)
          xml = xml.replacing(#/\buserId="[^"]*"/#, with: #"userId="""#)
          xml = xml.replacing(#/\bproviderId="[^"]*"/#, with: #"providerId="None""#)
        }
        return xml
      }
    }
    // Printer settings are a Windows DEVMODE; its first 64 bytes are the printer's name.
    for path in paths where path.contains("printerSettings/") {
      let url = package.appendingPathComponent(path)
      guard var data = try? Data(contentsOf: url), !data.isEmpty else { continue }
      data.replaceSubrange(0..<min(64, data.count), with: Data(count: min(64, data.count)))
      try data.write(to: url)
    }
  }

  private static func edit(_ url: URL, _ change: (String) -> String) throws {
    guard let xml = try? String(contentsOf: url, encoding: .utf8) else { return }
    let changed = change(xml)
    if changed != xml { try changed.write(to: url, atomically: true, encoding: .utf8) }
  }

  private static func insert(_ element: String, before closing: String, in url: URL) throws {
    try edit(url) { xml in
      guard let end = xml.range(of: closing, options: .backwards) else { return xml }
      return xml.replacingCharacters(in: end.lowerBound..<end.lowerBound, with: element)
    }
  }

  // MARK: Zip

  private static func unpack(_ url: URL) async throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fdu-office-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    do {
      try await SystemProcess.run("/usr/bin/unzip", ["-q", "-o", url.path, "-d", dir.path])
    } catch {
      try? FileManager.default.removeItem(at: dir)
      throw DropError.readFailed(url.lastPathComponent)
    }
    guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("[Content_Types].xml").path)
    else {
      try? FileManager.default.removeItem(at: dir)
      throw DropError.readFailed(url.lastPathComponent)
    }
    return dir
  }

  /// Unzips `source`, lets `change` edit the parts, and zips them back up to `destination`
  /// with the content types first (as Office writes them), every entry dated 1 January 1980
  /// and no extra fields (owner IDs, precise times).
  private static func rewriteOffice(
    _ source: URL, destination: URL, change: (URL) throws -> Void
  ) async throws {
    let package = try await unpack(source)
    defer { try? FileManager.default.removeItem(at: package) }
    do {
      try change(package)
      var epoch = DateComponents(calendar: Calendar(identifier: .gregorian), year: 1980, month: 1, day: 1)
      epoch.timeZone = .current
      let all = FileManager.default.enumerator(at: package, includingPropertiesForKeys: nil)
      while let url = all?.nextObject() as? URL {
        try FileManager.default.setAttributes([.modificationDate: epoch.date!], ofItemAtPath: url.path)
      }
      // -nw: "[Content_Types].xml" is a name, not a wildcard pattern.
      try await SystemProcess.run(
        "/usr/bin/zip", ["-q", "-X", "-D", "-nw", "-r", destination.path, "[Content_Types].xml", "."],
        in: package)
      removeExtendedAttributes(from: destination)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }
}
