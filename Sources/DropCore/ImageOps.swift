import CoreGraphics
import Foundation
import ImageIO

/// Image conversion and metadata handling with ImageIO.
public enum ImageOps {
  /// Re-encodes `source` as `format` and writes it to `destination`. `quality` applies to
  /// JPEG and HEIC only. Orientation is kept so images do not appear rotated afterwards.
  public static func convert(
    _ source: URL, to format: ImageFormat, quality: Double, destination: URL
  ) throws {
    guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      CGImageSourceGetCount(imageSource) > 0,
      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else { throw DropError.readFailed(source.lastPathComponent) }

    guard format.isImageIOWritable else {
      throw DropError.wrongInput("macOS can't write \(format.displayName) files.")
    }
    guard
      let dest = CGImageDestinationCreateWithURL(
        destination as CFURL, format.typeIdentifier as CFString, 1, nil)
    else { throw DropError.writeFailed(destination.lastPathComponent) }

    var options: [CFString: Any] = [:]
    let sourceProps = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
    if let orientation = sourceProps?[kCGImagePropertyOrientation] {
      options[kCGImagePropertyOrientation] = orientation
    }
    if format.usesQuality {
      options[kCGImageDestinationLossyCompressionQuality] = format.encoderQuality(quality)
    }
    CGImageDestinationAddImage(dest, image, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: destination)
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  /// A readable summary of an image's metadata, grouped as "Group: Key" → value.
  public static func metadata(of source: URL) throws -> [String: String] {
    guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any]
    else { throw DropError.readFailed(source.lastPathComponent) }

    var result: [String: String] = [:]
    for (key, value) in props {
      if let group = value as? [String: Any] {
        let groupName = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        for (subKey, subValue) in group {
          result["\(groupName): \(subKey)"] = String(describing: subValue)
        }
      } else {
        result[key] = String(describing: value)
      }
    }
    return result
  }

  /// True if the image carries GPS coordinates.
  public static func hasLocation(_ source: URL) throws -> Bool {
    try metadata(of: source).keys.contains { $0.hasPrefix("GPS:") }
  }

  /// Writes a copy of `source` without EXIF, GPS, IPTC or XMP metadata. Pixel data is
  /// re-encoded at maximum quality; orientation is applied so the result looks the same.
  /// With `complete`, the colour profile goes too: pixels are converted to sRGB first, so
  /// the untagged copy still looks right.
  public static func stripMetadata(_ source: URL, destination: URL, complete: Bool = false) throws {
    guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let type = CGImageSourceGetType(imageSource),
      CGImageSourceGetCount(imageSource) > 0
    else { throw DropError.readFailed(source.lastPathComponent) }

    // Bake orientation into the pixels so no orientation tag is needed afterwards.
    let thumbOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize(imageSource),
    ]
    guard
      var image = CGImageSourceCreateThumbnailAtIndex(
        imageSource, 0, thumbOptions as CFDictionary)
    else { throw DropError.readFailed(source.lastPathComponent) }
    if complete {
      guard let untagged = untaggedSRGB(image) else { throw DropError.readFailed(source.lastPathComponent) }
      image = untagged
    }

    // Formats macOS can only read (WebP) are written as PNG instead.
    let outType = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    let writeType: CFString =
      outType.contains(type as String) ? type : ImageFormat.png.typeIdentifier as CFString
    guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, writeType, 1, nil) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
    let format = ImageFormat.allCases.first { $0.typeIdentifier == writeType as String }
    let options: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: format?.encoderQuality(1) ?? 1
    ]
    CGImageDestinationAddImage(dest, image, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: destination)
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  /// `image` converted to 8-bit sRGB, then relabelled as device RGB so encoders write no
  /// ICC profile for it.
  static func untaggedSRGB(_ image: CGImage) -> CGImage? {
    guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()?.copy(colorSpace: CGColorSpaceCreateDeviceRGB())
  }

  /// Loads the first image with its orientation applied to the pixels.
  public static func loadOriented(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(source) > 0
    else { throw DropError.readFailed(url.lastPathComponent) }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize(source),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw DropError.readFailed(url.lastPathComponent)
    }
    return image
  }

  /// Encodes `image` as `format`. Throws for formats macOS cannot write.
  public static func write(_ image: CGImage, as format: ImageFormat, quality: Double, to url: URL) throws {
    guard format.isImageIOWritable else { throw DropError.writeFailed(url.lastPathComponent) }
    var options: [CFString: Any] = [:]
    if format.usesQuality {
      options[kCGImageDestinationLossyCompressionQuality] = format.encoderQuality(quality)
    }
    func encode(_ image: CGImage) -> Bool {
      guard
        let dest = CGImageDestinationCreateWithURL(url as CFURL, format.typeIdentifier as CFString, 1, nil)
      else { return false }
      CGImageDestinationAddImage(dest, image, options as CFDictionary)
      return CGImageDestinationFinalize(dest)
    }
    // Some encoders (TGA, JPEG 2000, OpenEXR) refuse pixel layouts other decoders produce,
    // such as float HDR pixels or cropped buffers; those are retried as plain 8-bit sRGB.
    guard encode(image) || eightBitSRGB(image).map(encode) == true else {
      try? FileManager.default.removeItem(at: url)
      throw DropError.writeFailed(url.lastPathComponent)
    }
  }

  /// `image` redrawn as 8-bit sRGB (RGBA, or RGB when it has no alpha).
  static func eightBitSRGB(_ image: CGImage) -> CGImage? {
    let alpha = hasAlpha(image)
    guard
      let ctx = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)
    else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()
  }

  /// Whether the image has an alpha channel that is actually used.
  public static func hasAlpha(_ image: CGImage) -> Bool {
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast: false
    default: true
    }
  }

  private static func maxPixelSize(_ source: CGImageSource) -> Int {
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
    return max(width, height, 1)
  }
}
