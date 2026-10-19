import AppKit
import DropCore
import SwiftUI

/// Watches for files being dragged anywhere on screen and opens the matching wheel while
/// Shift, Command or Control is held.
///
/// It polls the mouse button, modifier keys, Escape and the drag pasteboard on a timer:
/// slowly while idle, at display rate while the button is down. Another app's drag
/// session swallows many mouse events, so polling reacts to a key press even when the
/// pointer is still, where event monitors alone miss it. A mouse-down monitor still
/// records the pasteboard count at the exact moment of the press. The decisions
/// themselves live in `DragTrigger`. No Accessibility or Input Monitoring permission is
/// needed.
@MainActor
final class DragWatcher {
  static let shared = DragWatcher()

  private let idleInterval: TimeInterval = 0.08
  private let activeInterval: TimeInterval = 1.0 / 60
  private var timer: Timer?
  private var isPollingActively = false
  private var monitors: [Any] = []
  private var trigger = DragTrigger<WheelKind>()
  private let dragPasteboard = NSPasteboard(name: .drag)
  private let overlay = WheelOverlayController()
  private var hideWork: DispatchWorkItem?

  func start() {
    guard timer == nil else { return }
    let onMouseDown: (NSEvent) -> Void = { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.trigger.mouseDown(pasteboardChangeCount: self.dragPasteboard.changeCount)
        self.setPolling(active: true)
      }
    }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: onMouseDown) {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(
      matching: .leftMouseDown,
      handler: { event in
        onMouseDown(event)
        return event
      })
    {
      monitors.append(local)
    }
    setPolling(active: false)
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    overlay.hide()
  }

  private func setPolling(active: Bool) {
    guard timer == nil || active != isPollingActively else { return }
    isPollingActively = active
    timer?.invalidate()
    let t = Timer(timeInterval: active ? activeInterval : idleInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    t.tolerance = active ? 0.002 : 0.02
    // .common keeps it firing while menus or drag loops run in this app.
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  private func tick() {
    guard AppModel.shared.settings.wheelTriggerEnabled else {
      if overlay.isVisible { overlay.hide() }
      return
    }
    let buttonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
    let flags = NSEvent.ModifierFlags(
      rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
    let changeCount = dragPasteboard.changeCount
    let types = dragPasteboard.types ?? []
    let sample = DragTrigger<WheelKind>.Sample(
      time: ProcessInfo.processInfo.systemUptime,
      buttonDown: buttonDown,
      pasteboardChangeCount: changeCount,
      mayHoldFiles: types.isEmpty || types.contains(.fileURL),
      kind: WheelKind.forModifiers(flags),
      escapeDown: CGEventSource.keyState(.combinedSessionState, key: 53),
      dragInsideWheel: overlay.isDragInside)

    let action = trigger.update(sample)
    switch action {
    case .none:
      break
    case .show(let kind):
      hideWork?.cancel()
      overlay.show(kind, at: NSEvent.mouseLocation)
    case .hide:
      overlay.hide()
    case .hideAfterDrop:
      // performDragOperation runs on release; give it a moment before the panel goes.
      let work = DispatchWorkItem { [overlay] in MainActor.assumeIsolated { overlay.hide() } }
      hideWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    setPolling(active: buttonDown || overlay.isVisible)
  }
}

/// The floating, non-activating panel that hosts a drop-mode wheel.
@MainActor
final class WheelOverlayController {
  private var panel: NSPanel?
  /// Room around the wheel for the lit petal to swell into and for the shadow.
  private let size = NSSize(width: 340, height: 340)
  private let diameter = WheelGeometry.design
  private let dropState = WheelDropState()
  private var isShowing = false

  var isVisible: Bool { isShowing }
  var isDragInside: Bool { dropState.isDragInside }

  /// Opens the wheel centred on `point`, or switches the open wheel in place.
  func show(_ kind: WheelKind, at point: NSPoint) {
    let panel = self.panel ?? makePanel()
    self.panel = panel
    if isShowing {
      guard dropState.kind != kind else { return }
      dropState.kind = kind
      dropState.hotID = nil
      dropState.introRevision += 1
      return
    }
    isShowing = true
    dropState.reset()
    dropState.kind = kind
    dropState.introRevision += 1
    panel.setFrameOrigin(NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    panel.alphaValue = 1
    panel.orderFrontRegardless()
  }

  func hide() {
    guard isShowing, let panel else { return }
    isShowing = false
    dropState.hotID = nil
    dropState.isDragInside = false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.14
      panel.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        // A show() during the fade wins.
        guard self?.isShowing == false else { return }
        panel.orderOut(nil)
        self?.dropState.reset()
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
    let container = NSView(frame: NSRect(origin: .zero, size: size))
    let host = NSHostingView(rootView: DropWheelHost(diameter: diameter, state: dropState))
    host.frame = container.bounds
    host.autoresizingMask = [.width, .height]
    let dropView = WheelDropView(state: dropState)
    dropView.diameter = diameter
    dropView.onDrop = { item, urls in
      AppModel.shared.perform(item.command, urls: urls, origin: .overlay)
    }
    dropView.frame = container.bounds
    dropView.autoresizingMask = [.width, .height]
    container.addSubview(host)
    container.addSubview(dropView)  // On top, so it is the drag destination.
    panel.contentView = container
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
