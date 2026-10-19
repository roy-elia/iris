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

  /// Deterministic noise, which compresses poorly losslessly and well lossily.
  static func noisyImage(width: Int, height: Int) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    var seed: UInt32 = 12345
    for i in stride(from: 0, to: bytes.count, by: 4) {
      for c in 0..<3 {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        bytes[i + c] = UInt8(truncatingIfNeeded: seed >> 24)
      }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }

  @discardableResult
  static func writeCGImage(_ image: CGImage, to url: URL, type: String = "public.png") throws -> URL {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    return url
  }

  /// RGBA (0...255) of the pixel at a top-left-origin position.
  static func pixel(_ image: CGImage, x: Int, y: Int) -> [Int] {
    var buffer = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(
      data: &buffer, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Shift the image so the wanted pixel lands on the 1×1 canvas (CG is bottom-left origin).
    ctx.draw(
      image,
      in: CGRect(
        x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return buffer.map(Int.init)
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

  /// A tiny uncompressed Radiance HDR (RGBE) image, which ImageIO reads but can't write.
  @discardableResult
  static func writeHDR(to url: URL, width: Int = 4, height: Int = 4) throws -> URL {
    var data = Data("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y \(height) +X \(width)\n".utf8)
    // Widths under 8 are stored flat: one R, G, B, shared-exponent quad per pixel.
    for _ in 0..<(width * height) { data.append(contentsOf: [200, 100, 50, 128]) }
    try data.write(to: url)
    return url
  }
}
