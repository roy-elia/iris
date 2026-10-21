import AppKit
import SwiftUI

/// The app's mark: a ring of twelve petals around an iris (a solid ring and a pupil), so it is
/// the flower and the eye at once. Petals are half opacity and the iris solid, so it reads in
/// monochrome as a template image. Matches `Resources/AppIcon/HotbarIcon.svg`, which is the
/// app icon's geometry (a 1024 canvas) scaled into a 24pt box.
enum AppGlyph {
  private static let box: CGFloat = 24
  /// The icon canvas maps into the box by this scale and offset.
  private static let canvasScale: CGFloat = 24 / 720
  private static let canvasOffset = CGPoint(x: -152, y: -150)
  private static let center = CGPoint(x: 512, y: 520)
  private static let petalCount = 12
  private static let petalLength: CGFloat = 222
  private static let petalWidth: CGFloat = 64
  private static let petalBase: CGFloat = 102
  private static let irisRadius: CGFloat = 132
  private static let irisInner: CGFloat = 80
  private static let pupilRadius: CGFloat = 46

  struct Shape {
    let path: Path
    let opacity: Double
  }

  /// Every part in a `side`-point square, back to front.
  static func shapes(side: CGFloat) -> [Shape] {
    let k = side / box * canvasScale
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: (x + canvasOffset.x) * k, y: (y + canvasOffset.y) * k)
    }
    var out: [Shape] = []
    for i in 0..<petalCount {
      let t = Double(i) * 2 * .pi / Double(petalCount)
      // Petal coordinates: x across, y outward (negative), rotated to angle t from the top.
      func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        p(center.x + x * cos(t) - y * sin(t), center.y + x * sin(t) + y * cos(t))
      }
      let b = petalBase, l = petalLength, w = petalWidth
      var path = Path()
      path.move(to: q(0, -b))
      path.addCurve(to: q(0, -b - l), control1: q(w * 0.95, -b - l * 0.3), control2: q(w * 0.62, -b - l * 0.95))
      path.addCurve(to: q(0, -b), control1: q(-w * 0.62, -b - l * 0.95), control2: q(-w * 0.95, -b - l * 0.3))
      path.closeSubpath()
      out.append(Shape(path: path, opacity: 0.5))
    }
    func circle(_ r: CGFloat) -> Path {
      let c = p(center.x, center.y)
      return Path(ellipseIn: CGRect(x: c.x - r * k, y: c.y - r * k, width: 2 * r * k, height: 2 * r * k))
    }
    var ring = circle(irisRadius)
    ring.addPath(circle(irisInner))
    out.append(Shape(path: ring, opacity: 1))
    out.append(Shape(path: circle(pupilRadius), opacity: 1))
    return out
  }

  /// Fills the glyph into `rect` of the current AppKit context (unflipped, y up), black at
  /// full and half alpha for a template image.
  static func draw(in rect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    for shape in shapes(side: min(rect.width, rect.height)) {
      ctx.addPath(shape.path.cgPath)
      ctx.setFillColor(NSColor.black.withAlphaComponent(shape.opacity).cgColor)
      ctx.fillPath(using: .evenOdd)
    }
    ctx.restoreGState()
  }
}

/// The glyph as a SwiftUI view; it takes the current foreground style.
struct AppGlyphView: View {
  var body: some View {
    Canvas { context, size in
      let side = min(size.width, size.height)
      context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
      for shape in AppGlyph.shapes(side: side) {
        context.fill(
          shape.path, with: .style(.foreground.opacity(shape.opacity)), style: FillStyle(eoFill: true))
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }
}
