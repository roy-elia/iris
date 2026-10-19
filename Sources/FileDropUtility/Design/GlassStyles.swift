import SwiftUI

/// A floating Liquid Glass panel with continuous corners. The system draws the glass's rim,
/// depth and legibility treatment, and turns it into a solid surface when Reduce
/// Transparency is on, so nothing is layered on top of it here.
struct GlassPanel: ViewModifier {
  var cornerRadius: CGFloat = DesignTokens.Radius.card
  var tint: Color? = nil
  var interactive = false

  func body(content: Content) -> some View {
    content.glassEffect(
      Glass.regular.tint(tint).interactive(interactive),
      in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

extension View {
  /// Wraps the view in a floating glass panel. Add padding before calling this.
  func glassPanel(
    cornerRadius: CGFloat = DesignTokens.Radius.card, tint: Color? = nil, interactive: Bool = false
  ) -> some View {
    modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
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

/// A keyboard key cap, for showing which modifier opens which wheel.
struct Keycap: View {
  let symbol: String
  let name: String

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      Text(symbol).font(.title3.weight(.semibold))
      Text(name).font(.caption)
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(minWidth: 64, alignment: .trailing)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name) key")
  }
}
