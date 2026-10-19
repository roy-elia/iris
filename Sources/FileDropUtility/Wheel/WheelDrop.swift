import AppKit
import DropCore
import SwiftUI

/// Sound and trackpad feedback for the wheel, using built-in macOS system sounds.
@MainActor
enum WheelFeedback {
  private static let hoverSounds = SoundPool(name: "Tink", volume: 0.45, voices: 4)
  private static let dropSounds = SoundPool(name: "Pop", volume: 0.7, voices: 2)

  private static var enabled: Bool { AppModel.shared.settings.soundAndHaptics }

  /// A light tick when the pointer moves onto a new segment.
  static func hover() {
    guard enabled else { return }
    hoverSounds.play()
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
  }

  /// A pop when files are dropped on a segment.
  static func drop() {
    guard enabled else { return }
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

/// What the drag overlay shows, shared between the AppKit drop target and the SwiftUI
/// wheel.
@MainActor
final class WheelDropState: ObservableObject {
  @Published var kind: WheelKind = .convert
  /// The dragged files, readable once the drag is over the wheel.
  @Published var files: [DroppedFile] = []
  @Published var hotID: String?
  /// The pointer relative to the wheel's centre, y-down, while the drag is over it.
  @Published var pointer: CGPoint?
  @Published var introRevision = 0
  /// The drag is over the wheel, so letting go of the modifier keeps it open.
  var isDragInside = false

  var items: [WheelItem] { kind.items(for: files) }
  var centerText: String {
    guard !files.isEmpty else { return "Drop" }
    return ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.byteSize }, countStyle: .file)
  }

  func reset() {
    files = []
    hotID = nil
    pointer = nil
    isDragInside = false
  }
}

/// Wraps a drop-mode wheel so it redraws as the drag moves.
struct DropWheelHost: View {
  let diameter: CGFloat
  @ObservedObject var state: WheelDropState

  var body: some View {
    RadialWheel(
      kind: state.kind, items: state.items, centerText: state.centerText, mode: .drop, hotID: state.hotID,
      pointer: state.pointer, introRevision: state.introRevision
    ) { _, _ in }
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
  var diameter: CGFloat = WheelGeometry.design
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

  private func offset(of sender: NSDraggingInfo) -> CGPoint {
    let local = convert(sender.draggingLocation, from: nil)
    return CGPoint(x: local.x - bounds.midX, y: local.y - bounds.midY)
  }

  private func item(at offset: CGPoint) -> WheelItem? {
    let items = state.items
    guard let index = WheelGeometry.segment(at: offset, outerRadius: diameter / 2, count: items.count) else {
      return nil
    }
    return items[index]
  }

  private static func urls(in sender: NSDraggingInfo) -> [URL] {
    sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
      as? [URL] ?? []
  }

  private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
    let point = offset(of: sender)
    state.pointer = point
    let item = item(at: point)
    let id = item?.isEnabled == true ? item?.id : nil
    if id != state.hotID {
      state.hotID = id
      if id != nil { WheelFeedback.hover() }
    }
    return id == nil ? [] : .copy
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    state.isDragInside = true
    // As the drop target, the pasteboard is readable now: show the files' size and
    // enable only the segments that fit them.
    if state.files.isEmpty {
      state.files = Self.urls(in: sender).compactMap { try? DroppedFile.load($0) }
    }
    return update(sender)
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
  override func wantsPeriodicDraggingUpdates() -> Bool { false }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    state.isDragInside = false
    state.hotID = nil
    state.pointer = nil
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    item(at: offset(of: sender))?.isEnabled == true
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let item = item(at: offset(of: sender)), item.isEnabled else { return false }
    let urls = Self.urls(in: sender)
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
