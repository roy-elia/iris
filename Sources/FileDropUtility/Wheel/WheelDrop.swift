import AppKit
import SwiftUI

/// Sound and trackpad feedback for the wheel, using built-in macOS system sounds.
@MainActor
enum WheelFeedback {
  private static let hoverSounds = SoundPool(name: "Tink", volume: 0.45, voices: 4)
  private static let dropSounds = SoundPool(name: "Pop", volume: 0.7, voices: 2)

  /// A light tick when the pointer moves onto a new segment.
  static func hover() {
    hoverSounds.play()
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
  }

  /// A pop when files are dropped on a segment.
  static func drop() {
    dropSounds.play()
    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
  }
}

/// A few copies of one sound played in turn, so quick moves across segments overlap
/// naturally instead of cutting the previous tick off.
@MainActor
private final class SoundPool {
  private let voices: [NSSound]
  private var next = 0

  init(name: NSSound.Name, volume: Float, voices count: Int) {
    voices = (0..<count).compactMap { _ in
      let sound = NSSound(named: name)?.copy() as? NSSound
      sound?.volume = volume
      return sound
    }
  }

  func play() {
    guard !voices.isEmpty else { return }
    let sound = voices[next]
    next = (next + 1) % voices.count
    sound.stop()
    sound.play()
  }
}

/// The segment lit by the drag in progress, shared between the AppKit drop target and
/// the SwiftUI wheel.
@MainActor
final class WheelDropState: ObservableObject {
  @Published var hotID: String?
  /// The drag is over the wheel, so letting go of the modifier keeps it open.
  var isDragInside = false
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

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    state.isDragInside = true
    return update(sender)
  }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
  override func wantsPeriodicDraggingUpdates() -> Bool { false }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    state.isDragInside = false
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
    state.isDragInside = false
    state.hotID = nil
  }
}
