import Foundation

/// One metadata value, as ExifTool names it ("EXIF:Artist" → group "EXIF", tag "Artist").
public struct MetadataField: Equatable, Hashable, Sendable, Identifiable {
  public let group: String
  public let tag: String
  public let value: String

  public var id: String { "\(group):\(tag)" }

  public init(group: String, tag: String, value: String) {
    self.group = group
    self.tag = tag
    self.value = value
  }
}

/// A change to one tag: a new value, or nil to remove it. `tag` is group-qualified
/// ("XMP-dc:Title"); "GPS:all" with nil removes all location data.
public struct MetadataEdit: Codable, Equatable, Hashable, Sendable {
  public var tag: String
  public var value: String?

  public init(tag: String, value: String?) {
    self.tag = tag
    self.value = value
  }

  /// Removes every GPS tag.
  public static let removeLocation = MetadataEdit(tag: "GPS:all", value: nil)
}

/// The fields the metadata editor offers, with the tag each one writes.
public struct EditableField: Sendable, Identifiable {
  public let label: String
  public let tag: String
  /// Other tags that hold the same information and are read as fallbacks.
  public let alternatives: [String]
  public var id: String { tag }

  public static let all: [EditableField] = [
    .init(label: "Title", tag: "XMP-dc:Title", alternatives: ["IPTC:ObjectName"]),
    .init(
      label: "Description", tag: "EXIF:ImageDescription",
      alternatives: ["XMP-dc:Description", "IPTC:Caption-Abstract"]),
    .init(label: "Artist", tag: "EXIF:Artist", alternatives: ["XMP-dc:Creator", "IPTC:By-line"]),
    .init(
      label: "Copyright", tag: "EXIF:Copyright", alternatives: ["XMP-dc:Rights", "IPTC:CopyrightNotice"]),
    .init(label: "Keywords", tag: "XMP-dc:Subject", alternatives: ["IPTC:Keywords"]),
    .init(label: "Date taken", tag: "EXIF:DateTimeOriginal", alternatives: ["XMP-exif:DateTimeOriginal"]),
  ]
}

/// Reads and writes metadata with the bundled ExifTool, falling back to ImageIO for
/// reading when ExifTool isn't available.
public enum MetadataOps {
  /// Every readable field, sorted by group then tag. File-system and ExifTool's own
  /// bookkeeping fields are left out.
  public static func read(_ url: URL) async throws -> [MetadataField] {
    guard ToolLocator.isAvailable(.exiftool) else {
      return try ImageOps.metadata(of: url).map { key, value in
        let parts = key.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count == 2
          ? MetadataField(group: parts[0], tag: parts[1], value: value)
          : MetadataField(group: "Image", tag: key, value: value)
      }.sorted { ($0.group, $0.tag) < ($1.group, $1.tag) }
    }
    let output = try await ToolRunner.run(
      .exiftool, ["-j", "-G1", "-s", "-struct", "-api", "LargeFileSupport=1", url.path])
    guard
      let array = try JSONSerialization.jsonObject(with: output.stdout) as? [[String: Any]],
      let dict = array.first
    else { throw DropError.readFailed(url.lastPathComponent) }
    let hiddenGroups: Set<String> = ["ExifTool", "System", "File"]
    return dict.compactMap { key, value -> MetadataField? in
      let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
      guard parts.count == 2, !hiddenGroups.contains(parts[0]) else { return nil }
      return MetadataField(group: parts[0], tag: parts[1], value: describe(value))
    }.sorted { ($0.group, $0.tag) < ($1.group, $1.tag) }
  }

  /// The current value for an editable field: its own tag, else the first alternative.
  public static func value(of field: EditableField, in fields: [MetadataField]) -> String? {
    for tag in [field.tag] + field.alternatives {
      let parts = tag.split(separator: ":", maxSplits: 1).map(String.init)
      if let match = fields.first(where: { groupMatches(parts[0], $0.group) && $0.tag == parts[1] }) {
        return match.value
      }
    }
    return nil
  }

  /// Reading uses ExifTool's specific groups (`IFD0`, `ExifIFD`); writing uses the
  /// general `EXIF` group, which covers them all.
  static func groupMatches(_ wanted: String, _ actual: String) -> Bool {
    if wanted == actual { return true }
    return wanted == "EXIF" && ["IFD0", "IFD1", "ExifIFD", "SubIFD"].contains(actual)
  }

  /// Writes a copy of `source` with `edits` applied. The original is never touched.
  public static func write(_ source: URL, edits: [MetadataEdit], destination: URL) async throws {
    guard !edits.isEmpty else { throw DropError.wrongInput("There are no metadata changes to save.") }
    guard ToolLocator.isAvailable(.exiftool) else { throw ToolError.missing(.exiftool) }
    var args = ["-q", "-m", "-charset", "UTF8", "-sep", ", "]
    for edit in edits {
      if let value = edit.value, !value.isEmpty {
        args.append("-\(edit.tag)=\(value)")
      } else {
        args.append("-\(edit.tag)=")
      }
    }
    args += ["-o", destination.path, source.path]
    do {
      _ = try await ToolRunner.run(.exiftool, args)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
    guard FileManager.default.fileExists(atPath: destination.path) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  /// Copies all metadata from `source` onto `destination` in place (used after encoders
  /// that drop it, like cwebp). Orientation is reset, since pixels were already rotated.
  public static func copyAll(from source: URL, to destination: URL) async throws {
    guard ToolLocator.isAvailable(.exiftool) else { return }
    _ = try await ToolRunner.run(
      .exiftool,
      [
        "-q", "-m", "-overwrite_original", "-tagsFromFile", source.path, "-all:all", "-Orientation=",
        destination.path,
      ])
  }

  private static func describe(_ value: Any) -> String {
    switch value {
    case let s as String: s
    case let n as NSNumber: n.stringValue
    case let a as [Any]: a.map(describe).joined(separator: ", ")
    case let d as [String: Any]:
      d.sorted { $0.key < $1.key }.map { "\($0.key): \(describe($0.value))" }.joined(separator: "; ")
    default: String(describing: value)
    }
  }
}
