import CoreGraphics
import Foundation
import ImageIO

/// How Resize picks the new size.
public enum ResizeSpec: Codable, Equatable, Hashable, Sendable {
  /// Scale so the longest side is this many pixels.
  case maxEdge(Int)
  /// Scale both sides by this percentage.
  case percent(Double)

  public static let percentRange: ClosedRange<Double> = 1...400
  public static let edgeRange: ClosedRange<Int> = 1...16384

  /// The new pixel size for an image of `width` × `height`, at least 1 × 1.
  public func size(width: Int, height: Int) -> (width: Int, height: Int) {
    let scale: Double
    switch self {
    case .maxEdge(let edge):
      let clamped = min(max(edge, Self.edgeRange.lowerBound), Self.edgeRange.upperBound)
      scale = Double(clamped) / Double(max(width, height, 1))
    case .percent(let p):
      scale = min(max(p.isFinite ? p : 100, Self.percentRange.lowerBound), Self.percentRange.upperBound) / 100
    }
    return (max(Int((Double(width) * scale).rounded()), 1), max(Int((Double(height) * scale).rounded()), 1))
  }

  public var summary: String {
    switch self {
    case .maxEdge(let edge): "\(edge) px"
    case .percent(let p): "\(p.formatted(.number.precision(.fractionLength(0...1))))%"
    }
  }
}

/// Resize, grayscale and icon output.
public enum ImageToolOps {
  /// Pixel sizes written into an ICO file (Windows reads up to 256; ImageIO writes at most six).
  static let icoSizes = [16, 32, 48, 64, 128, 256]
  /// Pixel sizes written into an ICNS file; 1024 is stored as the 512 @2x icon.
  static let icnsSizes = [16, 32, 64, 128, 256, 512, 1024]

  /// Scales the oriented image to `spec` and writes it in the source format (PNG when the
  /// source can't be written).
  public static func resize(_ source: URL, spec: ResizeSpec, destination: URL, quality: Double = 0.92) throws
  {
    let image = try ImageOps.loadOriented(source)
    let size = spec.size(width: image.width, height: image.height)
    try ImageOps.write(
      scaled(image, width: size.width, height: size.height), as: EditOps.outputFormat(for: source),
      quality: quality, to: destination)
  }

  /// Writes a black-and-white copy (luminance only, transparency kept).
  public static func grayscale(_ source: URL, destination: URL, quality: Double = 0.92) throws {
    try EditOps.apply(source, recipe: EditRecipe(saturation: 0), destination: destination, quality: quality)
  }

  /// Draws `image` at a new size with high-quality interpolation.
  static func scaled(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
    if image.width == width && image.height == height { return image }
    let ctx = try canvas(width: width, height: height)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let out = ctx.makeImage() else { throw DropError.writeFailed("resize") }
    return out
  }

  /// The image centred on a transparent square of `side` pixels, keeping its proportions.
  static func squared(_ image: CGImage, side: Int) throws -> CGImage {
    let ctx = try canvas(width: side, height: side)
    ctx.interpolationQuality = .high
    let scale = Double(side) / Double(max(image.width, image.height))
    let w = Double(image.width) * scale
    let h = Double(image.height) * scale
    ctx.draw(image, in: CGRect(x: (Double(side) - w) / 2, y: (Double(side) - h) / 2, width: w, height: h))
    guard let out = ctx.makeImage() else { throw DropError.writeFailed("icon") }
    return out
  }

  /// Writes an ICO or ICNS holding the image at each standard size up to its own size
  /// (always at least the smallest two, so tiny images still make a usable icon).
  public static func writeIcon(_ source: URL, as format: ImageFormat, to destination: URL) throws {
    guard format.isIcon else { throw DropError.wrongInput("\(format.displayName) isn't an icon format.") }
    let image = try ImageOps.loadOriented(source)
    let all = format == .ico ? icoSizes : icnsSizes
    let longest = max(image.width, image.height)
    let sizes = all.enumerated().filter { $0.offset < 2 || $0.element <= max(longest, all[1]) }.map(\.element)
    guard
      let dest = CGImageDestinationCreateWithURL(
        destination as CFURL, format.typeIdentifier as CFString, sizes.count, nil)
    else { throw DropError.writeFailed(destination.lastPathComponent) }
    for side in sizes {
      // ICNS stores 1024 as a Retina 512, which ImageIO only accepts at 144 dpi.
      let props: [CFString: Any] =
        side == 1024 ? [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144] : [:]
      CGImageDestinationAddImage(dest, try squared(image, side: side), props as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: destination)
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  private static func canvas(width: Int, height: Int) throws -> CGContext {
    guard
      let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { throw DropError.writeFailed("image") }
    return ctx
  }
}
