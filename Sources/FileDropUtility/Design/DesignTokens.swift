import AppKit
import SwiftUI

/// Shape, spacing, colour and motion values shared by every screen. Materials come from the
/// system (Liquid Glass); the only custom colour is the brand lilac.
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

  /// The app's lilac, the one brand colour (the icon's gold stays in the icon). Everything
  /// else uses system semantic colours (`.primary`, `.secondary`, `.red`, `.orange`, hierarchical
  /// fills). Lilac marks three things only: the primary action, the current selection, and
  /// success. Each role has light, dark and Increase Contrast values; ratios are against the
  /// surfaces they sit on.
  enum Palette {
    /// Fills behind white text: selected tools, the lit wheel petal, the tint on glass.
    /// #7559E3 (white on it 4.9:1); Increase Contrast #5E43C9 (6.3:1).
    static let brand = Color(nsColor: adaptive(light: 0x7559E3, dark: 0x7559E3, contrast: 0x5E43C9))
    /// The deeper lilac for prominent buttons and the start of the wheel's gradient. The system
    /// draws a prominent button's label in a light tint of its fill; this stays above 4.5:1.
    /// Increase Contrast #4A30B5.
    static let brandDeep = Color(nsColor: adaptive(light: 0x6A4FD8, dark: 0x6A4FD8, contrast: 0x4A30B5))
    /// Lilac text and symbols on the window and glass: #6347D8 in light (5.6:1 on #F5F5F7),
    /// #C9BCFF in dark (6.6:1 on #3A3A3C); Increase Contrast #4A30B5 / #DDD4FF.
    static let brandInk = Color(
      nsColor: adaptive(light: 0x6347D8, dark: 0xC9BCFF, contrast: 0x4A30B5, darkContrast: 0xDDD4FF))

    static func adaptive(light: UInt32, dark: UInt32, contrast: UInt32, darkContrast: UInt32? = nil)
      -> NSColor
    {
      NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [
          .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ])
        return switch match {
        case .darkAqua: rgb(dark)
        case .accessibilityHighContrastAqua: rgb(contrast)
        case .accessibilityHighContrastDarkAqua: rgb(darkContrast ?? contrast)
        default: rgb(light)
        }
      }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
      NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
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
}

extension View {
  /// The app's lilac as the tint for every control in a window: prominent buttons, toggles,
  /// sliders, selection and `.tint` foregrounds. Apply once at each window's root.
  func brandTint() -> some View {
    tint(DesignTokens.Palette.brand)
  }

  /// The view's one primary action: prominent Liquid Glass on the deeper lilac. The system draws
  /// a prominent button's label in a light cyan it derives itself   /// change it); the deeper `brandDeep` fill keeps it above 4.5:1.
  func primaryActionStyle() -> some View {
    buttonStyle(.glassProminent).tint(DesignTokens.Palette.brandDeep)
  }
}
