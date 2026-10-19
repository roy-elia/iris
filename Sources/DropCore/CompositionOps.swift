import CoreGraphics
import Foundation
import ImageIO
import Vision

// MARK: Frame

/// What's behind a framed image.
public enum FrameBackground: Codable, Equatable, Hashable, Sendable {
  case transparent
  case solid(RGBA)
  /// Top-leading to bottom-trailing.
  case linear(RGBA, RGBA)
  /// From the centre out.
  case radial(RGBA, RGBA)
  case image(path: String)
}

/// The frame's canvas shape. `auto` follows the image plus padding.
public enum FrameRatio: String, Codable, CaseIterable, Sendable {
  case auto, square, landscape4x3, landscape16x9, portrait4x5, portrait9x16

  public var displayName: String {
    switch self {
    case .auto: "Auto"
    case .square: "1:1"
    case .landscape4x3: "4:3"
    case .landscape16x9: "16:9"
    case .portrait4x5: "4:5"
    case .portrait9x16: "9:16"
    }
  }

  /// Width over height, or nil for `auto`.
  public var value: Double? {
    switch self {
    case .auto: nil
    case .square: 1
    case .landscape4x3: 4.0 / 3
    case .landscape16x9: 16.0 / 9
    case .portrait4x5: 4.0 / 5
    case .portrait9x16: 9.0 / 16
    }
  }
}

/// Puts an image on a padded background with rounded corners and a soft shadow, the way
/// screenshots are presented.
public struct FrameRecipe: Codable, Equatable, Hashable, Sendable {
  /// Padding around the image as a fraction of its longer side.
  public var padding: Double
  /// Corner radius as a fraction of the image's shorter side.
  public var cornerRadius: Double
  public var shadow: Bool
  public var background: FrameBackground
  public var ratio: FrameRatio

  public init(
    padding: Double = 0.08, cornerRadius: Double = 0.03, shadow: Bool = true,
    background: FrameBackground = FramePreset.all[0].background, ratio: FrameRatio = .auto
  ) {
    self.padding = min(max(padding, 0), 0.5)
    self.cornerRadius = min(max(cornerRadius, 0), 0.5)
    self.shadow = shadow
    self.background = background
    self.ratio = ratio
  }
}

/// Named backgrounds offered by the frame tool.
public struct FramePreset: Sendable, Identifiable {
  public let name: String
  public let background: FrameBackground
  public var id: String { name }

  public static let all: [FramePreset] = [
    .init(
      name: "Lagoon",
      background: .linear(RGBA(red: 0.0, green: 0.55, blue: 0.62), RGBA(red: 0.10, green: 0.25, blue: 0.62))),
    .init(
      name: "Dusk",
      background: .linear(RGBA(red: 0.98, green: 0.55, blue: 0.40), RGBA(red: 0.55, green: 0.25, blue: 0.70))),
    .init(
      name: "Meadow",
      background: .linear(RGBA(red: 0.55, green: 0.85, blue: 0.55), RGBA(red: 0.10, green: 0.55, blue: 0.45))),
    .init(
      name: "Glow",
      background: .radial(RGBA(red: 0.95, green: 0.90, blue: 1.0), RGBA(red: 0.45, green: 0.40, blue: 0.85))),
    .init(
      name: "Graphite",
      background: .linear(RGBA(red: 0.30, green: 0.31, blue: 0.34), RGBA(red: 0.10, green: 0.10, blue: 0.12))),
    .init(name: "Paper", background: .solid(RGBA(red: 0.96, green: 0.96, blue: 0.95))),
    .init(name: "Ink", background: .solid(RGBA(red: 0.07, green: 0.07, blue: 0.08))),
    .init(name: "None", background: .transparent),
  ]
}

public enum FrameOps {
  public static func render(_ image: CGImage, recipe: FrameRecipe) throws -> CGImage {
    let w = Double(image.width)
    let h = Double(image.height)
    let pad = max(w, h) * recipe.padding
    var canvasW = w + pad * 2
    var canvasH = h + pad * 2
    if let ratio = recipe.ratio.value {
      if canvasW / canvasH < ratio { canvasW = canvasH * ratio } else { canvasH = canvasW / ratio }
    }
    let ctx = try EditOps.context(width: Int(canvasW.rounded()), height: Int(canvasH.rounded()), like: image)
    let canvas = CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height)
    try fill(ctx, rect: canvas, with: recipe.background)

    let imageRect = CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)
    let radius = min(w, h) * recipe.cornerRadius
    let path = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if recipe.shadow {
      ctx.saveGState()
      let blur = max(w, h) * 0.035
      ctx.setShadow(
        offset: CGSize(width: 0, height: -blur * 0.35), blur: blur, color: CGColor(gray: 0, alpha: 0.38))
      ctx.addPath(path)
      ctx.setFillColor(CGColor(gray: 0, alpha: 1))
      ctx.fillPath()
      ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(image, in: imageRect)
    ctx.restoreGState()
    return try EditOps.make(ctx)
  }

  /// Paints a background into `rect` of a bottom-left-origin context.
  static func fill(_ ctx: CGContext, rect: CGRect, with background: FrameBackground) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    switch background {
    case .transparent:
      ctx.clear(rect)
    case .solid(let c):
      ctx.setFillColor(c.cgColor)
      ctx.fill(rect)
    case .linear(let a, let b):
      let gradient = CGGradient(
        colorsSpace: space, colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1])!
      ctx.drawLinearGradient(
        gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY),
        options: [])
    case .radial(let inner, let outer):
      let gradient = CGGradient(
        colorsSpace: space, colors: [inner.cgColor, outer.cgColor] as CFArray, locations: [0, 1])!
      let center = CGPoint(x: rect.midX, y: rect.midY)
      ctx.setFillColor(outer.cgColor)
      ctx.fill(rect)
      ctx.drawRadialGradient(
        gradient, startCenter: center, startRadius: 0, endCenter: center,
        endRadius: hypot(rect.width, rect.height) / 2, options: [.drawsAfterEndLocation])
    case .image(let path):
      let photo = try ImageOps.loadOriented(URL(fileURLWithPath: path))
      ctx.draw(photo, in: aspectFill(CGSize(width: photo.width, height: photo.height), in: rect))
    }
  }

  /// The rectangle that covers `rect` with content of `size`, centred and cropped.
  static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
    let scale = max(rect.width / size.width, rect.height / size.height)
    let w = size.width * scale
    let h = size.height * scale
    return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
  }

  /// The rectangle that fits content of `size` inside `rect`, centred.
  static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
    let scale = min(rect.width / size.width, rect.height / size.height)
    let w = size.width * scale
    let h = size.height * scale
    return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
  }
}

// MARK: Collage

public enum CollageFill: String, Codable, CaseIterable, Sendable {
  /// Fill each cell, cropping edges.
  case fill
  /// Fit whole images inside their cells.
  case fit
}

/// Arranges several images in a grid.
public struct CollageRecipe: Codable, Equatable, Hashable, Sendable {
  /// Columns, or nil to pick a near-square grid.
  public var columns: Int?
  /// Gap between cells and around the edge, as a fraction of the output width.
  public var spacing: Double
  /// Cell corner radius as a fraction of the cell's shorter side.
  public var cornerRadius: Double
  public var background: RGBA
  public var fill: CollageFill
  /// Output width in pixels.
  public var width: Int
  /// Order the files by name, as Finder lists them, instead of drop order.
  public var orderByName: Bool

  public init(
    columns: Int? = nil, spacing: Double = 0.015, cornerRadius: Double = 0.04, background: RGBA = .white,
    fill: CollageFill = .fill, width: Int = 2400, orderByName: Bool = true
  ) {
    self.columns = columns.map { max(1, $0) }
    self.spacing = min(max(spacing, 0), 0.2)
    self.cornerRadius = min(max(cornerRadius, 0), 0.5)
    self.background = background
    self.fill = fill
    self.width = min(max(width, 200), 12000)
    self.orderByName = orderByName
  }

  /// Columns for `count` images.
  public func columnCount(for count: Int) -> Int {
    min(max(columns ?? Int(Double(count).squareRoot().rounded(.up)), 1), max(count, 1))
  }
}

public enum CollageOps {
  public static func render(_ urls: [URL], recipe: CollageRecipe) throws -> CGImage {
    guard urls.count >= 2 else { throw DropError.wrongInput("A collage needs at least two images.") }
    let ordered =
      recipe.orderByName
      ? urls.sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
      : urls
    let images = try ordered.map { try ImageOps.loadOriented(ImageInput.readableURL(for: $0)) }
    let columns = recipe.columnCount(for: images.count)
    let rows = Int((Double(images.count) / Double(columns)).rounded(.up))
    // Cells take the median aspect ratio, so typical photos fill them with little cropping.
    let aspects = images.map { Double($0.width) / Double(max($0.height, 1)) }.sorted()
    let cellAspect = aspects[aspects.count / 2]
    let width = Double(recipe.width)
    let gap = width * recipe.spacing
    let cellW = (width - gap * Double(columns + 1)) / Double(columns)
    let cellH = cellW / cellAspect
    let height = cellH * Double(rows) + gap * Double(rows + 1)

    let ctx = try EditOps.context(width: Int(width.rounded()), height: Int(height.rounded()), like: images[0])
    ctx.setFillColor(recipe.background.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
    for (index, image) in images.enumerated() {
      let row = index / columns
      let column = index % columns
      // The last row is centred when it isn't full.
      let inRow = row == rows - 1 ? images.count - row * columns : columns
      let rowOffset = (Double(columns - inRow) * (cellW + gap)) / 2
      let x = gap + Double(column) * (cellW + gap) + rowOffset
      let yFromTop = gap + Double(row) * (cellH + gap)
      let cell = CGRect(x: x, y: height - yFromTop - cellH, width: cellW, height: cellH)
      let radius = min(cellW, cellH) * recipe.cornerRadius
      let size = CGSize(width: image.width, height: image.height)
      let target =
        recipe.fill == .fill ? FrameOps.aspectFill(size, in: cell) : FrameOps.aspectFit(size, in: cell)
      let clip = recipe.fill == .fill ? cell : target
      ctx.saveGState()
      ctx.addPath(CGPath(roundedRect: clip, cornerWidth: radius, cornerHeight: radius, transform: nil))
      ctx.clip()
      ctx.draw(image, in: target)
      ctx.restoreGState()
    }
    return try EditOps.make(ctx)
  }
}

// MARK: QR

public enum QROps {
  /// The text of every QR code in the image, top to bottom.
  public static func read(_ url: URL) throws -> [String] {
    let image = try ImageOps.loadOriented(ImageInput.readableURL(for: url))
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    let results = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
    return results.compactMap(\.payloadStringValue)
  }
}
