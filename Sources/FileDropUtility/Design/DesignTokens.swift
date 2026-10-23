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
    /// The light lilac of hovered wheel petals and primary buttons: #A78BFA in light, #B9A6FA in
    /// dark, where it glows against dark surfaces. Its labels use `lilacInk`, not white.
    static let lilac = Color(
      nsColor: adaptive(light: 0xA78BFA, dark: 0xB9A6FA, contrast: 0xA78BFA, darkContrast: 0xB9A6FA))
    /// Deep ink for text and symbols on `lilac`: 6.0:1 in light, 7.6:1 in dark; Increase
    /// Contrast #120A2E (7.6:1 / 9.4:1).
    static let lilacInk = Color(nsColor: adaptive(light: 0x22184A, dark: 0x22184A, contrast: 0x120A2E))
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

  /// The view's one primary action: lilac over lilac Liquid Glass with a deep-ink label, at
  /// the size and shape of a standard macOS push button. A custom style because the system's
  /// prominent glass draws its own near-white label, which can't be read on a light lilac.
  func primaryActionStyle() -> some View {
    buttonStyle(PrimaryActionButtonStyle())
  }
}

/// Lilac primary button: a 24 pt rounded rectangle with a 6 pt radius and 12 pt side padding,
/// like the system's prominent button, filled with `lilac` over lilac glass so it keeps its
/// colour in inactive windows, where the system drops glass tints.
struct PrimaryActionButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.controlSize) private var controlSize

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: controlSize == .large ? 8 : 6, style: .continuous)
    let metrics: (height: CGFloat, padding: CGFloat) =
      switch controlSize {
      case .mini, .small: (20, 8)
      case .large, .extraLarge: (30, 14)
      default: (24, 12)
      }
    return configuration.label
      .font(controlSize == .small || controlSize == .mini ? .callout : .body)
      .foregroundStyle(DesignTokens.Palette.lilacInk.opacity(isEnabled ? 1 : 0.45))
      .padding(.horizontal, metrics.padding)
      .frame(minHeight: metrics.height)
      .background(
        DesignTokens.Palette.lilac.opacity(isEnabled ? (configuration.isPressed ? 1 : 0.92) : 0.35),
        in: shape
      )
      .overlay(shape.strokeBorder(.white.opacity(configuration.isPressed ? 0.1 : 0.22), lineWidth: 0.5))
      .glassEffect(.regular.tint(DesignTokens.Palette.lilac).interactive(), in: shape)
      .brightness(configuration.isPressed ? -0.06 : 0)
      .contentShape(shape)
  }
}
