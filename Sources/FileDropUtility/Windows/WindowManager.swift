import AppKit
import SwiftUI

/// Opens the app's windows from anywhere, including AppKit code like the drag overlay.
@MainActor
final class WindowManager {
  static let shared = WindowManager()

  private var editors: [URL: NSWindow] = [:]
  private var floats: [URL: NSWindow] = [:]
  private var onboarding: NSWindow?

  func openEditor(for url: URL, tool: EditorTool) {
    if let window = editors[url] {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    let view = EditorView(model: EditorModel(url: url, tool: tool))
      .environmentObject(AppModel.shared)
    let window = makeWindow(
      content: view, size: NSSize(width: 900, height: 640), title: "Edit \(url.lastPathComponent)")
    window.minSize = NSSize(width: 700, height: 480)
    track(window) { [weak self] in self?.editors[url] = nil }
    editors[url] = window
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

  // MARK: Helpers

  /// A window whose content floats over the desktop. With `transparent`, only the SwiftUI
  /// glass panels are drawn, so the window has no opaque background of its own.
  private func makeWindow<Content: View>(
    content: Content, size: NSSize, title: String, transparent: Bool = false
  ) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = title
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.contentViewController = NSHostingController(rootView: content)
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
