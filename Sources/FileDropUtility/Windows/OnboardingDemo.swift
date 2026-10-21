import SwiftUI

/// A looping mini-demo of the core gesture: drag a file, hold a key, drop on a segment.
struct WheelDemoView: View {
  private enum Step: Int { case drag, hold, aim, drop }

  let kind: WheelKind = .convert
  @State private var step: Step = .drag
  @State private var hotIndex = 0
  @State private var revision = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var items: [WheelItem] { kind.items(for: []) }

  var body: some View {
    HStack(spacing: 40) {
      ZStack {
        RadialWheel(
          kind: kind, items: items, centerText: step == .drop ? "Saved" : "2.4 MB", mode: .drop,
          hotID: step == .aim || step == .drop ? items[safe: hotIndex]?.id : nil,
          introRevision: revision
        ) { _, _ in }
        .frame(width: 300, height: 300)
        .opacity(step == .drag ? 0.18 : 1)
        .scaleEffect(step == .drag ? 0.92 : 1)
        fileChip
      }
      .frame(width: 320, height: 320)
      .allowsHitTesting(false)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 16) {
        caption(1, "Drag a file", active: step == .drag)
        HStack(spacing: 12) {
          caption(2, "Hold", active: step == .hold)
          Keycap(symbol: kind.keySymbol, name: kind.keyName)
            .scaleEffect(step == .hold ? 1.08 : 1)
        }
        caption(3, "Drop on a segment", active: step == .aim || step == .drop)
      }
      .frame(maxWidth: 260, alignment: .leading)
    }
    .task { await play() }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Demo: drag a file, hold \(kind.keyName), then drop it on a segment of the wheel.")
  }

  private var fileChip: some View {
    Image(systemName: "photo.fill")
      .font(.title)
      .foregroundStyle(.white)
      .frame(width: 54, height: 54)
      .background(DesignTokens.Palette.teal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .shadow(radius: step == .drag ? 8 : 2, y: 3)
      .offset(chipOffset)
      .opacity(step == .drop ? 0 : 1)
  }

  private var chipOffset: CGSize {
    switch step {
    case .drag: return CGSize(width: -110, height: 90)
    case .hold: return CGSize(width: -50, height: 40)
    case .aim, .drop:
      // Rides over the lit segment (segments are laid out clockwise from the top).
      let angle = (Double(hotIndex) + 0.5) / Double(max(items.count, 1)) * 2 * .pi
      return CGSize(width: sin(angle) * 95, height: -cos(angle) * 95)
    }
  }

  private func caption(_ n: Int, _ text: String, active: Bool) -> some View {
    Text("\(n). \(text)")
      .font(.title2.weight(.semibold))
      .foregroundStyle(active ? Color.primary : Color.secondary)
  }

  /// Under Reduce Motion the demo holds on its final frame instead of looping.
  private func play() async {
    if reduceMotion {
      step = .aim
      return
    }
    while !Task.isCancelled {
      await set(.drag, hold: 1.0)
      revision += 1
      await set(.hold, hold: 1.1)
      for i in [0, 1, 2] where i < items.count {
        hotIndex = i
        await set(.aim, hold: 0.7)
      }
      await set(.drop, hold: 1.2)
    }
  }

  private func set(_ next: Step, hold seconds: Double) async {
    withAnimation(.smooth(duration: 0.45)) { step = next }
    try? await Task.sleep(for: .seconds(seconds))
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
