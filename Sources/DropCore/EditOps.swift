import CoreGraphics
import CoreImage
import Foundation

/// Applies an `EditRecipe` to an image.
public enum EditOps {
  private static let ciContext = CIContext(options: [.cacheIntermediates: false])

  /// Renders `recipe` onto the image at `source` and returns the result.
  public static func render(_ source: URL, recipe: EditRecipe) throws -> CGImage {
    var image = try ImageOps.loadOriented(source)
    image = try rotate(image, quarterTurns: recipe.normalizedTurns)
    if recipe.hasColorAdjustments {
      image = try adjust(image, recipe: recipe)
    }
    if !recipe.redactions.isEmpty || !recipe.strokes.isEmpty {
      image = try draw(on: image, recipe: recipe)
    }
    if let crop = recipe.crop, crop != .full, !crop.isEmpty {
      let rect = crop.pixels(width: image.width, height: image.height)
      guard let cropped = image.cropping(to: rect) else { throw DropError.writeFailed("crop") }
      image = cropped
    }
    return image
  }

  /// Renders and writes the edited image, keeping the source format when it is writable.
  public static func apply(_ source: URL, recipe: EditRecipe, destination: URL, quality: Double = 0.95)
    throws
  {
    let image = try render(source, recipe: recipe)
    try ImageOps.write(image, as: outputFormat(for: source), quality: quality, to: destination)
  }

  /// Source format if macOS can write it, otherwise PNG.
  public static func outputFormat(for source: URL) -> ImageFormat {
    let format = ImageFormat(fileExtension: source.pathExtension) ?? .png
    return format.isWritable ? format : .png
  }

  // MARK: Steps

  static func rotate(_ image: CGImage, quarterTurns: Int) throws -> CGImage {
    guard quarterTurns != 0 else { return image }
    let swap = quarterTurns % 2 == 1
    let width = swap ? image.height : image.width
    let height = swap ? image.width : image.height
    let ctx = try context(width: width, height: height, like: image)
    // Core Graphics is bottom-left origin; positive angles turn counter-clockwise.
    ctx.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    ctx.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
    ctx.draw(
      image,
      in: CGRect(
        x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
        width: CGFloat(image.width), height: CGFloat(image.height)))
    return try make(ctx)
  }

  static func adjust(_ image: CGImage, recipe: EditRecipe) throws -> CGImage {
    let input = CIImage(cgImage: image)
    let filter = CIFilter(name: "CIColorControls")!
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(clamp(recipe.brightness, EditRecipe.brightnessRange), forKey: kCIInputBrightnessKey)
    filter.setValue(clamp(recipe.contrast, EditRecipe.contrastRange), forKey: kCIInputContrastKey)
    filter.setValue(clamp(recipe.saturation, EditRecipe.saturationRange), forKey: kCIInputSaturationKey)
    guard let output = filter.outputImage,
      let result = ciContext.createCGImage(output, from: input.extent)
    else { throw DropError.writeFailed("adjust") }
    return result
  }

  static func draw(on image: CGImage, recipe: EditRecipe) throws -> CGImage {
    let width = image.width
    let height = image.height
    let ctx = try context(width: width, height: height, like: image)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Flip so normalised top-left coordinates map directly.
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)

    if !recipe.redactions.isEmpty {
      let pixelated = recipe.redactStyle == .pixelate ? try pixelate(image) : nil
      for region in recipe.redactions where !region.isEmpty {
        let rect = region.pixels(width: width, height: height)
        if let pixelated {
          ctx.saveGState()
          ctx.clip(to: rect)
          // Undo the flip for drawing the image itself.
          ctx.translateBy(x: 0, y: CGFloat(height))
          ctx.scaleBy(x: 1, y: -1)
          ctx.draw(pixelated, in: CGRect(x: 0, y: 0, width: width, height: height))
          ctx.restoreGState()
        } else {
          ctx.setFillColor(RGBA.black.cgColor)
          ctx.fill(rect)
        }
      }
    }

    let shortSide = Double(min(width, height))
    for stroke in recipe.strokes where !stroke.points.isEmpty {
      ctx.setStrokeColor(stroke.color.cgColor)
      ctx.setLineWidth(max(1, stroke.width * shortSide))
      ctx.setLineCap(.round)
      ctx.setLineJoin(.round)
      let points = stroke.points.map { CGPoint(x: $0.x * Double(width), y: $0.y * Double(height)) }
      ctx.beginPath()
      ctx.move(to: points[0])
      if points.count == 1 {
        ctx.addLine(to: points[0])
      } else {
        for point in points.dropFirst() { ctx.addLine(to: point) }
      }
      ctx.strokePath()
    }
    return try make(ctx)
  }

  static func pixelate(_ image: CGImage) throws -> CGImage {
    let input = CIImage(cgImage: image)
    let filter = CIFilter(name: "CIPixellate")!
    filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
    filter.setValue(max(8, Double(max(image.width, image.height)) / 40), forKey: kCIInputScaleKey)
    filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
    guard let output = filter.outputImage?.cropped(to: input.extent),
      let result = ciContext.createCGImage(output, from: input.extent)
    else { throw DropError.writeFailed("redact") }
    return result
  }

  // MARK: Helpers

  static func context(width: Int, height: Int, like image: CGImage) throws -> CGContext {
    guard
      let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw DropError.writeFailed("image") }
    ctx.interpolationQuality = .high
    return ctx
  }

  static func make(_ ctx: CGContext) throws -> CGImage {
    guard let image = ctx.makeImage() else { throw DropError.writeFailed("image") }
    return image
  }

  private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
  }
}
