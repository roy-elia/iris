import AppKit
import SwiftUI

/// Shape, spacing and motion values shared by every screen. Materials come from the system
/// (Liquid Glass) and colours are system semantic colours, so neither is defined here.
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

  /// Text, icons and fills use system semantic colours (`.primary`, `.secondary`,
  /// `Color.accentColor`, `.red`, `.orange`), which adapt to light, dark and Increase
  /// Contrast. Only the wheel's highlight still has fixed colours, until it moves to glass.
  enum Palette {
    static let wheelHotTop = Color(red: 0.00, green: 0.34, blue: 0.56)
    static let wheelHotBottom = Color(red: 0.02, green: 0.60, blue: 0.76)
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
