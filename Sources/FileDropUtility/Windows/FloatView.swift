import AppKit
import DropCore
import QuickLookThumbnailing
import SwiftUI

/// Keeps the Floats: glass tabs docked to the screen edges, each holding a stack of files.
/// Floats are saved, so they come back after a relaunch. Closing one never touches its files.
@MainActor
final class FloatManager: ObservableObject {
  static let shared = FloatManager()

  @Published private(set) var stacks: [FloatStack] = []
  @Published private(set) var expanded: Set<UUID> = []
  @Published private(set) var thumbnails: [URL: NSImage] = [:]
  private var panels: [UUID: NSPanel] = [:]
  private var collapseTasks: [UUID: Task<Void, Never>] = [:]
  private let store: FloatStore

  /// Read by the wheel model, which isn't main-actor isolated.
  nonisolated(unsafe) static var openCount = 0

  static let collapsedSize = CGSize(width: 66, height: 104)
  static let rowHeight: CGFloat = 58
  static let maxVisibleRows = 6

  init(folder: URL = .appSupportFolder) {
    store = FloatStore(fileURL: folder.appendingPathComponent("floats.json"))
  }

  /// Reopens the Floats saved last time.
  func restore() {
    for stack in store.load() { show(stack) }
  }

  // MARK: Stacks

  /// A new Float holding `urls`, placed so it doesn't cover another one.
  func create(with urls: [URL]) {
    let used = stacks.filter { $0.edge == .right }.map(\.position)
    var position = 0.7
    while used.contains(where: { abs($0 - position) < 0.12 }) && position > 0.15 { position -= 0.14 }
    show(FloatStack(urls: urls, edge: .right, position: position))
  }

  /// Adds files to the most recent Float, or makes one.
  func addToLatest(_ urls: [URL]) {
    guard let id = stacks.last?.id else {
      create(with: urls)
      return
    }
    add(urls, to: id)
  }

  func add(_ urls: [URL], to id: UUID) {
    guard let i = stacks.firstIndex(where: { $0.id == id }) else { return }
    stacks[i].add(urls)
    loadThumbnails(for: urls)
    layout(id, animated: true)
    save()
  }

  func remove(_ url: URL, from id: UUID) {
    guard let i = stacks.firstIndex(where: { $0.id == id }) else { return }
    stacks[i].remove(url)
    if stacks[i].isEmpty {
      close(id)
    } else {
      layout(id, animated: true)
      save()
    }
  }

  /// Closes the Float. Its files stay where they are.
  func close(_ id: UUID) {
    panels[id]?.orderOut(nil)
    panels[id] = nil
    stacks.removeAll { $0.id == id }
    expanded.remove(id)
    Self.openCount = stacks.count
    save()
  }

  func closeAll() {
    for id in stacks.map(\.id) { close(id) }
  }

  func stack(_ id: UUID) -> FloatStack? { stacks.first { $0.id == id } }

  // MARK: Hover and moving

  func hover(_ id: UUID, inside: Bool) {
    collapseTasks[id]?.cancel()
    if inside {
      setExpanded(id, true)
    } else {
      // A short grace period, so brushing past the edge doesn't snap it shut.
      collapseTasks[id] = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        self?.setExpanded(id, false)
      }
    }
  }

  private func setExpanded(_ id: UUID, _ value: Bool) {
    guard expanded.contains(id) != value else { return }
    if value { expanded.insert(id) } else { expanded.remove(id) }
    layout(id, animated: true)
  }

  private var dragStart: (mouse: CGPoint, origin: CGPoint)?

  /// Moves the tab with the pointer (screen coordinates, so the moving window doesn't skew it).
  func dragChanged(_ id: UUID) {
    guard let panel = panels[id] else { return }
    let mouse = NSEvent.mouseLocation
    if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
    guard let start = dragStart else { return }
    panel.setFrameOrigin(
      CGPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
  }

  /// Snaps the tab to the nearer edge where it was let go.
  func dragEnded(_ id: UUID) {
    dragStart = nil
    guard let panel = panels[id], let i = stacks.firstIndex(where: { $0.id == id }) else { return }
    let screen = panel.screen ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }
    let snapped = FloatPlacement.snap(CGPoint(x: panel.frame.midX, y: panel.frame.midY), in: visible)
    stacks[i].edge = snapped.edge
    stacks[i].position = snapped.position
    layout(id, animated: true)
    save()
  }

  // MARK: Panels

  private func show(_ stack: FloatStack) {
    stacks.append(stack)
    Self.openCount = stacks.count
    loadThumbnails(for: stack.urls)
    let panel = NSPanel(
      contentRect: CGRect(origin: .zero, size: Self.collapsedSize),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.animationBehavior = AppWindowAnimation.behavior
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.contentView = NSHostingView(rootView: FloatTabView(id: stack.id).environmentObject(self))
    panels[stack.id] = panel
    layout(stack.id, animated: false)
    panel.orderFrontRegardless()
    save()
  }

  func size(for stack: FloatStack, expanded: Bool) -> CGSize {
    guard expanded else { return Self.collapsedSize }
    let rows = min(stack.urls.count, Self.maxVisibleRows)
    return CGSize(width: 236, height: 52 + CGFloat(rows) * Self.rowHeight + 16)
  }

  private func layout(_ id: UUID, animated: Bool) {
    guard let panel = panels[id], let stack = stack(id) else { return }
    let isExpanded = expanded.contains(id)
    let visible =
      (panel.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = FloatPlacement.frame(
      size: size(for: stack, expanded: isExpanded), edge: stack.edge, position: stack.position, in: visible,
      expanded: isExpanded)
    if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.22
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.1)
        panel.animator().setFrame(frame, display: true)
      }
    } else {
      panel.setFrame(frame, display: true)
    }
  }

  private func save() {
    try? store.save(stacks)
  }

  private func loadThumbnails(for urls: [URL]) {
    for url in urls where thumbnails[url] == nil {
      thumbnails[url] = NSWorkspace.shared.icon(forFile: url.path)
      let request = QLThumbnailGenerator.Request(
        fileAt: url, size: CGSize(width: 120, height: 120), scale: 2, representationTypes: .thumbnail)
      QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
        guard let image = rep?.nsImage else { return }
        Task { @MainActor in FloatManager.shared.thumbnails[url] = image }
      }
    }
  }

  #if DEBUG
    /// Shows a stack without a panel, for previews and snapshots.
    func preview(_ stack: FloatStack, expanded isExpanded: Bool, thumbnails images: [URL: NSImage]) {
      stacks = [stack]
      expanded = isExpanded ? [stack.id] : []
      thumbnails = images
    }
  #endif

  // MARK: Menus

  func menu(for url: URL?, in id: UUID) -> NSMenu {
    let menu = NSMenu()
    func item(_ title: String, _ action: @escaping () -> Void) {
      menu.addItem(ClosureMenuItem(title: title, action: action))
    }
    if let url {
      item("Open") { NSWorkspace.shared.open(url) }
      item("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
      item("Copy Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
      }
      menu.addItem(.separator())
      item("Remove from Float") { [weak self] in self?.remove(url, from: id) }
    } else if let stack = stack(id) {
      item("Show All in Finder") { NSWorkspace.shared.activateFileViewerSelecting(stack.urls) }
      menu.addItem(.separator())
    }
    item("Close Float") { [weak self] in self?.close(id) }
    return menu
  }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(title: String, action handler: @escaping () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(fire), keyEquivalent: "")
    target = self
  }

  required init(coder: NSCoder) { fatalError("not used") }

  @objc private func fire() { handler() }
}

// MARK: - Tab view

/// One Float. Collapsed, it's a glass tab tucked against the edge with a paper clip, the top
/// file and a count; hovering opens it into a stack of rows. Drag the tab body to carry
/// every file, a row to carry one, or the grip to move the tab.
struct FloatTabView: View {
  let id: UUID
  @EnvironmentObject var manager: FloatManager
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Collapsed and expanded share one glass identity, so opening morphs a single shape.
  @Namespace private var glassNamespace

  var body: some View {
    Group {
      if let stack = manager.stack(id) {
        let isExpanded = manager.expanded.contains(id)
        GlassEffectContainer(spacing: 8) {
          if isExpanded { expandedView(stack) } else { collapsedView(stack) }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onHover { manager.hover(id, inside: $0) }
    .dropDestination(for: URL.self) { urls, _ in
      manager.add(urls, to: id)
      return !urls.isEmpty
    }
  }

  private func collapsedView(_ stack: FloatStack) -> some View {
    VStack(spacing: 4) {
      Image(systemName: "paperclip")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .rotationEffect(.degrees(stack.edge == .right ? -30 : 30))
      thumb(stack.urls.first, size: 36)
      Text("\(stack.urls.count)")
        .font(.caption2.monospacedDigit().weight(.bold))
        .padding(.horizontal, 7).padding(.vertical, 1)
        .background(.tint, in: Capsule())
        .foregroundStyle(Color(nsColor: .alternateSelectedControlTextColor))
    }
    .padding(.vertical, 10)
    .padding(stack.edge == .right ? .trailing : .leading, FloatPlacement.tuck)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(FileDragSource(urls: stack.urls, menu: { manager.menu(for: nil, in: id) }))
    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .glassEffectID("float", in: glassNamespace)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Float with \(stack.urls.count) file\(stack.urls.count == 1 ? "" : "s")")
    .accessibilityHint("Hover to open. Drag to carry all files.")
  }

  private func expandedView(_ stack: FloatStack) -> some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "line.3.horizontal")
          .font(.caption.weight(.bold))
          .foregroundStyle(Color.secondary)
          .frame(width: 26, height: 26)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
              .onChanged { _ in manager.dragChanged(id) }
              .onEnded { _ in manager.dragEnded(id) }
          )
          .help("Drag to move the Float")
          .accessibilityLabel("Move Float")
        Image(systemName: "paperclip").foregroundStyle(Color.accentColor)
        Text("\(stack.urls.count) file\(stack.urls.count == 1 ? "" : "s")")
          .font(.callout.weight(.semibold))
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .background(FileDragSource(urls: stack.urls, menu: { manager.menu(for: nil, in: id) }))
          .help("Drag to carry all files")
        Button {
          manager.close(id)
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.bold))
        }
        .buttonStyle(.borderless)
        .help("Close Float (files stay where they are)")
        .accessibilityLabel("Close Float")
      }
      ScrollView {
        VStack(spacing: 4) {
          ForEach(stack.urls, id: \.self) { url in row(url) }
        }
      }
      .scrollIndicators(.never)
    }
    .padding(10)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .glassEffectID("float", in: glassNamespace)
    .padding(4)
  }

  private func row(_ url: URL) -> some View {
    HStack(spacing: 10) {
      thumb(url, size: 42)
      VStack(alignment: .leading, spacing: 1) {
        Text(url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
        Text(url.deletingLastPathComponent().lastPathComponent).font(.caption)
          .foregroundStyle(Color.secondary).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 6)
    .frame(height: FloatManager.rowHeight - 4)
    .background(FileDragSource(urls: [url], menu: { manager.menu(for: url, in: id) }))
    // Rows sit on the Float's glass, so they use a system fill rather than more glass.
    .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(url.lastPathComponent)
    .accessibilityHint("Double-click to open. Drag to carry this file.")
    .accessibilityAction(named: "Open") { NSWorkspace.shared.open(url) }
    .accessibilityAction(named: "Remove from Float") { manager.remove(url, from: id) }
  }

  private func thumb(_ url: URL?, size: CGFloat) -> some View {
    Group {
      if let url, let image = manager.thumbnails[url] {
        Image(nsImage: image).resizable().scaledToFit()
      } else {
        Image(systemName: "doc").resizable().scaledToFit().padding(size * 0.2)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }
}

// MARK: - Drag source

/// An AppKit drag source for one or more files, so a single gesture can carry them all
/// (SwiftUI's `onDrag` carries one item). Double-click opens; right-click shows `menu`.
struct FileDragSource: NSViewRepresentable {
  let urls: [URL]
  let menu: () -> NSMenu

  func makeNSView(context: Context) -> SourceView { SourceView() }

  func updateNSView(_ view: SourceView, context: Context) {
    view.urls = urls
    view.makeMenu = menu
  }

  final class SourceView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var makeMenu: (() -> NSMenu)?
    private var downEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
      downEvent = event
      if event.clickCount == 2 {
        for url in urls.prefix(10) { NSWorkspace.shared.open(url) }
      }
    }

    override func mouseDragged(with event: NSEvent) {
      guard let down = downEvent, !urls.isEmpty else { return }
      let distance = hypot(
        event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y
      )
      guard distance > 3 else { return }
      downEvent = nil
      let origin = convert(down.locationInWindow, from: nil)
      let items = urls.enumerated().map { index, url -> NSDraggingItem in
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = FloatManager.shared.thumbnails[url] ?? NSWorkspace.shared.icon(forFile: url.path)
        // Fan the first few icons, like a stack being lifted.
        let offset = CGFloat(min(index, 4)) * 6
        item.setDraggingFrame(
          CGRect(x: origin.x - 24 + offset, y: origin.y - 24 - offset, width: 48, height: 48), contents: icon)
        return item
      }
      beginDraggingSession(with: items, event: event, source: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
      -> NSDragOperation
    {
      context == .outsideApplication ? [.copy, .move, .link, .generic] : [.copy, .generic]
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  }
}
