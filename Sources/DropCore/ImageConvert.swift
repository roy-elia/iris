import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Makes any supported image readable by ImageIO. SVG is rasterised to a temporary PNG
/// first; everything else is used as it is.
public enum ImageInput {
  /// The longest side, in pixels, an SVG is rendered at when it has no larger natural size.
  static let svgMinimumPixels: CGFloat = 2048
  static let svgMaximumPixels: CGFloat = 8192

  /// A URL ImageIO can read for `url`. Callers delete nothing: temporary files live in
  /// the system temp folder, which macOS cleans up.
  public static func readableURL(for url: URL) throws -> URL {
    guard ImageFormat(fileExtension: url.pathExtension) == .svg else { return url }
    let image = try rasterizeSVG(url)
    let out = FileManager.default.temporaryDirectory
      .appendingPathComponent("fdu-svg-\(UUID().uuidString)")
      .appendingPathExtension("png")
    try ImageOps.write(image, as: .png, quality: 1, to: out)
    return out
  }

  /// Renders an SVG at a size that keeps it sharp: its natural size scaled up to at least
  /// `svgMinimumPixels` on the longest side.
  public static func rasterizeSVG(_ url: URL) throws -> CGImage {
    guard let svg = NSImage(contentsOf: url), svg.size.width > 0, svg.size.height > 0 else {
      throw DropError.readFailed(url.lastPathComponent)
    }
    let longest = max(svg.size.width, svg.size.height)
    let scale = min(max(svgMinimumPixels / longest, 1), svgMaximumPixels / longest)
    let width = Int((svg.size.width * scale).rounded())
    let height = Int((svg.size.height * scale).rounded())
    guard
      let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { throw DropError.readFailed(url.lastPathComponent) }
    let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    svg.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    guard let image = ctx.makeImage() else { throw DropError.readFailed(url.lastPathComponent) }
    return image
  }
}

/// Converts between image formats, including WebP (bundled `cwebp`) and animated GIF.
public enum ImageConvert {
  /// Converts `source` to `format` at `destination`.
  /// - Animated sources keep every frame when the output is GIF.
  /// - `options.preserveMetadata` keeps EXIF, GPS, IPTC and XMP where the format allows.
  public static func convert(
    _ source: URL, to format: ImageFormat, quality: Double, options: FormatSettings = FormatSettings(),
    destination: URL
  ) async throws {
    guard format.isWritable else {
      throw DropError.wrongInput("\(format.displayName) can't be written on this Mac.")
    }
    let readable = try ImageInput.readableURL(for: source)
    switch format {
    case .webp:
      try await writeWebP(
        from: readable, quality: quality, keepMetadata: options.preserveMetadata, to: destination)
    case .gif where frameCount(readable) > 1:
      try writeAnimatedGIF(from: readable, to: destination)
    default:
      try writeWithImageIO(
        readable, as: format, quality: quality, keepMetadata: options.preserveMetadata, to: destination)
    }
  }

  /// Number of frames (1 for still images).
  public static func frameCount(_ url: URL) -> Int {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
    return CGImageSourceGetCount(src)
  }

  // MARK: ImageIO

  static func writeWithImageIO(
    _ source: URL, as format: ImageFormat, quality: Double, keepMetadata: Bool, to destination: URL
  ) throws {
    guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
      throw DropError.readFailed(source.lastPathComponent)
    }
    guard
      let dest = CGImageDestinationCreateWithURL(
        destination as CFURL, format.typeIdentifier as CFString, 1, nil)
    else { throw DropError.writeFailed(destination.lastPathComponent) }
    var options: [CFString: Any] = [:]
    if format.usesQuality {
      options[kCGImageDestinationLossyCompressionQuality] = AppSettings.clampQuality(quality)
    }
    if keepMetadata {
      // Copies the source's metadata (orientation included) with the new encoding.
      CGImageDestinationAddImageFromSource(dest, src, 0, options as CFDictionary)
    } else {
      let image = try ImageOps.loadOriented(source)
      CGImageDestinationAddImage(dest, image, options as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: destination)
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  /// Copies every frame and its timing into a looping GIF.
  static func writeAnimatedGIF(from source: URL, to destination: URL) throws {
    guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else {
      throw DropError.readFailed(source.lastPathComponent)
    }
    let count = CGImageSourceGetCount(src)
    guard
      let dest = CGImageDestinationCreateWithURL(
        destination as CFURL, ImageFormat.gif.typeIdentifier as CFString, count, nil)
    else { throw DropError.writeFailed(destination.lastPathComponent) }
    let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
    CGImageDestinationSetProperties(dest, fileProps as CFDictionary)
    for index in 0..<count {
      guard let frame = CGImageSourceCreateImageAtIndex(src, index, nil) else { continue }
      let delay = frameDelay(src, index: index)
      let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]]
      CGImageDestinationAddImage(dest, frame, props as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: destination)
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  /// A frame's display time in seconds, from whichever animation dictionary it has.
  static func frameDelay(_ src: CGImageSource, index: Int) -> Double {
    let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any] ?? [:]
    let dictionaries: [(CFString, CFString, CFString)] = [
      (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
      (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
      (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
      (
        kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime,
        kCGImagePropertyHEICSDelayTime
      ),
    ]
    for (dict, unclamped, clamped) in dictionaries {
      guard let d = props[dict] as? [CFString: Any] else { continue }
      if let v = d[unclamped] as? Double, v > 0 { return v }
      if let v = d[clamped] as? Double, v > 0 { return v }
    }
    return 0.1
  }

  // MARK: WebP

  /// Encodes with the bundled `cwebp`. Orientation is baked into the pixels first, since
  /// cwebp ignores the EXIF orientation tag.
  static func writeWebP(from source: URL, quality: Double, keepMetadata: Bool, to destination: URL)
    async throws
  {
    let staged = try stagePNG(source)
    defer { try? FileManager.default.removeItem(at: staged) }
    var args = ["-quiet"]
    if quality >= 0.999 {
      args += ["-lossless", "-exact"]
    } else {
      args += ["-q", String(Int((AppSettings.clampQuality(quality) * 100).rounded()))]
    }
    try await runCwebp(args, input: staged, output: destination)
    // cwebp drops metadata from our staged PNG; copy it back from the original.
    if keepMetadata { try? await MetadataOps.copyAll(from: source, to: destination) }
  }

  /// Writes the oriented image as a lossless PNG in the temp folder.
  static func stagePNG(_ source: URL) throws -> URL {
    let image = try ImageOps.loadOriented(source)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("fdu-stage-\(UUID().uuidString)").appendingPathExtension("png")
    try ImageOps.write(image, as: .png, quality: 1, to: url)
    return url
  }

  static func runCwebp(_ args: [String], input: URL, output: URL) async throws {
    do {
      _ = try await ToolRunner.run(.cwebp, args + [input.path, "-o", output.path])
    } catch {
      try? FileManager.default.removeItem(at: output)
      throw error
    }
    guard FileManager.default.fileExists(atPath: output.path) else {
      throw DropError.writeFailed(output.lastPathComponent)
    }
  }
}
