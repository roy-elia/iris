import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// How Split divides a PDF.
public enum PDFSplit: Codable, Equatable, Hashable, Sendable {
  /// One PDF per page.
  case everyPage
  /// One PDF per comma-separated group, such as "1-3,7,9-" (a trailing "-" means to the end).
  case ranges(String)

  /// The 0-based page indexes of each output, for a PDF of `pageCount` pages.
  public func groups(pageCount: Int) throws -> [[Int]] {
    switch self {
    case .everyPage:
      return (0..<pageCount).map { [$0] }
    case .ranges(let text):
      let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
      guard !parts.isEmpty else { throw DropError.wrongInput("Enter pages such as 1-3, 7.") }
      return try parts.map { part in
        let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
          .map { $0.trimmingCharacters(in: .whitespaces) }
        let first = Int(bounds[0])
        let last: Int? =
          switch bounds.count {
          case 1: first
          case 2: bounds[1].isEmpty ? pageCount : Int(bounds[1])
          default: nil
          }
        guard let first, let last, first >= 1, first <= last else {
          throw DropError.wrongInput("\"\(part)\" isn't a page or a range like 1-3.")
        }
        guard last <= pageCount else {
          throw DropError.wrongInput(
            "The PDF has \(pageCount) page\(pageCount == 1 ? "" : "s"); \"\(part)\" is past the end.")
        }
        return Array((first - 1)...(last - 1))
      }
    }
  }

  /// "page 3" or "pages 1-3", for output names.
  static func label(_ group: [Int]) -> String {
    guard let first = group.first, let last = group.last else { return "pages" }
    return first == last ? "page \(first + 1)" : "pages \(first + 1)-\(last + 1)"
  }
}

/// Split, multi-page TIFF and comic-book (CBZ) export.
public enum PDFExportOps {
  /// Writes one PDF per group, each named by `destination(group)`.
  public static func split(_ source: URL, plan: PDFSplit, destination: ([Int]) -> URL) throws -> [URL] {
    let doc = try PDFPageOps.open(source)
    let groups = try plan.groups(pageCount: doc.pageCount)
    var outputs: [URL] = []
    do {
      for group in groups {
        let output = PDFDocument()
        for index in group {
          guard let page = doc.page(at: index)?.copy() as? PDFPage else { continue }
          output.insert(page, at: output.pageCount)
        }
        let out = destination(group)
        guard output.write(to: out) else { throw DropError.writeFailed(out.lastPathComponent) }
        outputs.append(out)
      }
    } catch {
      for url in outputs { try? FileManager.default.removeItem(at: url) }
      throw error
    }
    return outputs
  }

  /// Writes every page, at 144 dpi, into one multi-page TIFF (LZW-compressed).
  public static func tiff(_ source: URL, destination: URL) throws {
    let doc = try PDFPageOps.open(source)
    guard doc.pageCount > 0,
      let dest = CGImageDestinationCreateWithURL(
        destination as CFURL, ImageFormat.tiff.typeIdentifier as CFString, doc.pageCount, nil)
    else { throw DropError.writeFailed(destination.lastPathComponent) }
    let props: [CFString: Any] = [
      kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5],
      kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144,
    ]
    for index in 0..<doc.pageCount {
      guard let page = doc.page(at: index), let image = PDFPageOps.render(page, scale: 2) else {
        throw DropError.readFailed(source.lastPathComponent)
      }
      CGImageDestinationAddImage(dest, image, props as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: destination)
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  /// Writes a comic-book archive: a zip of JPEG pages named so readers sort them in order.
  public static func cbz(_ source: URL, destination: URL) async throws {
    let doc = try PDFPageOps.open(source)
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fdu-cbz-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    let digits = max(String(doc.pageCount).count, 3)
    for index in 0..<doc.pageCount {
      guard let page = doc.page(at: index), let image = PDFPageOps.render(page, scale: 2) else {
        throw DropError.readFailed(source.lastPathComponent)
      }
      let number = String(repeating: "0", count: max(digits - String(index + 1).count, 0)) + String(index + 1)
      try ImageOps.write(image, as: .jpeg, quality: 0.9, to: staging.appendingPathComponent("\(number).jpg"))
    }
    do {
      try await ArchiveOps.zip([staging], contentsOnly: true, destination: destination)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }
}
