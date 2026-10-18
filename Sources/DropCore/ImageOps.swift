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
      options[kCGImageDestinationLossyCompressionQuality] = Settings.clampQuality(quality)
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
  public static func stripMetadata(_ source: URL, destination: URL) throws {
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
      let image = CGImageSourceCreateThumbnailAtIndex(
        imageSource, 0, thumbOptions as CFDictionary)
    else { throw DropError.readFailed(source.lastPathComponent) }

    guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, type, 1, nil) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
    CGImageDestinationAddImage(dest, image, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: destination)
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  private static func maxPixelSize(_ source: CGImageSource) -> Int {
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
    return max(width, height, 1)
  }
}
