import AppKit
import DropCore
import SwiftUI

/// Sound and trackpad feedback for the wheel: the app's own highlight tap, and the macOS
/// Pop sound for drops.
@MainActor
enum WheelFeedback {
  /// The bundled `Highlight.wav`; outside the .app (swift run, the self-test) the same sound
  /// is generated in memory.
  private static let hoverSounds = SoundPool(
    make: {
      (NSSound(named: "Highlight")?.copy() as? NSSound) ?? NSSound(data: HighlightSound.wavData())
    }, volume: 0.8, voices: 4)
  private static let dropSounds = SoundPool(
    make: { NSSound(named: "Pop")?.copy() as? NSSound }, volume: 0.7, voices: 2)

  private static var enabled: Bool { AppModel.shared.settings.soundAndHaptics }

  /// A soft tap when the pointer moves onto a new segment.
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

  init(make: () -> NSSound?, volume: Float, voices count: Int) {
    voices = (0..<count).compactMap { _ in
      let sound = make()
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
  /// The open wheel was swapped for another kind, so the new one skips its opening animation.
  var switching = false
  /// The drag is over the wheel, so letting go of the modifier keeps it open.
  var isDragInside = false

  /// Which page of the wheel is showing; modifier taps turn it.
  @Published var page = 0

  var pages: [[WheelItem]] { WheelPaging.pages(kind.items(for: files)) }
  var items: [WheelItem] {
    let all = pages
    return all[min(page, all.count - 1)]
  }
  var centerText: String {
    guard !files.isEmpty else { return "Drop" }
    return ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.byteSize }, countStyle: .file)
  }

  func reset() {
    files = []
    page = 0
    hotID = nil
    pointer = nil
    isDragInside = false
  }
}

/// Wraps a drop-mode wheel so it redraws as the drag moves.
struct DropWheelHost: View {
  @ObservedObject var state: WheelDropState

  private var diameter: CGFloat { WheelGeometry.diameter(forItemCount: state.items.count) }

  var body: some View {
    RadialWheel(
      kind: state.kind, items: state.items, centerText: state.centerText, mode: .drop, hotID: state.hotID,
      pointer: state.pointer, introRevision: state.introRevision, playsIntro: !state.switching,
      pageIndex: min(state.page, state.pages.count - 1), pageCount: state.pages.count
    ) { _, _ in }
    .id("\(state.kind.rawValue)-\(state.page)")
    .transition(.opacity.combined(with: .scale(scale: 0.94)))
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
  let state: WheelDropState
  /// Matches the drawn wheel, which sizes itself from its petal count.
  var diameter: CGFloat { WheelGeometry.diameter(forItemCount: state.items.count) }
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

  /// What each dragged item looked like before the wheel shrank it, to restore on exit.
  private var originalPreviews: [(frame: NSRect, components: [NSDraggingImageComponent])] = []

  /// The source app (Finder) draws the file's icon and full name at the pointer, and the name
  /// runs across the wheel's centre and petals. While the drag is over the wheel it shows a
  /// compact icon-only chip instead, so the labels stay readable.
  private func compactPreview(_ sender: NSDraggingInfo) {
    originalPreviews = []
    let side: CGFloat = 36
    let location = convert(sender.draggingLocation, from: nil)
    sender.draggingFormation = .none
    sender.enumerateDraggingItems(
      options: [], for: self, classes: [NSURL.self], searchOptions: [.urlReadingFileURLsOnly: true]
    ) { [weak self] item, _, _ in
      guard let self else { return }
      self.originalPreviews.append((item.draggingFrame, item.imageComponents ?? []))
      let icon: NSImage =
        (item.item as? URL).map { NSWorkspace.shared.icon(forFile: $0.path) }
        ?? NSWorkspace.shared.icon(for: .data)
      let component = NSDraggingImageComponent(key: .icon)
      component.contents = icon
      component.frame = NSRect(x: 0, y: 0, width: side, height: side)
      item.draggingFrame = NSRect(x: location.x - side / 2, y: location.y - side / 2, width: side, height: side)
      item.imageComponentsProvider = { [component] }
    }
  }

  private func restorePreview(_ sender: NSDraggingInfo?) {
    guard let sender, !originalPreviews.isEmpty else { return }
    var index = 0
    sender.enumerateDraggingItems(
      options: [], for: self, classes: [NSURL.self], searchOptions: [.urlReadingFileURLsOnly: true]
    ) { [weak self] item, _, _ in
      guard let self, index < self.originalPreviews.count else { return }
      let original = self.originalPreviews[index]
      index += 1
      item.draggingFrame = original.frame
      item.imageComponentsProvider = { original.components }
    }
    originalPreviews = []
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    state.isDragInside = true
    compactPreview(sender)
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
    restorePreview(sender)
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
