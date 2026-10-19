import CoreGraphics
import Foundation

/// A rectangle in normalised image coordinates: origin top-left, all values 0...1.
public struct NormRect: Codable, Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  /// Builds a rectangle from two corners, in any order, clamped to the image.
  public init(from a: NormPoint, to b: NormPoint) {
    let x0 = min(max(min(a.x, b.x), 0), 1)
    let y0 = min(max(min(a.y, b.y), 0), 1)
    let x1 = min(max(max(a.x, b.x), 0), 1)
    let y1 = min(max(max(a.y, b.y), 0), 1)
    self.init(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  public static let full = NormRect(x: 0, y: 0, width: 1, height: 1)

  /// Too small to mean anything (a click rather than a drag).
  public var isEmpty: Bool { width < 0.005 || height < 0.005 }

  /// Pixel rectangle in a top-left-origin image of the given size.
  public func pixels(width w: Int, height h: Int) -> CGRect {
    CGRect(
      x: (x * Double(w)).rounded(), y: (y * Double(h)).rounded(),
      width: max(1, (width * Double(w)).rounded()), height: max(1, (height * Double(h)).rounded()))
  }
}

/// A point in normalised image coordinates (top-left origin).
public struct NormPoint: Codable, Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// A freehand annotation stroke.
public struct Stroke: Codable, Equatable, Hashable, Sendable {
  public var points: [NormPoint]
  public var color: RGBA
  /// Line width as a fraction of the image's shorter side.
  public var width: Double

  public init(points: [NormPoint], color: RGBA, width: Double = 0.01) {
    self.points = points
    self.color = color
    self.width = width
  }
}

public enum RedactStyle: String, Codable, CaseIterable, Sendable {
  /// Solid black: the only style that's safe for sensitive information.
  case blackout
  case pixelate
  /// Softens details; reversible enough that it shouldn't hide secrets.
  case blur
}

/// An annotation drawn on top of the image. Positions are normalised (top-left origin);
/// widths and sizes are fractions of the image's shorter side.
public enum Mark: Codable, Equatable, Hashable, Sendable {
  case arrow(from: NormPoint, to: NormPoint, color: RGBA, width: Double)
  case rectangle(NormRect, color: RGBA, width: Double, filled: Bool)
  case ellipse(NormRect, color: RGBA, width: Double, filled: Bool)
  /// A translucent marker over a region.
  case highlight(NormRect, color: RGBA)
  /// Text whose top-left corner is at `at`, wrapped to `boxWidth` (normalised).
  case text(String, at: NormPoint, color: RGBA, size: Double, boxWidth: Double)
  /// A numbered disc.
  case callout(number: Int, at: NormPoint, color: RGBA, radius: Double)
  /// A round bubble at `at` showing the area around `source`, enlarged by `zoom`.
  case magnifier(source: NormPoint, at: NormPoint, radius: Double, zoom: Double)
  /// An image file placed in `rect`.
  case sticker(path: String, rect: NormRect)
}

/// Everything the editor can change, applied in a fixed order:
/// rotate, adjust colour, redact, annotate (strokes, then marks), crop. Rects and strokes are relative to the
/// rotated image, which is what the editor shows.
public struct EditRecipe: Codable, Equatable, Hashable, Sendable {
  public var quarterTurns: Int
  public var brightness: Double
  public var contrast: Double
  public var saturation: Double
  public var redactions: [NormRect]
  public var redactStyle: RedactStyle
  public var strokes: [Stroke]
  public var marks: [Mark]
  public var crop: NormRect?

  public static let brightnessRange: ClosedRange<Double> = -0.5...0.5
  public static let contrastRange: ClosedRange<Double> = 0.5...1.5
  public static let saturationRange: ClosedRange<Double> = 0...2

  public init(
    quarterTurns: Int = 0, brightness: Double = 0, contrast: Double = 1, saturation: Double = 1,
    redactions: [NormRect] = [], redactStyle: RedactStyle = .blackout, strokes: [Stroke] = [],
    marks: [Mark] = [], crop: NormRect? = nil
  ) {
    self.quarterTurns = quarterTurns
    self.brightness = brightness
    self.contrast = contrast
    self.saturation = saturation
    self.redactions = redactions
    self.redactStyle = redactStyle
    self.strokes = strokes
    self.marks = marks
    self.crop = crop
  }

  /// Rotation normalised to 0...3 clockwise quarter turns.
  public var normalizedTurns: Int { ((quarterTurns % 4) + 4) % 4 }

  public var hasColorAdjustments: Bool { brightness != 0 || contrast != 1 || saturation != 1 }

  /// True when applying the recipe would change nothing.
  public var isIdentity: Bool {
    normalizedTurns == 0 && !hasColorAdjustments && redactions.isEmpty && strokes.isEmpty && marks.isEmpty
      && (crop == nil || crop == .full)
  }
}

extension RGBA {
  /// The colour in sRGB, so it matches what the user picked.
  public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
