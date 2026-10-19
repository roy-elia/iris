import AppKit
import SwiftUI

/// Opens the app's windows from anywhere, including AppKit code like the drag overlay.
@MainActor
final class WindowManager {
  static let shared = WindowManager()

  private var editors: [URL: NSWindow] = [:]
  private var onboarding: NSWindow?
  private var main: NSWindow?

  /// The main window: Files, History and Settings on floating glass, opened from the
  /// menu's Settings… item.
  func openMain() {
    if let main {
      main.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    var holder: NSWindow?
    let view = PanelView().environmentObject(AppModel.shared)
      .fixedSize()
      .onGeometryChange(for: CGSize.self) {
        $0.size
      } action: { size in
        DispatchQueue.main.async { holder?.fitContent(size) }
      }
    let window = makeWindow(
      content: view, size: NSSize(width: 424, height: 560), title: "File Drop Utility", toolbar: true)
    holder = window
    window.styleMask.remove(.resizable)
    window.isMovableByWindowBackground = true
    track(window) { [weak self] in self?.main = nil }
    main = window
    show(window)
  }

  func openEditor(for url: URL, tool: EditorTool, batch: [URL] = []) {
    if let window = editors[url] {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    let view = EditorView(model: EditorModel(url: url, tool: tool, batch: batch))
      .environmentObject(AppModel.shared)
    let window = makeWindow(
      content: view, size: NSSize(width: 900, height: 640), title: "Edit \(url.lastPathComponent)")
    window.minSize = NSSize(width: 700, height: 480)
    track(window) { [weak self] in self?.editors[url] = nil }
    editors[url] = window
    show(window)
  }

  private var videoEditors: [URL: NSWindow] = [:]
  private var audioEditors: [URL: NSWindow] = [:]
  private var organizers: [URL: NSWindow] = [:]

  func openVideoEditor(for url: URL, tool: VideoTool) {
    if let window = videoEditors[url] {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    let view = VideoEditorView(model: VideoEditorModel(url: url, tool: tool)).environmentObject(
      AppModel.shared)
    let window = makeWindow(
      content: view, size: NSSize(width: 1000, height: 680), title: "Edit \(url.lastPathComponent)")
    window.minSize = NSSize(width: 820, height: 520)
    track(window) { [weak self] in self?.videoEditors[url] = nil }
    videoEditors[url] = window
    show(window)
  }

  func openAudioEditor(for url: URL, tool: AudioTool) {
    if let window = audioEditors[url] {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    let view = AudioEditorView(model: AudioEditorModel(url: url, tool: tool)).environmentObject(
      AppModel.shared)
    let window = makeWindow(
      content: view, size: NSSize(width: 960, height: 460), title: "Edit \(url.lastPathComponent)")
    window.minSize = NSSize(width: 780, height: 380)
    track(window) { [weak self] in self?.audioEditors[url] = nil }
    audioEditors[url] = window
    show(window)
  }

  func openPDFOrganizer(for url: URL) {
    if let window = organizers[url] {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    let view = PDFOrganizerView(model: PDFOrganizerModel(url: url)).environmentObject(AppModel.shared)
    let window = makeWindow(
      content: view, size: NSSize(width: 900, height: 640), title: "Organize \(url.lastPathComponent)")
    window.minSize = NSSize(width: 620, height: 420)
    track(window) { [weak self] in self?.organizers[url] = nil }
    organizers[url] = window
    show(window)
  }

  func openOnboarding() {
    if let onboarding {
      onboarding.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    let view = OnboardingView { [weak self] in self?.onboarding?.close() }
      .environmentObject(AppModel.shared)
    let window = makeWindow(
      content: view, size: NSSize(width: 820, height: 520), title: "Welcome", transparent: true)
    track(window) { [weak self] in self?.onboarding = nil }
    onboarding = window
    show(window)
  }

  private var tools: [String: NSWindow] = [:]

  /// Opens a tool window (one per kind; reopening replaces its contents).
  func openTool<Content: View>(_ id: String, title: String, @ViewBuilder content: () -> Content) {
    tools[id]?.close()
    var window: NSWindow?
    // The content reports its ideal size and the window adopts it on the next turn of the
    // run loop. (Letting the hosting controller drive the window size live, with
    // `.preferredContentSize`, loops forever when the content's height changes after it
    // opens, and AppKit ends the loop with an exception.)
    let view = content()
      .environment(\.dismissToolWindow, { window?.close() })
      .environmentObject(AppModel.shared)
      .fixedSize()
      .onGeometryChange(for: CGSize.self) {
        $0.size
      } action: { size in
        DispatchQueue.main.async { window?.fitContent(size) }
      }
    let made = makeWindow(
      content: view, size: NSSize(width: 460, height: 420), title: title, transparent: true)
    made.styleMask.remove(.resizable)
    made.isMovableByWindowBackground = true
    window = made
    track(made) { [weak self] in self?.tools[id] = nil }
    tools[id] = made
    show(made)
  }

  // MARK: Helpers

  /// A window whose content floats over the desktop. With `transparent`, only the SwiftUI
  /// glass panels are drawn, so the window has no opaque background of its own.
  /// With `toolbar`, the SwiftUI view's `.toolbar` items become the window's own toolbar,
  /// which the system draws in Liquid Glass.
  private func makeWindow<Content: View>(
    content: Content, size: NSSize, title: String, transparent: Bool = false, toolbar: Bool = false
  ) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = title
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.animationBehavior = AppWindowAnimation.behavior
    let hosting = NSHostingController(rootView: AnyView(content))
    hosting.sizingOptions = []
    if toolbar {
      hosting.sceneBridgingOptions = [.toolbars]
      window.toolbarStyle = .unified
    }
    window.contentViewController = hosting
    window.setContentSize(size)
    if transparent {
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = false  // The glass panel draws its own adaptive shadow.
    }
    window.center()
    return window
  }

  private func show(_ window: NSWindow) {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate()
  }

  private var observers: [NSObjectProtocol] = []

  private func track(_ window: NSWindow, onClose: @escaping @MainActor () -> Void) {
    let token = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { _ in
      MainActor.assumeIsolated { onClose() }
    }
    observers.append(token)
  }
}

/// AppKit's open and close zoom effect runs on a GCD worker thread that it holds for the
/// animation's length. When frames stop arriving (with the display asleep, for example) those
/// threads are never returned; enough tool windows and toasts then exhaust GCD's 64 workers and
/// stall anything that needs one, such as ImageIO's AVIF encoder. The app's windows and panels
/// draw their own SwiftUI transitions, so the system effect is turned off.
enum AppWindowAnimation {
  static let behavior: NSWindow.AnimationBehavior = .none
}

extension NSWindow {
  /// Resizes to `size`, keeping the top edge where it is. Ignores sub-point changes.
  func fitContent(_ size: CGSize) {
    let current = contentRect(forFrameRect: frame).size
    guard size.width > 1, size.height > 1,
      abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5
    else { return }
    var rect = frameRect(forContentRect: CGRect(origin: .zero, size: size))
    rect.origin = CGPoint(x: frame.minX, y: frame.maxY - rect.height)
    setFrame(rect, display: true, animate: false)
  }
}
