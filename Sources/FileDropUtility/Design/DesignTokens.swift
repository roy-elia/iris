import AppKit
import SwiftUI

/// Every adaptive design value in one place. Change a value here and every glass panel,
/// shadow, stroke and animation follows.
///
/// Custom colours are defined in code with light and dark variants because asset catalogs
/// need Xcode's `actool`, which the Command Line Tools don't include.
enum DesignTokens {
  // MARK: Shape

  enum Radius {
    static let window: CGFloat = 28
    static let card: CGFloat = 20
    static let control: CGFloat = 12
    static let chip: CGFloat = 8
  }

  // MARK: Spacing (floating layout insets)

  enum Spacing {
    /// Gap between a floating panel and the window edge.
    static let inset: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let stack: CGFloat = 10
    static let tight: CGFloat = 6
  }

  // MARK: Colour

  enum Palette {
    /// Fill for prominent buttons and selected segments. White text on it is ≥ 4.5:1 measured with the glass highlight (7:1+ flat).
    static let accentFill = Color(
      nsColor: dynamic(light: (0.00, 0.36, 0.45), dark: (0.00, 0.34, 0.43)))
    /// Accent for text and icons on glass. ≥ 6:1 on light and ≥ 9:1 on dark backgrounds.
    static let accentText = Color(
      nsColor: dynamic(light: (0.00, 0.40, 0.50), dark: (0.40, 0.82, 0.92)))
    /// Text on `accentFill`.
    static let onAccent = Color.white
    /// Error text. System red is too light for small text on bright glass.
    static let errorText = Color(
      nsColor: dynamic(light: (0.70, 0.04, 0.07), dark: (1.00, 0.50, 0.48)))
    /// Warning text and icons. System orange is under 3:1 on light backgrounds.
    static let warningText = Color(
      nsColor: dynamic(light: (0.60, 0.29, 0.00), dark: (1.00, 0.72, 0.32)))
    /// Secondary text. The system `.secondary` label is 50% black (about 3.9:1 on white),
    /// below WCAG AA, so this uses a stronger mix of the label colour, and stronger still
    /// with Increase Contrast.
    static let secondaryText = Color(
      nsColor: NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [
          .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ]) {
        case .darkAqua?: NSColor.white.withAlphaComponent(0.66)
        case .accessibilityHighContrastDarkAqua?: NSColor.white.withAlphaComponent(0.82)
        case .accessibilityHighContrastAqua?: NSColor.black.withAlphaComponent(0.80)
        default: NSColor.black.withAlphaComponent(0.64)
        }
      })
  }

  // MARK: Legibility backing

  /// A thin layer of the window background colour inside each glass panel. It keeps text
  /// at ≥ 4.5:1 over bright, busy content while the glass still shows what's behind it.
  static func scrim(for scheme: ColorScheme, increasedContrast: Bool) -> Color {
    let base = Color(nsColor: .windowBackgroundColor)
    switch (scheme, increasedContrast) {
    case (.dark, false): return base.opacity(0.55)
    case (_, false): return base.opacity(0.50)
    case (_, true): return base.opacity(0.85)
    }
  }

  // MARK: Edge highlight

  struct Stroke {
    let color: Color
    let width: CGFloat

    static func edge(for scheme: ColorScheme, increasedContrast: Bool) -> Stroke {
      switch (scheme, increasedContrast) {
      case (.dark, false): Stroke(color: .white.opacity(0.16), width: 1)
      case (.dark, true): Stroke(color: .white.opacity(0.45), width: 1.5)
      case (_, false): Stroke(color: .black.opacity(0.10), width: 1)
      case (_, true): Stroke(color: .black.opacity(0.40), width: 1.5)
      }
    }
  }

  // MARK: Depth

  struct Shadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    /// Tight shadow where the panel meets the surface.
    static func contact(for scheme: ColorScheme) -> Shadow {
      scheme == .dark
        ? Shadow(color: .black.opacity(0.50), radius: 1.5, y: 1)
        : Shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
    }

    /// Large, soft shadow for ambient depth.
    static func ambient(for scheme: ColorScheme) -> Shadow {
      scheme == .dark
        ? Shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        : Shadow(color: .black.opacity(0.10), radius: 22, y: 12)
    }
  }

  // MARK: Motion

  enum Motion {
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.7)
    static let fade = Animation.easeInOut(duration: 0.2)

    /// Spring morph normally; a plain fade when Reduce Motion is on.
    static func animation(reduceMotion: Bool) -> Animation { reduceMotion ? fade : spring }

    static func transition(reduceMotion: Bool) -> AnyTransition {
      reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity)
    }
  }

  // MARK: Helpers

  private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> NSColor {
    NSColor(name: nil) { appearance in
      let isDark =
        appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        .map { [.darkAqua, .vibrantDark].contains($0) } ?? false
      let c = isDark ? dark : light
      return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    }
  }
}
