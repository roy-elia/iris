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

/// Geometry shared by the SwiftUI wheel and the AppKit drop target, so the segment that
/// lights up is always the one under the pointer.
enum WheelGeometry {
  static let innerRatio: CGFloat = 0.42

  /// Angle where segment `index` of `count` starts. Segment 0 is centred at the top and
  /// the rest follow clockwise (in flipped, y-down coordinates).
  static func startAngle(index: Int, count: Int) -> Angle {
    let step = 360.0 / Double(max(count, 1))
    return Angle(degrees: -90 - step / 2 + step * Double(index))
  }

  /// The segment under `point`, given relative to the wheel's centre in y-down
  /// coordinates, or nil over the centre or outside the wheel.
  static func segment(at point: CGPoint, outerRadius: CGFloat, count: Int) -> Int? {
    WheelHitTest.segment(
      dx: point.x, dy: point.y, outerRadius: outerRadius, count: count, innerRatio: innerRatio)
  }
}

/// The radial action wheel: separate Liquid Glass segments around a glass centre pill.
/// In `.click` mode segments are buttons that light up under the pointer. In `.drop`
/// mode an AppKit drop target tracks the drag and passes the lit segment in `hotID`.
struct RadialWheel: View {
  enum Mode { case click, drop }

  let kind: WheelKind
  let items: [WheelItem]
  let centerText: String
  let mode: Mode
  /// The lit segment in `.drop` mode, set by `WheelDropView`.
  var hotID: String? = nil
  let onSelect: (WheelItem, [URL]) -> Void

  @State private var hovered: String?
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.forceIncreasedContrast) private var forceContrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var litID: String? { mode == .drop ? hotID : hovered }
  private var litItem: WheelItem? { items.first { $0.id == litID && $0.isEnabled } }

  var body: some View {
    GeometryReader { geo in
      let size = min(geo.size.width, geo.size.height)
      // Each segment keeps its own glass: a shared GlassEffectContainer would melt the
      // neighbouring shapes into one disc.
      ZStack {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          let start = WheelGeometry.startAngle(index: index, count: items.count)
          let step = 360.0 / Double(items.count)
          segment(item, start: start, end: start + .degrees(step), size: size)
        }
        center(size: size)
      }
      .frame(width: size, height: size)
      .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(kind.longTitle) wheel")
  }

  @ViewBuilder
  private func segment(_ item: WheelItem, start: Angle, end: Angle, size: CGFloat) -> some View {
    let shape = RingSegment(startAngle: start, endAngle: end, innerRatio: WheelGeometry.innerRatio, gap: 7)
    let isHot = litID == item.id && item.isEnabled
    let increased = contrast == .increased || forceContrast
    let mid = Angle(degrees: (start.degrees + end.degrees) / 2)
    let labelRadius = size / 2 * 0.71
    let offset = CGSize(
      width: cos(mid.radians) * labelRadius, height: sin(mid.radians) * labelRadius)
    let contact = DesignTokens.Shadow.contact(for: scheme)
    let ambient = DesignTokens.Shadow.ambient(for: scheme)

    ZStack {
      shape
        .fill(
          isHot
            ? AnyShapeStyle(DesignTokens.Palette.accentFill)
            : AnyShapeStyle(DesignTokens.scrim(for: scheme, increasedContrast: increased))
        )
        .glassEffect(isHot ? .regular.tint(DesignTokens.Palette.accentFill) : .regular, in: shape)
        // The lit segment glows in the accent colour instead of being outlined.
        .shadow(
          color: isHot ? DesignTokens.Palette.accentFill.opacity(0.55) : contact.color,
          radius: isHot ? 14 : contact.radius, y: isHot ? 0 : contact.y
        )
        .shadow(color: isHot ? .clear : ambient.color, radius: ambient.radius, y: ambient.y)
      VStack(spacing: 3) {
        if let symbol = item.systemImage {
          Image(systemName: symbol).font(.title3.weight(.medium)).accessibilityHidden(true)
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
    .scaleEffect(isHot && !reduceMotion ? 1.04 : 1)
    .zIndex(isHot ? 1 : 0)
    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: isHot)
    .modifier(SegmentClick(enabled: mode == .click, item: item, hovered: $hovered, onSelect: onSelect))
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

  /// The centre pill names the lit segment, or shows `centerText` when nothing is lit.
  private func center(size: CGFloat) -> some View {
    VStack(spacing: 2) {
      Text(litItem?.title.uppercased() ?? centerText)
        .font(
          litItem == nil ? .headline.monospacedDigit() : .system(.subheadline, design: .rounded).weight(.bold)
        )
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .contentTransition(.opacity)
      Text(kind.title).font(.caption2).foregroundStyle(DesignTokens.Palette.secondaryText)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .frame(maxWidth: size * 0.34)
    .glassPanel(cornerRadius: 999)
    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: litID)
    .accessibilityElement(children: .combine)
  }
}

/// Hover and click behaviour for a segment in `.click` mode.
private struct SegmentClick: ViewModifier {
  let enabled: Bool
  let item: WheelItem
  @Binding var hovered: String?
  let onSelect: (WheelItem, [URL]) -> Void

  func body(content: Content) -> some View {
    if enabled {
      content
        .onHover { inside in
          if inside {
            if hovered != item.id, item.isEnabled { WheelFeedback.hover() }
            hovered = item.id
          } else if hovered == item.id {
            hovered = nil
          }
        }
        .onTapGesture { if item.isEnabled { onSelect(item, []) } }
    } else {
      content
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
