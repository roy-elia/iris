import AppKit

/// The menu-bar icon. Idle, it's the app glyph; while a task runs, a smaller glyph sits inside
/// a ring that fills clockwise from the top. It's a template image, so the menu bar colours it
/// for light, dark and Increase Contrast.
enum MenuBarIcon {
  static let size = NSSize(width: 18, height: 18)

  /// Progress is rounded to 5% steps so the menu bar isn't redrawn on every tiny update.
  static func quantised(_ progress: Double?) -> Double? {
    progress.map { (min(max($0, 0), 1) * 20).rounded() / 20 }
  }

  static func image(progress: Double?) -> NSImage {
    let progress = quantised(progress)
    let image = NSImage(size: size, flipped: false) { rect in
      guard let progress else {
        AppGlyph.draw(in: rect)
        return true
      }
      let ring = rect.insetBy(dx: 1.25, dy: 1.25)
      let track = NSBezierPath(ovalIn: ring)
      track.lineWidth = 1.5
      NSColor.black.withAlphaComponent(0.3).setStroke()
      track.stroke()
      // Always show a sliver, so a task that has just started still reads as running.
      let sweep = max(progress, 0.04) * 360
      let arc = NSBezierPath()
      arc.appendArc(
        withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: ring.width / 2, startAngle: 90,
        endAngle: 90 - sweep, clockwise: true)
      arc.lineWidth = 1.5
      arc.lineCapStyle = .round
      NSColor.black.setStroke()
      arc.stroke()
      AppGlyph.draw(in: rect.insetBy(dx: 4, dy: 4))
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription =
      progress.map { "File Drop Utility, \(Int(($0 * 100).rounded()))% done" } ?? "File Drop Utility"
    return image
  }
}
