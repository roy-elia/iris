import AppKit
import SwiftUI

/// The app's mark: a five-petal wheel whose lit petal swells past the rim, drawn with the
/// radial wheel's own `PetalShape`. Idle petals are half opacity, so the lit one reads without
/// colour. Matches `Resources/AppIcon/HotbarIcon.svg`.
enum AppGlyph {
  /// Designed in a 24pt box (y down), offset so the swollen petal sits optically centred.
  private static let box: CGFloat = 24
  private static let center = CGPoint(x: 11.4, y: 12.6)
  private static let count = 5
  private static let lit = 1
  private static let radius: CGFloat = 9.2

  /// Each petal's path in a `side`-point square, with whether it is the lit petal.
  static func petals(side: CGFloat) -> [(path: Path, isLit: Bool)] {
    let k = side / box
    let c = CGPoint(x: center.x * k, y: center.y * k)
    let s = radius / 126
    let step = 360.0 / Double(count)
    let frame = CGRect(x: c.x - side, y: c.y - side, width: side * 2, height: side * 2)
    return (0..<count).map { index in
      let isLit = index == lit
      let widen = Angle(degrees: isLit ? 2 : 0)
      let start = WheelGeometry.startAngle(index: index, count: count)
      let shape = PetalShape(
        startAngle: start - widen, endAngle: start + .degrees(step) + widen, innerRadius: 2.6 * k,
        outerRadius: (radius - 8 * s + (isLit ? 1.7 : 0)) * k, gap: 1.6 * k, cornerRadius: 1.2 * k)
      return (shape.path(in: frame), isLit)
    }
  }

  /// Fills the glyph into `rect` of the current AppKit context (unflipped, y up), black at
  /// full and half alpha for a template image.
  static func draw(in rect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    for petal in petals(side: min(rect.width, rect.height)) {
      ctx.addPath(petal.path.cgPath)
      ctx.setFillColor(NSColor.black.withAlphaComponent(petal.isLit ? 1 : 0.5).cgColor)
      ctx.fillPath()
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
      for petal in AppGlyph.petals(side: side) {
        context.fill(petal.path, with: .style(.foreground.opacity(petal.isLit ? 1 : 0.5)))
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }
}
