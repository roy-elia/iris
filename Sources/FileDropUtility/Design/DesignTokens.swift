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
    /// Fill for prominent buttons and selected segments. White text on it is ≥ 5.1:1.
    static let accentFill = Color(
      nsColor: dynamic(light: (0.00, 0.42, 0.52), dark: (0.02, 0.47, 0.58)))
    /// Accent for text and icons on glass. ≥ 6:1 on light and ≥ 9:1 on dark backgrounds.
    static let accentText = Color(
      nsColor: dynamic(light: (0.00, 0.40, 0.50), dark: (0.40, 0.82, 0.92)))
    /// Text on `accentFill`.
    static let onAccent = Color.white
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
