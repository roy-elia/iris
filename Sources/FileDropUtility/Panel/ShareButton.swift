import AppKit
import SwiftUI

/// A Share button that opens the system sharing picker anchored to itself.
/// SwiftUI's `ShareLink` does not present from a `MenuBarExtra` window, so this wraps an
/// `NSButton` and shows `NSSharingServicePicker` directly.
struct ShareButton: NSViewRepresentable {
  let items: [URL]

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      title: "Share", target: context.coordinator, action: #selector(Coordinator.share(_:)))
    // The AppKit counterpart of SwiftUI's .bordered button style, matching the buttons beside it.
    button.bezelStyle = .push
    button.setAccessibilityIdentifier("share")
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.items = items
    button.isEnabled = !items.isEmpty
  }

  func makeCoordinator() -> Coordinator { Coordinator(items: items) }

  final class Coordinator: NSObject {
    var items: [URL]

    init(items: [URL]) {
      self.items = items
    }

    @MainActor @objc func share(_ sender: NSButton) {
      let picker = NSSharingServicePicker(items: items)
      picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
  }
}

/// Shows the system sharing picker for files dropped on the wheel. The wheel has closed
/// by then, so the picker hangs off a small invisible panel under the pointer.
@MainActor
enum SharePresenter {
  /// Replaces presentation (the self-test checks routing without opening a picker).
  static var presentOverride: (([URL]) -> Void)?

  private static var anchor: NSPanel?
  private static let delegate = Delegate()

  static func share(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    if let presentOverride { return presentOverride(urls) }
    close()
    let size = NSSize(width: 2, height: 2)
    let point = NSEvent.mouseLocation
    let panel = NSPanel(
      contentRect: NSRect(origin: NSPoint(x: point.x - 1, y: point.y - 1), size: size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.animationBehavior = AppWindowAnimation.behavior
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    let view = NSView(frame: NSRect(origin: .zero, size: size))
    panel.contentView = view
    panel.orderFrontRegardless()
    anchor = panel
    NSApp.activate()
    let picker = NSSharingServicePicker(items: urls)
    picker.delegate = delegate
    picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
  }

  static func close() {
    anchor?.orderOut(nil)
    anchor = nil
  }

  final class Delegate: NSObject, NSSharingServicePickerDelegate {
    /// Called with the chosen service, or nil when the picker is dismissed.
    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
      MainActor.assumeIsolated { SharePresenter.close() }
    }
  }
}
