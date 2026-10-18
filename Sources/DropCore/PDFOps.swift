import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// PDF building with PDFKit and Core Graphics.
public enum PDFOps {
  /// Appends the pages of each PDF in order and writes one document.
  public static func merge(_ sources: [URL], destination: URL) throws {
    let output = PDFDocument()
    for source in sources {
      guard let doc = PDFDocument(url: source) else {
        throw DropError.readFailed(source.lastPathComponent)
      }
      if doc.isLocked {
        throw DropError.wrongInput("\(source.lastPathComponent) is password-protected.")
      }
      for index in 0..<doc.pageCount {
        guard let page = doc.page(at: index) else { continue }
        output.insert(page, at: output.pageCount)
      }
    }
    guard output.pageCount > 0, output.write(to: destination) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  /// Writes one page per image, each page sized to its image at 72 dpi.
  public static func imagesToPDF(_ sources: [URL], destination: URL) throws {
    var mediaBox = CGRect.zero
    guard let context = CGContext(destination as CFURL, mediaBox: &mediaBox, nil) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
    var completed = false
    defer {
      if !completed { try? FileManager.default.removeItem(at: destination) }
    }

    for source in sources {
      let image = try orientedImage(source)
      var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
      let pageInfo = [kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)]
      context.beginPDFPage(pageInfo as CFDictionary)
      context.draw(image, in: box)
      context.endPDFPage()
    }
    context.closePDF()
    completed = true
  }

  public static func pageCount(of url: URL) -> Int? {
    PDFDocument(url: url)?.pageCount
  }

  private static func orientedImage(_ source: URL) throws -> CGImage {
    guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
    else { throw DropError.readFailed(source.lastPathComponent) }
    let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    else { throw DropError.readFailed(source.lastPathComponent) }
    return image
  }
}
