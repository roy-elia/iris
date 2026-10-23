import DropCore
import SwiftUI
import UniformTypeIdentifiers

/// The wheel's proportions, designed at a 252pt diameter and scaled from there. Shared
/// with the AppKit drop target, so the segment that lights up is the one under the pointer.
enum WheelGeometry {
  static let design: CGFloat = 252
  /// The drag-and-hold wheel's size on screen: large enough that its 8.4pt design labels
  /// render at 10pt, macOS's minimum text size.
  static let onScreen: CGFloat = 250
  /// The largest a drag-and-hold wheel opens, for the busiest wheels.
  static let maxOnScreen: CGFloat = 330

  /// The drag-and-hold wheel's size for `count` petals. Up to 10 petals use `onScreen`; each
  /// petal past that adds 25pt, so a 12-petal wheel opens at 350pt and a 14-petal one at 400pt,
  /// which leaves the narrow petals room for a symbol and a 10pt SF Pro label.
  static func diameter(forItemCount count: Int) -> CGFloat {
    min(onScreen + 25 * CGFloat(max(count - 10, 0)), maxOnScreen)
  }

  /// Where a petal's label sits and how wide it may be, so it stays inside the petal.
  struct LabelFit {
    /// Distance from the wheel's centre to the centre of the label stack.
    var radius: CGFloat
    /// The widest the text line can be without crossing the petal's edge.
    var width: CGFloat
  }

  /// Searches along petal `index`'s centre line for the spot where an axis-aligned label
  /// (an optional symbol above a text line) gets the widest text line inside the petal.
  /// Petals near the top and bottom are narrow across, so a fixed-width label spills out
  /// of them even when it fits the petals on the sides.
  static func labelFit(
    index: Int, count: Int, innerRadius: CGFloat, outerRadius: CGFloat, gap: CGFloat,
    symbolSize: CGSize?, spacing: CGFloat, textHeight: CGFloat, needed: CGFloat = .infinity
  ) -> LabelFit {
    let step = 2 * Double.pi / Double(max(count, 1))
    let start = -Double.pi / 2 - step / 2 + step * Double(index)
    let mid = start + step / 2
    let edges = [start, start + step]
    let padding: CGFloat = 1.5
    let stackHeight = (symbolSize.map { $0.height + spacing } ?? 0) + textHeight

    /// True when every corner of the rectangle lies inside the petal, `padding` clear of its edges.
    func contains(center c: CGPoint, size: CGSize) -> Bool {
      for sx in [-1.0, 1.0] {
        for sy in [-1.0, 1.0] {
          let x = c.x + sx * size.width / 2
          let y = c.y + sy * size.height / 2
          let r = hypot(x, y)
          guard r >= innerRadius + padding, r <= outerRadius - padding else { return false }
          var offset = (atan2(Double(y), Double(x)) - mid).truncatingRemainder(dividingBy: 2 * .pi)
          if offset > .pi { offset -= 2 * .pi } else if offset < -.pi { offset += 2 * .pi }
          guard abs(offset) <= step / 2 else { return false }
          for edge in edges where abs(-sin(edge) * x + cos(edge) * y) < gap / 2 + padding { return false }
        }
      }
      return true
    }

    // Labels sit in the middle of the petal. A label moves off the mid radius only when its
    // line doesn't fit there, and then only as far as it must; one that fits nowhere goes
    // where the petal is widest.
    let middle = (innerRadius + outerRadius) / 2
    let tolerance = (outerRadius - innerRadius) * 0.3
    var best = LabelFit(radius: middle, width: 0)
    var closest: LabelFit?
    let samples = 40
    for pass in 0..<2 where closest == nil && (pass == 0 || needed.isFinite || best.width == 0) {
    for k in 0...samples {
      let radius = innerRadius + (outerRadius - innerRadius) * CGFloat(k) / CGFloat(samples)
      if pass == 0, abs(radius - middle) > tolerance { continue }
      let c = CGPoint(x: cos(mid) * radius, y: sin(mid) * radius)
      if let symbolSize {
        let symbolCenter = CGPoint(x: c.x, y: c.y - stackHeight / 2 + symbolSize.height / 2)
        guard contains(center: symbolCenter, size: symbolSize) else { continue }
      }
      let textCenter = CGPoint(x: c.x, y: c.y + stackHeight / 2 - textHeight / 2)
      // A narrower line always fits where a wider one does, so binary-search the width.
      var low: CGFloat = 0
      var high = outerRadius * 2
      guard contains(center: textCenter, size: CGSize(width: 1, height: textHeight)) else { continue }
      while high - low > 0.5 {
        let width = (low + high) / 2
        if contains(center: textCenter, size: CGSize(width: width, height: textHeight)) {
          low = width
        } else {
          high = width
        }
      }
      let width = low
      if width > best.width { best = LabelFit(radius: radius, width: width) }
      if width >= needed, abs(radius - middle) < abs((closest?.radius ?? .infinity) - middle) {
        closest = LabelFit(radius: radius, width: width)
      }
    }
    }
    return closest ?? best
  }
  /// The smallest a wheel label may render, from the macOS minimum (typography guidelines).
  static let minimumLabelSize: CGFloat = 10
  /// Petal inner radius over disc radius. Busy wheels (more than 10 petals) use a smaller
  /// centre well, which gives their narrow petals more length and width for a label.
  static func innerRatio(forCount count: Int) -> CGFloat { (count > 10 ? 38.0 : 50.0) / 126 }

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
      dx: point.x, dy: point.y, outerRadius: outerRadius, count: count, innerRatio: innerRatio(forCount: count))
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

  var animatableData:
    AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>
  {
    get {
      AnimatablePair(
        AnimatablePair(startAngle.radians, endAngle.radians),
        AnimatablePair(innerRadius, AnimatablePair(outerRadius, cornerRadius)))
    }
    set {
      startAngle = .radians(newValue.first.first)
      endAngle = .radians(newValue.first.second)
      innerRadius = newValue.second.first
      outerRadius = newValue.second.second.first
      cornerRadius = newValue.second.second.second
    }
  }

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    // The corner radius must also fit the petal's angular width at its inner edge, or narrow
    // petals on busy wheels would collapse to nothing.
    let span = CGFloat((endAngle - startAngle).radians)
    let angularLimit = span < 2 ? (span * innerRadius - gap) / (2 - span) * 0.9 : .infinity
    let r = max(0, min(cornerRadius, (outerRadius - innerRadius) / 2 - 0.5, angularLimit))
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

/// The radial action wheel: rounded petals on a Liquid Glass disc, around a centre well with
/// a label. The petal under the pointer turns lilac, swells past the rim and
/// leans toward the pointer. The wheel springs open from a third of its size, and the labels
/// fade in just after. Everything is drawn with system glass, fills and colours, so it
/// follows light and dark, Increase Contrast and Reduce Transparency.
///
/// In `.click` mode the wheel tracks the pointer itself. In `.drop` mode an AppKit drop
/// target tracks the drag and passes the lit segment and pointer in.
extension WheelTheme {
  /// The disc's glass: the theme setting picks one of the system variants.
  var glass: Glass {
    switch self {
    case .dark: .regular
    case .light: .clear
    case .tinted: .regular
    }
  }
}

/// The wheel's hover lilac. The wheel's panel never becomes key, and the system drops glass
/// tints on inactive windows, so lilac is drawn as a fill over the lilac glass rather than as
/// a tint alone. The lilac is light, so the lit petal's label is deep ink, not white.
enum WheelBrand {
  static let color = DesignTokens.Palette.brand
  /// Deep ink for the lit petal's label and symbol: 7.6:1 on the dark wheel's lilac, 6.0:1 on
  /// the light wheel's.
  static let ink = DesignTokens.Palette.lilacInk

  /// A true lilac, a little lighter on the dark wheel (#B9A6FA) so it glows against the
  /// near-black petals, and a little richer on the light wheel (#A78BFA) so it reads on frost.
  static func lilac(light: Bool) -> Color {
    light ? hex(0xA78BFA) : hex(0xB9A6FA)
  }

  /// Slightly deeper at the lower left, lighter at the upper right, like light on glass.
  static func gradient(light: Bool) -> LinearGradient {
    LinearGradient(
      colors: light
        ? [hex(0x9D85F2), hex(0xA78BFA), hex(0xB09CF7)] : [hex(0xAD97F8), hex(0xB9A6FA), hex(0xC4B5FD)],
      startPoint: .bottomLeading, endPoint: .topTrailing)
  }

  private static func hex(_ v: UInt32) -> Color {
    Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
  }
}

/// The wheel's surfaces in each appearance. Dark: a cool dark glass disc, near-black petals and
/// a lighter hub ring, matching the dark system UI. Light: white frost on the same glass, pale
/// lilac-grey petals and dark labels. Labels stay above 12:1 on the petals in both.
struct WheelSurface {
  let disc: Color
  let discOpacity: Double
  let petal: Color
  let petalOpacity: Double
  let hubRing: Color
  let hubWell: Color
  /// Enabled labels, symbols, the centre pill's text and the current page dot.
  let label: Color
  /// The fine inner ring and the well's edge.
  let hairline: Color

  static let dark = WheelSurface(
    disc: Color(red: 0.18, green: 0.17, blue: 0.24), discOpacity: 0.72,
    petal: Color(red: 0.12, green: 0.11, blue: 0.16), petalOpacity: 0.82,
    hubRing: Color(red: 0.27, green: 0.25, blue: 0.34), hubWell: Color(red: 0.13, green: 0.12, blue: 0.18),
    label: .white, hairline: .white.opacity(0.07))

  static let light = WheelSurface(
    disc: .white, discOpacity: 0.5,
    petal: Color(red: 0.957, green: 0.949, blue: 0.973), petalOpacity: 0.78,
    hubRing: Color(red: 0.894, green: 0.878, blue: 0.933),
    hubWell: Color(red: 0.957, green: 0.949, blue: 0.973),
    label: Color(red: 0.114, green: 0.114, blue: 0.122), hairline: .black.opacity(0.08))
}

/// The wheel's rim and sheen, shared by both appearances.
enum WheelSlate {

  /// A light edge that catches the top-left and fades toward the bottom-right.
  static func rim(_ strength: Double = 1) -> LinearGradient {
    LinearGradient(
      colors: [.white.opacity(0.42 * strength), .white.opacity(0.05 * strength), .white.opacity(0.2 * strength)],
      startPoint: .topLeading, endPoint: .bottomTrailing)
  }
  /// A faint highlight along a petal's top edge.
  static let petalSheen = LinearGradient(
    colors: [.white.opacity(0.16), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
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
  /// Every segment given; a wheel with more than `WheelPaging.perPage` shows them a page at
  /// a time. In `.drop` mode the overlay passes one page already, and the page position.
  let allItems: [WheelItem]
  let centerText: String
  let mode: Mode
  /// `.drop` mode: the lit segment, set by `WheelDropView`.
  var hotID: String? = nil
  /// `.drop` mode: the pointer relative to the wheel's centre, y-down.
  var pointer: CGPoint? = nil
  /// Changing this replays the opening animation.
  var introRevision = 0
  /// False when this wheel replaces another in place (a modifier switch): it appears without
  /// replaying the opening animation.
  var playsIntro = true
  /// `.drop` mode: which page the overlay shows, and how many pages there are.
  var pageIndex = 0
  var pageCount = 1
  let onSelect: (WheelItem, [URL]) -> Void

  init(
    kind: WheelKind, items: [WheelItem], centerText: String, mode: Mode, hotID: String? = nil,
    pointer: CGPoint? = nil, introRevision: Int = 0, playsIntro: Bool = true, pageIndex: Int = 0,
    pageCount: Int = 1, onSelect: @escaping (WheelItem, [URL]) -> Void
  ) {
    self.kind = kind
    self.allItems = items
    self.centerText = centerText
    self.mode = mode
    self.hotID = hotID
    self.pointer = pointer
    self.introRevision = introRevision
    self.playsIntro = playsIntro
    self.pageIndex = pageIndex
    self.pageCount = pageCount
    self.onSelect = onSelect
  }

  /// `.click` mode: the page showing; tapping the hub turns it.
  @State private var clickPage = 0

  private var pagesList: [[WheelItem]] { WheelPaging.pages(allItems) }
  private var currentPage: Int { mode == .click ? min(clickPage, pagesList.count - 1) : pageIndex }
  private var totalPages: Int { max(pageCount, pagesList.count) }
  private var items: [WheelItem] { pagesList[min(currentPage, pagesList.count - 1)] }

  @State private var hoverPoint: CGPoint?
  @State private var opened = true
  @State private var labelsShown = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.wheelTheme) private var themeOverride
  @Environment(\.colorScheme) private var colorScheme

  private var theme: WheelTheme { themeOverride ?? AppModel.shared.settings.wheelTheme }
  /// The Regular wheel follows the system appearance. Clear glass keeps its dimming layer and
  /// light labels, and Tinted keeps its lilac disc, so both stay dark.
  private var isLight: Bool { theme == .dark && colorScheme == .light }
  private var surface: WheelSurface { isLight ? .light : .dark }

  var body: some View {
    GeometryReader { geo in
      let d = min(geo.size.width, geo.size.height)
      wheel(diameter: d)
        .frame(width: d, height: d)
        .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }
    .aspectRatio(1, contentMode: .fit)
    .environment(\.colorScheme, isLight ? .light : .dark)
    .onChange(of: introRevision, initial: true) { playIntro() }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(kind.longTitle) wheel")
  }

  // MARK: Layout

  /// Petal labels and symbols scale with the wheel, except on busy wheels (more than 10
  /// petals): those open larger to make room, so their type stays at the 300pt wheel's size
  /// and the extra diameter becomes space between neighbouring labels.
  private func textScale(_ s: CGFloat) -> CGFloat {
    items.count > 10 ? min(s, WheelGeometry.onScreen / WheelGeometry.design) : s
  }

  /// How the wheel's labels are set so every one stays inside its petal. Every label keeps
  /// its symbol and the system's standard SF Pro width; busy wheels open larger instead.
  struct LabelLayout {
    var fits: [WheelGeometry.LabelFit]
    /// One text scale for every label on the wheel, so the longest title still fits its
    /// petal on one line and all labels stay the same size.
    var fontScale: CGFloat
  }

  private static var layoutCache: [String: LabelLayout] = [:]

  /// Places each label on one line in the middle of its petal, moving it only as far as it
  /// must to fit. The text never goes below `WheelGeometry.minimumLabelSize` before scaling.
  private func labelLayout(diameter d: CGFloat, scale s: CGFloat) -> LabelLayout {
    let key =
      "\(Int(d))|" + items.map { "\($0.title)\($0.systemImage == nil ? "" : "*")" }.joined(separator: "|")
    if let cached = Self.layoutCache[key] { return cached }
    let ts = textScale(s)
    let fontSize = max(WheelGeometry.minimumLabelSize, 8.4 * ts)
    let symbolSide = 13 * ts * 1.25
    let geometry = petalGeometry(diameter: d, scale: s)
    let lineHeight = ceil(fontSize * 1.25)
    let font = NSFont.systemFont(ofSize: fontSize, weight: labelWeight)
    func measure(_ text: String) -> CGFloat {
      let shown = usesCaps ? text.uppercased() : text
      return ceil(
        NSAttributedString(string: shown, attributes: [.font: font, .kern: labelTracking * s]).size().width)
    }
    // Every label sits in the middle of its petal on one line. The whole wheel's text shrinks
    // together just enough for its longest label to fit, so labels never move off centre,
    // wrap or truncate, and all stay one size.
    let fits = items.indices.map { index -> WheelGeometry.LabelFit in
      WheelGeometry.labelFit(
        index: index, count: items.count, innerRadius: geometry.inner, outerRadius: geometry.outer,
        gap: geometry.gap,
        symbolSize: items[index].systemImage != nil ? CGSize(width: symbolSide, height: symbolSide) : nil,
        spacing: 3 * s, textHeight: lineHeight, needed: 0)
    }
    let fontScale = items.indices.reduce(CGFloat(1)) { scale, index in
      min(scale, fits[index].width / max(measure(items[index].title), 1))
    }
    let layout = LabelLayout(fits: fits, fontScale: max(0.7, fontScale))
    Self.layoutCache[key] = layout
    return layout
  }

  /// Petal labels are SF Pro at its standard width. Wheels with room (10 petals or fewer) set
  /// them in bold capitals, like Tangerine's; busy wheels use semibold title case, which is
  /// narrower, so every label still fits its petal.
  private var usesCaps: Bool { items.count <= 10 }
  private var labelWeight: NSFont.Weight { usesCaps ? .bold : .semibold }
  private var labelTracking: CGFloat { usesCaps ? 0.3 : 0 }


  private func petalGeometry(diameter d: CGFloat, scale s: CGFloat) -> (
    inner: CGFloat, outer: CGFloat, gap: CGFloat
  ) {
    ((items.count > 10 ? 38 : 50) * s, d / 2 - 8 * s, (items.count > 10 ? 4.5 : 7) * s)
  }

  private func wheel(diameter d: CGFloat) -> some View {
    let s = d / WheelGeometry.design
    let pointer = mode == .drop ? self.pointer : hoverPoint
    let lit = litIndex(diameter: d, pointer: pointer)
    let labels = labelLayout(diameter: d, scale: s)
    return ZStack {
      disc(diameter: d, scale: s)
      // The petals' glass lives in its own container, so the lit petal's lilac glass is drawn
      // on its own rather than folded into the disc's glass variant.
      GlassEffectContainer(spacing: 0) {
        ZStack {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            petal(
              item, index: index, isHot: index == lit, diameter: d, scale: s, pointer: pointer, labels: labels
            )
          }
          center(scale: s, litItem: lit.map { items[$0] })
        }
      }
    }
    .scaleEffect(opened ? 1 : 0.3)
    .opacity(opened ? 1 : 0)
    .contentShape(Circle())
    .modifier(
      ClickTracking(enabled: mode == .click, diameter: d, hoverPoint: $hoverPoint) { point in
        guard let index = WheelGeometry.segment(at: point, outerRadius: d / 2, count: items.count),
          items[index].isEnabled
        else {
          if totalPages > 1, hypot(point.x, point.y) < d / 2 * WheelGeometry.innerRatio(forCount: items.count) {
            withAnimation(.smooth(duration: 0.2)) { clickPage = (currentPage + 1) % pagesList.count }
          }
          return
        }
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

  /// The disc is the wheel's only glass; the system draws its edge and depth, and makes it
  /// solid under Reduce Transparency.
  /// Clear glass gets a 35% dimming layer, as Apple advises for clear glass over bright
  /// content, and the wheel then draws in its dark appearance so labels stay light.
  private func disc(diameter d: CGFloat, scale s: CGFloat) -> some View {
    ZStack {
      Circle()
        .fill(discFill)
        .glassEffect(theme.glass, in: Circle())
      // The outer bevel and a fine inner ring.
      Circle().strokeBorder(WheelSlate.rim(), lineWidth: 1.6 * s)
      Circle().inset(by: 4.5 * s).strokeBorder(surface.hairline, lineWidth: 1)
    }
  }

  private var discFill: AnyShapeStyle {
    switch theme {
    case .tinted: AnyShapeStyle(WheelBrand.color.opacity(0.6))
    case .light: AnyShapeStyle(WheelSurface.dark.disc.opacity(0.55))
    case .dark: AnyShapeStyle(surface.disc.opacity(surface.discOpacity))
    }
  }

  @ViewBuilder
  private func petal(
    _ item: WheelItem, index: Int, isHot: Bool, diameter d: CGFloat, scale s: CGFloat, pointer: CGPoint?,
    labels: LabelLayout
  ) -> some View {
    let step = 360.0 / Double(items.count)
    let start = WheelGeometry.startAngle(index: index, count: items.count)
    // The lit petal keeps the same concentric shape as the others, its edges following the
    // circle with the same corners, and swells outward past the rim.
    let widen = Angle(degrees: isHot ? 2 : 0)
    let geometry = petalGeometry(diameter: d, scale: s)
    let inner = geometry.inner
    let outer = geometry.outer + (isHot ? 12 * s : 0)
    let shape = PetalShape(
      startAngle: start - widen, endAngle: start + .degrees(step) + widen, innerRadius: inner,
      outerRadius: outer, gap: geometry.gap, cornerRadius: 15 * s)
    let mid = Angle(degrees: start.degrees + step / 2)
    // Measured against the resting petal, so the label doesn't jump when the petal swells.
    let fit = labels.fits[index]
    let labelRadius = fit.radius
    let labelOffset = CGSize(width: cos(mid.radians) * labelRadius, height: sin(mid.radians) * labelRadius)
    let lean = isHot ? leanOffset(toward: pointer, from: labelOffset, limit: 7 * s) : .zero

    ZStack {
      // The lit petal is lilac; the rest use hierarchical fills on the glass. On the lilac
      // disc the lit petal flips to the background colour so it stands out.
      if isHot {
        // A see-through lilac layer over the lilac glass: the glass gives the edge and
        // refraction, and the layer keeps it lilac in the non-activating panel, where the
        // system draws glass tints without colour.
        shape.fill(
          theme == .tinted ? AnyShapeStyle(.background) : AnyShapeStyle(WheelBrand.gradient(light: isLight).opacity(0.92)))
      } else if theme == .tinted {
        shape.fill(.background.opacity(item.isEnabled ? 0.18 : 0.08))
      } else {
        shape.fill(surface.petal.opacity(item.isEnabled ? surface.petalOpacity : 0.5))
        shape.stroke(WheelSlate.petalSheen, lineWidth: 1)
      }
      VStack(spacing: 3 * s) {
        if let symbol = item.systemImage {
          Image(systemName: symbol)
            .font(.system(size: 13 * textScale(s), weight: .semibold))
            .accessibilityHidden(true)
        }
        Text(item.title)
          .font(
            .system(
              size: max(WheelGeometry.minimumLabelSize, 8.4 * textScale(s)) * labels.fontScale,
              weight: usesCaps ? .bold : .semibold)
          )
          .tracking(labelTracking * s * labels.fontScale)
          .textCase(usesCaps ? .uppercase : nil)
          .multilineTextAlignment(.center)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .frame(width: max(fit.width, 1))
      }
      .foregroundStyle(
        isHot
          ? (theme == .tinted
            ? AnyShapeStyle(DesignTokens.Palette.brandInk) : AnyShapeStyle(WheelBrand.ink))
          : (item.isEnabled ? AnyShapeStyle(surface.label) : AnyShapeStyle(surface.label.opacity(0.35)))
      )
      .offset(labelOffset)
      .opacity(labelsShown ? 1 : 0)
      .allowsHitTesting(false)
    }
    .modifier(TealGlass(isOn: isHot && theme != .tinted, shape: shape))
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
    let wellSide: CGFloat = items.count > 10 ? 66 : 84
    return ZStack {
      // A raised ring around a recessed well, then the pill that names the lit petal.
      Circle()
        .fill(surface.hubRing.opacity(0.85))
        .frame(width: wellSide * s, height: wellSide * s)
        .overlay(Circle().strokeBorder(WheelSlate.rim(0.8), lineWidth: 1.2 * s))
      Circle()
        .fill(surface.hubWell.opacity(0.9))
        .frame(width: wellSide * 0.84 * s, height: wellSide * 0.84 * s)
        .overlay(Circle().strokeBorder(surface.hairline, lineWidth: 1))
      Text(litItem?.title ?? centerText)
        .font(.system(size: max(WheelGeometry.minimumLabelSize, 9 * s), weight: .bold))
        .tracking(0.2 * s)
        .textCase(litItem == nil || !usesCaps ? nil : .uppercase)
        .foregroundStyle(surface.label)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 4 * s)
        .frame(width: wellSide * 0.78 * s, height: min(34, wellSide * 0.38) * s)
        .background(surface.petal.opacity(0.95), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(WheelSlate.petalSheen, lineWidth: 1))
        .clipShape(Capsule(style: .continuous))
        .contentTransition(.opacity)
        .animation(.easeOut(duration: 0.12), value: litItem?.id)
        .opacity(labelsShown ? 1 : 0)
      if totalPages > 1 {
        // One dot per page, the current one lit, under the pill.
        HStack(spacing: 4 * s) {
          ForEach(0..<totalPages, id: \.self) { page in
            Circle()
              .fill(surface.label.opacity(page == currentPage ? 0.95 : 0.3))
              .frame(width: 4 * s, height: 4 * s)
          }
        }
        .offset(y: wellSide * 0.3 * s)
        .opacity(labelsShown ? 1 : 0)
        .accessibilityLabel("Page \(currentPage + 1) of \(totalPages)")
      }
    }
    .allowsHitTesting(false)
    .accessibilityElement(children: .combine)
  }

  // MARK: Motion

  private func playIntro() {
    guard playsIntro else {
      opened = true
      labelsShown = true
      return
    }
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

/// Reads dragged text out of drag providers and calls back on the main actor with all of it.
enum TextLoader {
  static func load(_ providers: [NSItemProvider], completion: @escaping @MainActor (String) -> Void) {
    let group = DispatchGroup()
    let collected = Collector()
    for provider in providers where provider.canLoadObject(ofClass: String.self) {
      group.enter()
      _ = provider.loadObject(ofClass: String.self) { text, _ in
        if let text { collected.append(text) }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      MainActor.assumeIsolated { completion(collected.joined) }
    }
  }

  private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ text: String) { lock.withLock { storage.append(text) } }
    var joined: String { lock.withLock { storage.joined(separator: "\n\n") } }
  }
}

/// Lilac Liquid Glass behind the lit petal. Only the lit petal gets a glass effect: an
/// `.identity` glass on the others would still merge them into the disc's glass.
private struct TealGlass: ViewModifier {
  let isOn: Bool
  let shape: PetalShape

  func body(content: Content) -> some View {
    if isOn {
      content.glassEffect(.regular.tint(WheelBrand.lilac(light: false)).interactive(), in: shape)
    } else {
      content
    }
  }
}
