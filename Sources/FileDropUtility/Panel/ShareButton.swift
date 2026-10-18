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
    button.bezelStyle = .rounded
    button.controlSize = .small
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
