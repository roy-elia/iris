import SwiftUI

/// A floating glass tab bar. The selected tab's highlight morphs between tabs with the
/// app spring (or fades under Reduce Motion).
struct FloatingTabBar<Tab: Hashable & Identifiable>: View {
  let tabs: [Tab]
  @Binding var selection: Tab
  let title: (Tab) -> String
  let systemImage: (Tab) -> String

  @Namespace private var glassNamespace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GlassEffectContainer(spacing: 4) {
      HStack(spacing: 4) {
        ForEach(tabs) { tab in
          let isSelected = tab == selection
          Button {
            withMorph(reduceMotion: reduceMotion) { selection = tab }
          } label: {
            Label(title(tab), systemImage: systemImage(tab))
              .labelStyle(.titleAndIcon)
              .font(.callout.weight(isSelected ? .semibold : .regular))
              .foregroundStyle(isSelected ? DesignTokens.Palette.onAccent : .primary)
              .padding(.horizontal, 12)
              .padding(.vertical, 7)
              .frame(maxWidth: .infinity)
              .contentShape(Capsule(style: .continuous))
          }
          .buttonStyle(.plain)
          .background {
            if isSelected {
              Capsule(style: .continuous)
                .fill(DesignTokens.Palette.accentFill)
                .glassEffect(.regular.tint(DesignTokens.Palette.accentFill), in: Capsule(style: .continuous))
                .glassEffectID("selection", in: glassNamespace)
            }
          }
          .accessibilityLabel(title(tab))
          .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
          .accessibilityIdentifier("tab-\(title(tab))")
        }
      }
      .padding(4)
      .glassPanel(cornerRadius: 999, shadowed: true)
    }
  }
}
