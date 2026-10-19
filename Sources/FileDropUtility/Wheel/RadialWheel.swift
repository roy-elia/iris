import DropCore
import SwiftUI
import UniformTypeIdentifiers

/// The wheel's proportions, designed at a 252pt diameter and scaled from there. Shared
/// with the AppKit drop target, so the segment that lights up is the one under the pointer.
enum WheelGeometry {
  static let design: CGFloat = 252
  /// Petal inner radius over disc radius.
  static let innerRatio: CGFloat = 50.0 / 126

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

/// A petal: an annular sector with evenly rounded corners. Its angles and radii animate,
/// so a lit petal can swell smoothly.
struct PetalShape: Shape {
  var startAngle: Angle
  var endAngle: Angle
  var innerRadius: CGFloat
  var outerRadius: CGFloat
  var gap: CGFloat
  var cornerRadius: CGFloat

  var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<CGFloat, CGFloat>> {
    get {
      AnimatablePair(
        AnimatablePair(startAngle.radians, endAngle.radians), AnimatablePair(innerRadius, outerRadius))
    }
    set {
      startAngle = .radians(newValue.first.first)
      endAngle = .radians(newValue.first.second)
      innerRadius = newValue.second.first
      outerRadius = newValue.second.second
    }
  }

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let r = max(0, min(cornerRadius, (outerRadius - innerRadius) / 2 - 0.5))
    let outer = outerRadius - r
    let inner = innerRadius + r
    guard outer > inner, inner > 0 else { return Path() }
    // Shrink the sector by the corner radius on every side, then grow it back with a
    // round-joined stroke: the result has true circular corners.
    let edgeInset = gap / 2 + r
    let outerInset = Angle(radians: Double(edgeInset / outer))
    let innerInset = Angle(radians: Double(edgeInset / inner))
    guard startAngle + innerInset < endAngle - innerInset else { return Path() }
    var core = Path()
    core.addArc(
      center: center, radius: outer, startAngle: startAngle + outerInset, endAngle: endAngle - outerInset,
      clockwise: false)
    core.addArc(
      center: center, radius: inner, startAngle: endAngle - innerInset, endAngle: startAngle + innerInset,
      clockwise: true)
    core.closeSubpath()
    guard r > 0 else { return core }
    return core.union(core.strokedPath(StrokeStyle(lineWidth: r * 2, lineCap: .round, lineJoin: .round)))
  }
}

/// The radial action wheel: rounded petals on a dark Liquid Glass disc, around a recessed
/// centre well with a label pill. The petal under the pointer fills with an accent
/// gradient, swells past the rim and leans toward the pointer. The wheel springs open
/// from a third of its size, and the labels fade in just after.
///
/// In `.click` mode the wheel tracks the pointer itself. In `.drop` mode an AppKit drop
/// target tracks the drag and passes the lit segment and pointer in.
/// Colours for one wheel theme.
struct WheelPalette {
  var disc: Color
  var discTint: Color
  var reducedDisc: Color
  var petalTop: Color
  var petalBottom: Color
  var label: Color
  var disabledLabel: Color
  var hotColors: [Color]
  var hotLabel: Color
  var hotGlow: Color
  var well: Color
  var wellShadow: Color
  var pill: Color
  var pillText: Color

  init(_ theme: WheelTheme) {
    let hot = [DesignTokens.Palette.wheelHotTop, DesignTokens.Palette.wheelHotBottom]
    switch theme {
    case .dark:
      self.init(
        disc: .black.opacity(0.5), discTint: .black.opacity(0.45), reducedDisc: Color(white: 0.11),
        petalTop: .white.opacity(0.11), petalBottom: .white.opacity(0.06), label: .white,
        disabledLabel: .white.opacity(0.4), hotColors: hot, hotLabel: .white, hotGlow: hot[1],
        well: .black.opacity(0.42), wellShadow: .black.opacity(0.7), pill: .white.opacity(0.09),
        pillText: .white)
    case .light:
      self.init(
        disc: .white.opacity(0.45), discTint: .white.opacity(0.5), reducedDisc: Color(white: 0.93),
        petalTop: .white.opacity(0.7), petalBottom: .white.opacity(0.45), label: .black.opacity(0.82),
        disabledLabel: .black.opacity(0.3), hotColors: hot, hotLabel: .white, hotGlow: hot[1],
        well: .white.opacity(0.6), wellShadow: .black.opacity(0.22), pill: .black.opacity(0.06),
        pillText: .black.opacity(0.85))
    case .tinted:
      self.init(
        disc: hot[1].opacity(0.55), discTint: hot[0].opacity(0.5), reducedDisc: hot[1],
        petalTop: .white.opacity(0.16), petalBottom: .white.opacity(0.08), label: .white,
        disabledLabel: .white.opacity(0.45), hotColors: [.white, .white.opacity(0.84)], hotLabel: hot[1],
        hotGlow: .white, well: .black.opacity(0.28), wellShadow: .black.opacity(0.55),
        pill: .white.opacity(0.14),
        pillText: .white)
    }
  }

  init(
    disc: Color, discTint: Color, reducedDisc: Color, petalTop: Color, petalBottom: Color, label: Color,
    disabledLabel: Color, hotColors: [Color], hotLabel: Color, hotGlow: Color, well: Color, wellShadow: Color,
    pill: Color, pillText: Color
  ) {
    self.disc = disc
    self.discTint = discTint
    self.reducedDisc = reducedDisc
    self.petalTop = petalTop
    self.petalBottom = petalBottom
    self.label = label
    self.disabledLabel = disabledLabel
    self.hotColors = hotColors
    self.hotLabel = hotLabel
    self.hotGlow = hotGlow
    self.well = well
    self.wellShadow = wellShadow
    self.pill = pill
    self.pillText = pillText
  }
}

private struct WheelThemeKey: EnvironmentKey {
  static let defaultValue: WheelTheme? = nil
}

extension EnvironmentValues {
  /// Overrides the wheel theme from Settings (previews and the theme picker use this).
  var wheelTheme: WheelTheme? {
    get { self[WheelThemeKey.self] }
    set { self[WheelThemeKey.self] = newValue }
  }
}

struct RadialWheel: View {
  enum Mode { case click, drop }

  let kind: WheelKind
  let items: [WheelItem]
  let centerText: String
  let mode: Mode
  /// `.drop` mode: the lit segment, set by `WheelDropView`.
  var hotID: String? = nil
  /// `.drop` mode: the pointer relative to the wheel's centre, y-down.
  var pointer: CGPoint? = nil
  /// Changing this replays the opening animation.
  var introRevision = 0
  let onSelect: (WheelItem, [URL]) -> Void

  @State private var hoverPoint: CGPoint?
  @State private var opened = true
  @State private var labelsShown = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.wheelTheme) private var themeOverride

  private var palette: WheelPalette { WheelPalette(themeOverride ?? AppModel.shared.settings.wheelTheme) }

  var body: some View {
    GeometryReader { geo in
      let d = min(geo.size.width, geo.size.height)
      wheel(diameter: d)
        .frame(width: d, height: d)
        .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }
    .aspectRatio(1, contentMode: .fit)
    // The wheel is a heads-up control, dark in either appearance, as in the reference.
    .environment(\.colorScheme, .dark)
    .onChange(of: introRevision, initial: true) { playIntro() }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(kind.longTitle) wheel")
  }

  // MARK: Layout

  private func wheel(diameter d: CGFloat) -> some View {
    let s = d / WheelGeometry.design
    let pointer = mode == .drop ? self.pointer : hoverPoint
    let lit = litIndex(diameter: d, pointer: pointer)
    return ZStack {
      disc(diameter: d, scale: s)
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        petal(item, index: index, isHot: index == lit, diameter: d, scale: s, pointer: pointer)
      }
      center(scale: s, litItem: lit.map { items[$0] })
    }
    .scaleEffect(opened ? 1 : 0.3)
    .opacity(opened ? 1 : 0)
    .contentShape(Circle())
    .modifier(
      ClickTracking(enabled: mode == .click, diameter: d, hoverPoint: $hoverPoint) { point in
        guard let index = WheelGeometry.segment(at: point, outerRadius: d / 2, count: items.count),
          items[index].isEnabled
        else { return }
        onSelect(items[index], [])
      }
    )
    .onChange(of: lit) { old, new in
      if mode == .click, let new, new != old { WheelFeedback.hover() }
    }
  }

  private func litIndex(diameter d: CGFloat, pointer: CGPoint?) -> Int? {
    let index: Int?
    switch mode {
    case .drop: index = items.firstIndex { $0.id == hotID }
    case .click:
      index = pointer.flatMap { WheelGeometry.segment(at: $0, outerRadius: d / 2, count: items.count) }
    }
    guard let index, items[index].isEnabled else { return nil }
    return index
  }

  // MARK: Pieces

  private func disc(diameter d: CGFloat, scale s: CGFloat) -> some View {
    Group {
      if reduceTransparency {
        Circle().fill(palette.reducedDisc)
      } else {
        Circle()
          .fill(palette.disc)
          .glassEffect(.regular.tint(palette.discTint), in: Circle())
      }
    }
    .shadow(color: .black.opacity(0.35), radius: 2 * s, y: 1)
    .shadow(color: .black.opacity(0.40), radius: 26 * s, y: 12 * s)
  }

  @ViewBuilder
  private func petal(
    _ item: WheelItem, index: Int, isHot: Bool, diameter d: CGFloat, scale s: CGFloat, pointer: CGPoint?
  ) -> some View {
    let step = 360.0 / Double(items.count)
    let start = WheelGeometry.startAngle(index: index, count: items.count)
    let widen = Angle(degrees: isHot ? 2.5 : 0)
    let inner = 50 * s
    let outer = d / 2 - 8 * s + (isHot ? 12 * s : 0)
    let shape = PetalShape(
      startAngle: start - widen, endAngle: start + .degrees(step) + widen, innerRadius: inner,
      outerRadius: outer, gap: 7 * s, cornerRadius: 13 * s)
    let mid = Angle(degrees: start.degrees + step / 2)
    let labelRadius = (inner + outer) / 2
    let labelOffset = CGSize(width: cos(mid.radians) * labelRadius, height: sin(mid.radians) * labelRadius)
    let lean = isHot ? leanOffset(toward: pointer, from: labelOffset, limit: 7 * s) : .zero

    ZStack {
      if isHot {
        shape
          .fill(
            LinearGradient(
              colors: palette.hotColors, startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .overlay(
            // A soft specular sheen across the top, as on a lit glass petal.
            shape.fill(
              RadialGradient(
                colors: [.white.opacity(0.14), .clear], center: .init(x: 0.35, y: 0.2), startRadius: 0,
                endRadius: d * 0.22))
          )
          .shadow(color: palette.hotGlow.opacity(0.65), radius: 16 * s)
      } else {
        shape.fill(
          LinearGradient(
            colors: [
              palette.petalTop.opacity(item.isEnabled ? 1 : 0.55),
              palette.petalBottom.opacity(item.isEnabled ? 1 : 0.5),
            ],
            startPoint: .top, endPoint: .bottom))
      }
      VStack(spacing: 3 * s) {
        if let symbol = item.systemImage {
          Image(systemName: symbol)
            .font(.system(size: 13 * s, weight: .semibold))
            .accessibilityHidden(true)
        }
        Text(item.title)
          .font(.system(size: 8 * s, weight: .bold))
          .tracking(0.4 * s)
          .textCase(.uppercase)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .minimumScaleFactor(0.75)
      }
      .foregroundStyle(isHot ? palette.hotLabel : (item.isEnabled ? palette.label : palette.disabledLabel))
      .frame(width: 64 * s)
      .offset(labelOffset)
      .opacity(labelsShown ? 1 : 0)
      .allowsHitTesting(false)
    }
    .offset(lean)
    .zIndex(isHot ? 1 : 0)
    .animation(
      reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.6), value: isHot
    )
    .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.82), value: lean)
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

  /// The lit petal leans a few points toward the pointer, like it's being pulled.
  private func leanOffset(toward pointer: CGPoint?, from anchor: CGSize, limit: CGFloat) -> CGSize {
    guard let pointer, !reduceMotion else { return .zero }
    let dx = (pointer.x - anchor.width) * 0.14
    let dy = (pointer.y - anchor.height) * 0.14
    let length = hypot(dx, dy)
    guard length > limit else { return CGSize(width: dx, height: dy) }
    return CGSize(width: dx / length * limit, height: dy / length * limit)
  }

  /// A recessed well with a pill naming the lit petal, or showing `centerText`.
  private func center(scale s: CGFloat, litItem: WheelItem?) -> some View {
    ZStack {
      Circle()
        .fill(palette.well.shadow(.inner(color: palette.wellShadow, radius: 4 * s, y: 1.5 * s)))
        .frame(width: 84 * s, height: 84 * s)
      Text(litItem?.title ?? centerText)
        .font(.system(size: 9 * s, weight: .bold))
        .tracking(0.3 * s)
        .textCase(litItem == nil ? nil : .uppercase)
        .foregroundStyle(palette.pillText)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 10 * s)
        .frame(width: 74 * s, height: 30 * s)
        .background(palette.pill, in: Capsule(style: .continuous))
        .contentTransition(.opacity)
        .animation(.easeOut(duration: 0.12), value: litItem?.id)
        .opacity(labelsShown ? 1 : 0)
    }
    .allowsHitTesting(false)
    .accessibilityElement(children: .combine)
  }

  // MARK: Motion

  private func playIntro() {
    guard !reduceMotion else {
      opened = true
      labelsShown = true
      return
    }
    var reset = Transaction()
    reset.disablesAnimations = true
    withTransaction(reset) {
      opened = false
      labelsShown = false
    }
    DispatchQueue.main.async {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.66)) { opened = true }
      withAnimation(.easeOut(duration: 0.14).delay(0.09)) { labelsShown = true }
    }
  }
}

/// Pointer tracking and clicks for a `.click` mode wheel. Points are relative to the
/// wheel's centre, y-down.
private struct ClickTracking: ViewModifier {
  let enabled: Bool
  let diameter: CGFloat
  @Binding var hoverPoint: CGPoint?
  let onClick: (CGPoint) -> Void

  func body(content: Content) -> some View {
    if enabled {
      content
        .onContinuousHover(coordinateSpace: .local) { phase in
          switch phase {
          case .active(let location):
            hoverPoint = CGPoint(x: location.x - diameter / 2, y: location.y - diameter / 2)
          case .ended:
            hoverPoint = nil
          }
        }
        .onTapGesture(coordinateSpace: .local) { location in
          onClick(CGPoint(x: location.x - diameter / 2, y: location.y - diameter / 2))
        }
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
