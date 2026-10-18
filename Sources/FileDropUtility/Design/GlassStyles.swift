import SwiftUI

/// A floating glass panel: Liquid Glass material, continuous corners, an appearance-aware
/// edge stroke and two-layer shadow. Falls back to an opaque surface only when the user
/// has turned on Reduce Transparency.
struct GlassPanel: ViewModifier {
  var cornerRadius: CGFloat = DesignTokens.Radius.card
  var tint: Color? = nil
  var interactive = false
  var shadowed = true

  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.forceIncreasedContrast) private var forceContrast
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let increased = contrast == .increased || forceContrast
    let stroke = DesignTokens.Stroke.edge(for: scheme, increasedContrast: increased)
    let contact = DesignTokens.Shadow.contact(for: scheme)
    let ambient = DesignTokens.Shadow.ambient(for: scheme)

    Group {
      if reduceTransparency {
        content.background(Color(nsColor: .windowBackgroundColor), in: shape)
      } else {
        content
          .background(
            tint == nil ? DesignTokens.scrim(for: scheme, increasedContrast: increased) : .clear, in: shape
          )
          .glassEffect(glass, in: shape)
      }
    }
    .overlay(shape.strokeBorder(stroke.color, lineWidth: stroke.width).allowsHitTesting(false))
    .shadow(color: shadowed ? contact.color : .clear, radius: contact.radius, y: contact.y)
    .shadow(color: shadowed ? ambient.color : .clear, radius: ambient.radius, y: ambient.y)
  }

  private var glass: Glass {
    var g = Glass.regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
  }
}

private struct ForceIncreasedContrastKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Treats Increase Contrast as on. The system setting can't be set per window, so the
  /// snapshot harness uses this to check the high-contrast styling. (Written by hand:
  /// the `@Entry` macro's plugin ships only with Xcode.)
  var forceIncreasedContrast: Bool {
    get { self[ForceIncreasedContrastKey.self] }
    set { self[ForceIncreasedContrastKey.self] = newValue }
  }
}

extension View {
  /// Wraps the view in a floating glass panel. Add padding before calling this.
  func glassPanel(
    cornerRadius: CGFloat = DesignTokens.Radius.card, tint: Color? = nil, interactive: Bool = false,
    shadowed: Bool = true
  ) -> some View {
    modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint, interactive: interactive, shadowed: shadowed))
  }

  /// A padded glass card for grouping content inside a window.
  func glassCard() -> some View {
    padding(DesignTokens.Spacing.cardPadding).frame(maxWidth: .infinity, alignment: .leading).glassPanel()
  }

  /// Runs a state change with the spring morph, or a fade under Reduce Motion.
  func morphTransition(reduceMotion: Bool) -> some View {
    transition(DesignTokens.Motion.transition(reduceMotion: reduceMotion))
  }
}

/// Animates a state change with the app's spring, or a fade when Reduce Motion is on.
@MainActor
func withMorph(reduceMotion: Bool, _ body: () -> Void) {
  withAnimation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), body)
}

/// Primary action button: blue-teal glass with white text.
struct ProminentGlassButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(DesignTokens.Palette.onAccent)
      .padding(.horizontal, 22)
      .padding(.vertical, 10)
      .background(
        DesignTokens.Palette.accentFill.opacity(isEnabled ? 1 : 0.45),
        in: Capsule(style: .continuous)
      )
      .glassEffect(
        .regular.tint(DesignTokens.Palette.accentFill).interactive(), in: Capsule(style: .continuous)
      )
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .opacity(isEnabled ? 1 : 0.6)
  }
}

/// Secondary action: plain glass capsule with primary-coloured text.
struct SubtleGlassButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.medium))
      .foregroundStyle(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
  }
}

extension ButtonStyle where Self == ProminentGlassButtonStyle {
  static var prominentGlass: ProminentGlassButtonStyle { ProminentGlassButtonStyle() }
}

extension ButtonStyle where Self == SubtleGlassButtonStyle {
  static var subtleGlass: SubtleGlassButtonStyle { SubtleGlassButtonStyle() }
}

/// A keyboard key cap, for showing which modifier opens which wheel.
struct Keycap: View {
  let symbol: String
  let name: String

  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.forceIncreasedContrast) private var forceContrast

  var body: some View {
    let stroke = DesignTokens.Stroke.edge(
      for: scheme, increasedContrast: contrast == .increased || forceContrast)
    VStack(alignment: .trailing, spacing: 2) {
      Text(symbol).font(.title3.weight(.semibold))
      Text(name).font(.caption)
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(minWidth: 64, alignment: .trailing)
    .background(
      .background.secondary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
        .strokeBorder(stroke.color, lineWidth: stroke.width)
    )
    .shadow(color: DesignTokens.Shadow.contact(for: scheme).color, radius: 1, y: 1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name) key")
  }
}
