import CoreGraphics
import Foundation
import ImageIO

/// Generates test images and PDFs on the fly, so no binary fixtures live in the repo.
enum Fixtures {
  /// A solid-colour image of the given size.
  static func image(width: Int = 40, height: Int = 20) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  /// Writes an image file. With `withMetadata`, adds EXIF, GPS and TIFF fields.
  @discardableResult
  static func writeImage(
    to url: URL, type: String = "public.jpeg", width: Int = 40, height: Int = 20,
    withMetadata: Bool = false
  ) throws -> URL {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
    var props: [CFString: Any] = [:]
    if withMetadata {
      props[kCGImagePropertyExifDictionary] = [
        kCGImagePropertyExifUserComment: "secret comment",
        kCGImagePropertyExifDateTimeOriginal: "2024:01:02 03:04:05",
      ]
      props[kCGImagePropertyGPSDictionary] = [
        kCGImagePropertyGPSLatitude: 45.5,
        kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 73.6,
        kCGImagePropertyGPSLongitudeRef: "W",
      ]
      props[kCGImagePropertyTIFFDictionary] = [
        kCGImagePropertyTIFFMake: "TestCam",
        kCGImagePropertyTIFFArtist: "Someone",
      ]
    }
    CGImageDestinationAddImage(dest, image(width: width, height: height), props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    return url
  }

  /// Writes a PDF with `pages` blank pages.
  @discardableResult
  static func writePDF(to url: URL, pages: Int) throws -> URL {
    var box = CGRect(x: 0, y: 0, width: 200, height: 100)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    for _ in 0..<pages {
      context.beginPDFPage(nil)
      context.endPDFPage()
    }
    context.closePDF()
    return url
  }

  static func properties(of url: URL) -> [CFString: Any] {
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
  }

  static func typeIdentifier(of url: URL) -> String? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceGetType(source) as String?
  }
}
