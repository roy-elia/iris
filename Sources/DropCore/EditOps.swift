import CoreGraphics
import CoreImage
import CoreText
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
    if !recipe.redactions.isEmpty || !recipe.strokes.isEmpty || !recipe.marks.isEmpty {
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

  /// Source format if ImageIO can write it, otherwise PNG.
  public static func outputFormat(for source: URL) -> ImageFormat {
    let format = ImageFormat(fileExtension: source.pathExtension) ?? .png
    return format.isImageIOWritable ? format : .png
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
      let pixelated: CGImage? =
        switch recipe.redactStyle {
        case .pixelate: try pixelate(image)
        case .blur: try blur(image)
        case .blackout: nil
        }
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
    for mark in recipe.marks {
      try MarkRenderer.draw(mark, in: ctx, source: image, width: width, height: height)
    }
    return try make(ctx)
  }

  static func blur(_ image: CGImage) throws -> CGImage {
    let input = CIImage(cgImage: image)
    let filter = CIFilter(name: "CIGaussianBlur")!
    filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
    filter.setValue(max(6, Double(max(image.width, image.height)) / 45), forKey: kCIInputRadiusKey)
    guard let output = filter.outputImage?.cropped(to: input.extent),
      let result = ciContext.createCGImage(output, from: input.extent)
    else { throw DropError.writeFailed("redact") }
    return result
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

/// Draws annotation marks into a context that's already flipped to top-left origin.
enum MarkRenderer {
  static func draw(_ mark: Mark, in ctx: CGContext, source: CGImage, width: Int, height: Int) throws {
    let w = Double(width)
    let h = Double(height)
    let short = min(w, h)
    func point(_ p: NormPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }
    func rect(_ r: NormRect) -> CGRect {
      CGRect(x: r.x * w, y: r.y * h, width: r.width * w, height: r.height * h)
    }

    ctx.saveGState()
    defer { ctx.restoreGState() }
    switch mark {
    case .arrow(let from, let to, let color, let width):
      let a = point(from)
      let b = point(to)
      let line = max(1, width * short)
      let angle = atan2(b.y - a.y, b.x - a.x)
      let head = line * 4.5
      // Stop the shaft inside the head so its end doesn't poke through the tip.
      let shaftEnd = CGPoint(x: b.x - cos(angle) * head * 0.6, y: b.y - sin(angle) * head * 0.6)
      ctx.setStrokeColor(color.cgColor)
      ctx.setLineWidth(line)
      ctx.setLineCap(.round)
      ctx.move(to: a)
      ctx.addLine(to: shaftEnd)
      ctx.strokePath()
      ctx.setFillColor(color.cgColor)
      ctx.move(to: b)
      ctx.addLine(to: CGPoint(x: b.x - cos(angle - 0.45) * head, y: b.y - sin(angle - 0.45) * head))
      ctx.addLine(to: CGPoint(x: b.x - cos(angle + 0.45) * head, y: b.y - sin(angle + 0.45) * head))
      ctx.closePath()
      ctx.fillPath()

    case .rectangle(let r, let color, let width, let filled),
      .ellipse(let r, let color, let width, let filled):
      let box = rect(r)
      let path: CGPath =
        if case .ellipse = mark {
          CGPath(ellipseIn: box, transform: nil)
        } else {
          CGPath(roundedRect: box, cornerWidth: short * 0.01, cornerHeight: short * 0.01, transform: nil)
        }
      ctx.addPath(path)
      if filled {
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
      } else {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(max(1, width * short))
        ctx.setLineJoin(.round)
        ctx.strokePath()
      }

    case .highlight(let r, let color):
      var marker = color
      marker.alpha = min(color.alpha, 0.4)
      ctx.setBlendMode(.multiply)
      ctx.setFillColor(marker.cgColor)
      ctx.fill(rect(r))

    case .text(let string, let at, let color, let size, let boxWidth):
      let fontSize = max(6, size * short)
      let font =
        CTFontCreateUIFontForLanguage(.system, fontSize, nil)
        ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
      let attributed = NSAttributedString(
        string: string,
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): font,
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ])
      let origin = point(at)
      let boxW = max(fontSize, boxWidth * w)
      let setter = CTFramesetterCreateWithAttributedString(attributed)
      let fit = CTFramesetterSuggestFrameSizeWithConstraints(
        setter, CFRange(location: 0, length: 0), nil, CGSize(width: boxW, height: .greatestFiniteMagnitude),
        nil)
      // Core Text draws bottom-up: undo the flip locally around the text box.
      ctx.translateBy(x: origin.x, y: origin.y + fit.height)
      ctx.scaleBy(x: 1, y: -1)
      let frame = CTFramesetterCreateFrame(
        setter, CFRange(location: 0, length: 0),
        CGPath(rect: CGRect(x: 0, y: 0, width: boxW, height: fit.height), transform: nil), nil)
      CTFrameDraw(frame, ctx)

    case .callout(let number, let at, let color, let radius):
      let c = point(at)
      let r = max(6, radius * short)
      ctx.setFillColor(color.cgColor)
      ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
      let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, r * 1.1, nil)!
      let label = NSAttributedString(
        string: "\(number)",
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): font,
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): contrastingText(for: color),
        ])
      let line = CTLineCreateWithAttributedString(label)
      let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
      ctx.translateBy(x: c.x, y: c.y)
      ctx.scaleBy(x: 1, y: -1)
      ctx.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
      CTLineDraw(line, ctx)

    case .magnifier(let src, let at, let radius, let zoom):
      let r = max(8, radius * short)
      let z = min(max(zoom, 1.2), 8)
      let s = point(src)
      let c = point(at)
      let bubble = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
      // Shadow under the bubble, then the enlarged area clipped to a circle.
      ctx.saveGState()
      ctx.setShadow(offset: .zero, blur: r * 0.25, color: CGColor(gray: 0, alpha: 0.45))
      ctx.setFillColor(CGColor(gray: 1, alpha: 1))
      ctx.fillEllipse(in: bubble.insetBy(dx: -r * 0.04, dy: -r * 0.04))
      ctx.restoreGState()
      ctx.addEllipse(in: bubble)
      ctx.clip()
      // Map the source region (radius r/z around s) onto the bubble. The context is
      // flipped, so draw the image through a local un-flip.
      let scaleFactor = z
      ctx.translateBy(x: c.x, y: c.y)
      ctx.scaleBy(x: scaleFactor, y: scaleFactor)
      ctx.translateBy(x: -s.x, y: -s.y)
      ctx.translateBy(x: 0, y: h)
      ctx.scaleBy(x: 1, y: -1)
      ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))

    case .sticker(let path, let r):
      let sticker = try ImageOps.loadOriented(ImageInput.readableURL(for: URL(fileURLWithPath: path)))
      let box = FrameOps.aspectFit(CGSize(width: sticker.width, height: sticker.height), in: rect(r))
      ctx.translateBy(x: 0, y: box.minY + box.maxY)
      ctx.scaleBy(x: 1, y: -1)
      ctx.draw(sticker, in: box)
    }
  }

  /// White on dark colours, black on light ones.
  static func contrastingText(for color: RGBA) -> CGColor {
    let luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
    return luminance > 0.6 ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1)
  }
}
