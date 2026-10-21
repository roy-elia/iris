import AppKit
import SwiftUI

/// Shape, spacing, colour and motion values shared by every screen. Materials come from the
/// system (Liquid Glass); the only custom colour is the brand violet.
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

  /// The app's iris violet, the one brand colour (the icon's gold stays in the icon). Everything
  /// else uses system semantic colours (`.primary`, `.secondary`, `.red`, `.orange`, hierarchical
  /// fills). Violet marks three things only: the primary action, the current selection, and
  /// success. Each role has light, dark and Increase Contrast values; ratios are against the
  /// surfaces they sit on.
  enum Palette {
    /// Fills behind white text: prominent buttons, selected tools, the lit wheel petal.
    /// #5B3FD9 (white on it 6.7:1); Increase Contrast #4527B8 (9.4:1).
    static let brand = Color(nsColor: adaptive(light: 0x5B3FD9, dark: 0x5B3FD9, contrast: 0x4527B8))
    /// The deeper end of the wheel's gradient and prominent buttons. White on it 10.3:1;
    /// Increase Contrast #2E1A8A (12.9:1).
    static let brandDeep = Color(nsColor: adaptive(light: 0x3F25A8, dark: 0x3F25A8, contrast: 0x2E1A8A))
    /// Violet text and symbols on the window and glass: #5338D0 in light (6.8:1 on #F5F5F7),
    /// #B3A3FF in dark (5.2:1 on #3A3A3C); Increase Contrast #3F25A8 / #CBC0FF.
    static let brandInk = Color(
      nsColor: adaptive(light: 0x5338D0, dark: 0xB3A3FF, contrast: 0x3F25A8, darkContrast: 0xCBC0FF))

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
  /// The app's violet as the tint for every control in a window: prominent buttons, toggles,
  /// sliders, selection and `.tint` foregrounds. Apply once at each window's root.
  func brandTint() -> some View {
    tint(DesignTokens.Palette.brand)
  }

  /// The view's one primary action: prominent Liquid Glass on the deeper violet. The system draws
  /// a prominent button's label in a light cyan it derives itself (a foreground style doesn't
  /// change it); the deeper `brandDeep` fill keeps it well above 4.5:1.
  func primaryActionStyle() -> some View {
    buttonStyle(.glassProminent).tint(DesignTokens.Palette.brandDeep)
  }
}
