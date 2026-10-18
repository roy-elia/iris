import DropCore
import SwiftUI
import UniformTypeIdentifiers

/// One segment of a ring: an annular sector with rounded joins.
struct RingSegment: Shape {
  var startAngle: Angle
  var endAngle: Angle
  var innerRatio: CGFloat = 0.42
  /// Gap between neighbouring segments, in points along the ring.
  var gap: CGFloat = 6

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outer = min(rect.width, rect.height) / 2
    let inner = outer * innerRatio
    // Convert the linear gap into an angle at each radius so the gap is even.
    let outerInset = Angle(radians: Double(gap / 2 / outer))
    let innerInset = Angle(radians: Double(gap / 2 / inner))
    var p = Path()
    p.addArc(
      center: center, radius: outer, startAngle: startAngle + outerInset, endAngle: endAngle - outerInset,
      clockwise: false)
    p.addArc(
      center: center, radius: inner, startAngle: endAngle - innerInset, endAngle: startAngle + innerInset,
      clockwise: true)
    p.closeSubpath()
    return p
  }
}

/// The radial action wheel. In `.click` mode segments are buttons; in `.drop` mode each
/// segment is a drop target for files being dragged.
struct RadialWheel: View {
  enum Mode { case click, drop }

  let kind: WheelKind
  let items: [WheelItem]
  let centerText: String
  let mode: Mode
  let onSelect: (WheelItem, [URL]) -> Void

  @State private var hovered: String?
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.forceIncreasedContrast) private var forceContrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geo in
      let size = min(geo.size.width, geo.size.height)
      let step = 360.0 / Double(max(items.count, 1))
      ZStack {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          // Start at the top, going clockwise.
          let start = Angle(degrees: -90 - step / 2 + step * Double(index))
          segment(item, start: start, end: start + .degrees(step), size: size)
        }
        center(size: size)
      }
      .frame(width: size, height: size)
      .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }
    .aspectRatio(1, contentMode: .fit)
    .padding(10)
    .glassPanel(cornerRadius: 999)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(kind.longTitle) wheel")
  }

  @ViewBuilder
  private func segment(_ item: WheelItem, start: Angle, end: Angle, size: CGFloat) -> some View {
    let shape = RingSegment(startAngle: start, endAngle: end)
    let isHot = hovered == item.id && item.isEnabled
    let stroke = DesignTokens.Stroke.edge(
      for: scheme, increasedContrast: contrast == .increased || forceContrast)
    let mid = Angle(degrees: (start.degrees + end.degrees) / 2)
    let labelRadius = size / 2 * 0.71
    let offset = CGSize(
      width: cos(mid.radians) * labelRadius, height: sin(mid.radians) * labelRadius)

    ZStack {
      shape
        .fill(
          isHot
            ? AnyShapeStyle(DesignTokens.Palette.accentFill)
            : AnyShapeStyle(
              DesignTokens.scrim(for: scheme, increasedContrast: contrast == .increased || forceContrast))
        )
        .glassEffect(isHot ? .regular.tint(DesignTokens.Palette.accentFill) : .regular, in: shape)
        .overlay(shape.stroke(stroke.color, lineWidth: stroke.width))
      VStack(spacing: 3) {
        if let symbol = item.systemImage {
          Image(systemName: symbol).font(.title3).accessibilityHidden(true)
        }
        Text(item.title)
          .font(.system(.caption, design: .rounded).weight(.bold))
          .textCase(.uppercase)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(0.7)
      }
      .foregroundStyle(
        isHot
          ? DesignTokens.Palette.onAccent
          : (item.isEnabled ? Color.primary : DesignTokens.Palette.secondaryText)
      )
      .frame(width: size * 0.2)
      .offset(offset)
      .allowsHitTesting(false)
    }
    .contentShape(shape)
    .scaleEffect(isHot && !reduceMotion ? 1.03 : 1)
    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: isHot)
    .modifier(SegmentInteraction(mode: mode, item: item, hovered: $hovered, onSelect: onSelect))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(item.title)
    .accessibilityHint(item.disabledReason ?? "")
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("wheel-\(item.id)")
    .accessibilityAction {
      if item.isEnabled { onSelect(item, []) }
    }
    .help(item.disabledReason ?? item.title)
  }

  private func center(size: CGFloat) -> some View {
    VStack(spacing: 2) {
      Text(centerText).font(.headline.monospacedDigit())
      Text(kind.title).font(.caption2).foregroundStyle(DesignTokens.Palette.secondaryText)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .glassPanel(cornerRadius: 999, shadowed: false)
    .frame(width: size * 0.36)
    .accessibilityElement(children: .combine)
  }
}

/// Click or drop behaviour for a segment.
private struct SegmentInteraction: ViewModifier {
  let mode: RadialWheel.Mode
  let item: WheelItem
  @Binding var hovered: String?
  let onSelect: (WheelItem, [URL]) -> Void

  func body(content: Content) -> some View {
    switch mode {
    case .click:
      content
        .onHover { inside in hovered = inside ? item.id : (hovered == item.id ? nil : hovered) }
        .onTapGesture { if item.isEnabled { onSelect(item, []) } }
    case .drop:
      content.onDrop(
        of: [.fileURL],
        isTargeted: Binding(
          get: { hovered == item.id },
          set: { inside in hovered = inside ? item.id : (hovered == item.id ? nil : hovered) })
      ) { providers in
        guard item.isEnabled else { return false }
        URLLoader.load(providers) { urls in onSelect(item, urls) }
        return true
      }
    }
  }
}

/// Reads file URLs out of drag providers and calls back on the main actor.
enum URLLoader {
  static func load(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    let collected = Collector()
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      group.enter()
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        if let url { collected.append(url) }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      MainActor.assumeIsolated { completion(collected.urls) }
    }
  }

  private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.withLock { storage.append(url) } }
    var urls: [URL] { lock.withLock { storage } }
  }
}
