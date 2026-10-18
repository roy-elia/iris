import AppKit
import DropCore
import SwiftUI

/// Watches for files being dragged anywhere on screen. While a file drag is in progress
/// and Shift, Command or Control is held, it shows the matching wheel under the pointer.
///
/// Uses global mouse monitors plus `NSEvent.modifierFlags`, so it needs no Accessibility
/// or Input Monitoring permission. Key events are never monitored.
@MainActor
final class DragWatcher {
  static let shared = DragWatcher()

  private var monitors: [Any] = []
  private var dragPasteboardCount = NSPasteboard(name: .drag).changeCount
  private var isFileDrag = false
  private let overlay = WheelOverlayController()

  func start() {
    guard monitors.isEmpty else { return }
    let handler: (NSEvent) -> Void = { [weak self] event in
      MainActor.assumeIsolated { self?.handle(event) }
    }
    if let global = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: handler)
    {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
      handler: { event in
        handler(event)
        return event
      })
    {
      monitors.append(local)
    }
  }

  func stop() {
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    overlay.hide()
  }

  private func handle(_ event: NSEvent) {
    guard AppModel.shared.settings.wheelTriggerEnabled else { return }
    switch event.type {
    case .leftMouseDown:
      dragPasteboardCount = NSPasteboard(name: .drag).changeCount
      isFileDrag = false
    case .leftMouseDragged:
      if !isFileDrag {
        let pasteboard = NSPasteboard(name: .drag)
        // A new drag session writes to the drag pasteboard; only react to file drags.
        if pasteboard.changeCount != dragPasteboardCount,
          pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        {
          isFileDrag = true
        }
      }
      guard isFileDrag else { return }
      if let kind = WheelKind.forModifiers(NSEvent.modifierFlags) {
        overlay.show(kind, at: NSEvent.mouseLocation)
      }
    case .leftMouseUp:
      isFileDrag = false
      // Let the drop land before the panel goes away.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [overlay] in
        MainActor.assumeIsolated { overlay.hide() }
      }
    default:
      break
    }
  }
}

/// The floating, non-activating panel that hosts a drop-mode wheel.
@MainActor
final class WheelOverlayController {
  private var panel: NSPanel?
  private var currentKind: WheelKind?
  private let size = NSSize(width: 380, height: 380)

  func show(_ kind: WheelKind, at point: NSPoint) {
    let panel = self.panel ?? makePanel()
    self.panel = panel
    if currentKind != kind {
      currentKind = kind
      let view = RadialWheel(
        kind: kind, items: kind.items(for: []), centerText: "Drop", mode: .drop
      ) { item, urls in
        AppModel.shared.perform(item.command, urls: urls, origin: .overlay)
      }
      .padding(DesignTokens.Spacing.inset)
      panel.contentView = NSHostingView(rootView: view)
    }
    if !panel.isVisible {
      panel.setFrameOrigin(NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
      panel.orderFrontRegardless()
      startReleaseWatch()
    }
  }

  func hide() {
    releaseTimer?.invalidate()
    releaseTimer = nil
    panel?.orderOut(nil)
    currentKind = nil
  }

  private var releaseTimer: Timer?

  /// During another app's drag session the mouse-up often never reaches our monitors, so
  /// also watch the physical button state and close shortly after it's released.
  private func startReleaseWatch() {
    releaseTimer?.invalidate()
    releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        self?.releaseTimer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.hide() }
      }
    }
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    return panel
  }
}

/// A short glass message near the top of the screen, for results of overlay drops.
@MainActor
enum Toast {
  private static var panel: NSPanel?
  private static var hideWork: DispatchWorkItem?

  static func show(result: OperationResult, operation: String) {
    if result.outputs.isEmpty, let failure = result.failures.first {
      show(
        failure.file.isEmpty ? failure.message : "\(failure.file): \(failure.message)", outputs: [],
        isError: true)
    } else {
      let count = result.outputs.count
      let extra = result.failures.isEmpty ? "" : " · \(result.failures.count) failed"
      show("\(operation): saved \(count) file\(count == 1 ? "" : "s")\(extra)", outputs: result.outputs)
    }
  }

  static func show(_ message: String, outputs: [URL], isError: Bool = false) {
    let view = ToastView(message: message, outputs: outputs, isError: isError)
      .padding(DesignTokens.Spacing.inset)
    let host = NSHostingView(rootView: view)
    let size = host.fittingSize
    let panel =
      self.panel
      ?? {
        let p = NSPanel(
          contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
      }()
    self.panel = panel
    panel.contentView = host
    if let screen = NSScreen.main {
      let frame = screen.visibleFrame
      panel.setFrame(
        NSRect(
          x: frame.midX - size.width / 2, y: frame.maxY - size.height - 8, width: size.width,
          height: size.height),
        display: true)
    }
    panel.orderFrontRegardless()
    hideWork?.cancel()
    let work = DispatchWorkItem { MainActor.assumeIsolated { panel.orderOut(nil) } }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
  }
}

private struct ToastView: View {
  let message: String
  let outputs: [URL]
  let isError: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        .foregroundStyle(isError ? DesignTokens.Palette.warningText : DesignTokens.Palette.accentText)
        .accessibilityHidden(true)
      Text(message).font(.callout).foregroundStyle(.primary).lineLimit(2)
      if !outputs.isEmpty {
        Button("Show") { AppModel.shared.reveal(outputs) }
          .buttonStyle(.subtleGlass)
          .accessibilityLabel("Show in Finder")
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .glassPanel(cornerRadius: 999)
    .accessibilityElement(children: .combine)
  }
}
