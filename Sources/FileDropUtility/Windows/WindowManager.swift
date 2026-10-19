import AppKit
import SwiftUI

/// Opens the app's windows from anywhere, including AppKit code like the drag overlay.
@MainActor
final class WindowManager {
  static let shared = WindowManager()

  private var editors: [URL: NSWindow] = [:]
  private var floats: [URL: NSWindow] = [:]
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
    let view = PanelView().environmentObject(AppModel.shared)
    let window = makeWindow(
      content: view, size: NSSize(width: 400, height: 520), title: "File Drop Utility", transparent: true,
      fitsContent: true)
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

  func openFloat(for url: URL) {
    if let window = floats[url] {
      window.orderFrontRegardless()
      return
    }
    let window = makeWindow(
      content: FloatView(url: url), size: NSSize(width: 260, height: 260), title: url.lastPathComponent,
      transparent: true)
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    track(window) { [weak self] in self?.floats[url] = nil }
    floats[url] = window
    window.orderFrontRegardless()
  }

  func closeFloat(for url: URL) {
    floats[url]?.close()
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
    let view = content()
      .environment(\.dismissToolWindow, { window?.close() })
      .environmentObject(AppModel.shared)
    let made = makeWindow(
      content: view, size: NSSize(width: 460, height: 420), title: title, transparent: true, fitsContent: true
    )
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
  private func makeWindow<Content: View>(
    content: Content, size: NSSize, title: String, transparent: Bool = false, fitsContent: Bool = false
  ) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = title
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    let hosting = NSHostingController(rootView: AnyView(content))
    // With `fitsContent`, the window grows and shrinks with the SwiftUI content.
    hosting.sizingOptions = fitsContent ? [.preferredContentSize] : []
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
