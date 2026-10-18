import AppKit
import SwiftUI

/// Sound and trackpad feedback for the wheel. Uses built-in macOS system sounds.
@MainActor
enum WheelFeedback {
  private static let hoverSound: NSSound? = {
    let sound = NSSound(named: "Tink")?.copy() as? NSSound
    sound?.volume = 0.45
    return sound
  }()
  private static let dropSound: NSSound? = {
    let sound = NSSound(named: "Pop")?.copy() as? NSSound
    sound?.volume = 0.7
    return sound
  }()

  /// A light tick when the pointer moves onto a new segment.
  static func hover() {
    restart(hoverSound)
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
  }

  /// A pop when files are dropped on a segment.
  static func drop() {
    restart(dropSound)
    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
  }

  private static func restart(_ sound: NSSound?) {
    guard let sound else { return }
    // Quick moves across segments retrigger the sound instead of being dropped.
    sound.stop()
    sound.play()
  }
}

/// The segment lit by the drag in progress, shared between the AppKit drop target and
/// the SwiftUI wheel.
@MainActor
final class WheelDropState: ObservableObject {
  @Published var hotID: String?
}

/// Wraps a drop-mode wheel so it redraws when the lit segment changes.
struct DropWheelHost: View {
  let kind: WheelKind
  let items: [WheelItem]
  let diameter: CGFloat
  @ObservedObject var state: WheelDropState

  var body: some View {
    RadialWheel(kind: kind, items: items, centerText: "Drop", mode: .drop, hotID: state.hotID) { _, _ in }
      .frame(width: diameter, height: diameter)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// A transparent AppKit view laid over the wheel that receives the file drag. It works
/// out the segment under the pointer from the angle and distance to the centre, lights
/// it, plays the hover tick, and runs the segment's command on drop.
///
/// AppKit's dragging-destination calls arrive reliably for a panel that appears in the
/// middle of another app's drag, which SwiftUI's per-view `onDrop` did not.
@MainActor
final class WheelDropView: NSView {
  var items: [WheelItem] = []
  var diameter: CGFloat = 340
  let state: WheelDropState
  var onDrop: (WheelItem, [URL]) -> Void = { _, _ in }

  init(state: WheelDropState) {
    self.state = state
    super.init(frame: .zero)
    registerForDraggedTypes([.fileURL])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  // y-down, matching SwiftUI's angles.
  override var isFlipped: Bool { true }

  private func item(for sender: NSDraggingInfo) -> WheelItem? {
    let local = convert(sender.draggingLocation, from: nil)
    let offset = CGPoint(x: local.x - bounds.midX, y: local.y - bounds.midY)
    guard let index = WheelGeometry.segment(at: offset, outerRadius: diameter / 2, count: items.count) else {
      return nil
    }
    return items[index]
  }

  private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
    let item = item(for: sender)
    let id = item?.isEnabled == true ? item?.id : nil
    if id != state.hotID {
      state.hotID = id
      if id != nil { WheelFeedback.hover() }
    }
    return id == nil ? [] : .copy
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
  override func wantsPeriodicDraggingUpdates() -> Bool { false }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    state.hotID = nil
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    item(for: sender)?.isEnabled == true
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let item = item(for: sender), item.isEnabled else { return false }
    let urls =
      sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    guard !urls.isEmpty else { return false }
    WheelFeedback.drop()
    // Run after the drag session finishes so the source app isn't kept waiting.
    DispatchQueue.main.async { [onDrop] in
      MainActor.assumeIsolated { onDrop(item, urls) }
    }
    return true
  }

  override func concludeDragOperation(_ sender: NSDraggingInfo?) {
    state.hotID = nil
  }
}
