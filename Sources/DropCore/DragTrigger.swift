import Foundation

/// Decides when the drag wheel opens, switches, and closes. The app samples the mouse
/// button, modifier keys, Escape and the drag pasteboard on a timer and feeds each
/// sample here, so the wheel reacts to a key press even while the pointer is still.
///
/// Rules:
/// - A drag starts when the drag pasteboard changes while the button is held.
/// - While a drag is active, holding a wheel's modifier opens that wheel at the pointer;
///   switching modifiers switches the wheel in place.
/// - Letting go of the modifier closes the wheel after a short grace period, unless the
///   drag is over the wheel (so you can release the key once you're on a segment).
/// - Escape closes the wheel for the rest of that drag.
/// - Releasing the button ends the drag; the wheel closes once the drop has landed.
public struct DragTrigger<Kind: Equatable>: Sendable where Kind: Sendable {
  public struct Sample: Sendable {
    public var time: TimeInterval
    public var buttonDown: Bool
    public var pasteboardChangeCount: Int
    /// False only when the pasteboard is readable and holds no file URL. macOS 26 often
    /// hides drag types from apps that aren't the drop target, so unknown counts as files.
    public var mayHoldFiles: Bool
    public var kind: Kind?
    public var escapeDown: Bool
    public var dragInsideWheel: Bool

    public init(
      time: TimeInterval, buttonDown: Bool, pasteboardChangeCount: Int, mayHoldFiles: Bool = true,
      kind: Kind?, escapeDown: Bool = false, dragInsideWheel: Bool = false
    ) {
      self.time = time
      self.buttonDown = buttonDown
      self.pasteboardChangeCount = pasteboardChangeCount
      self.mayHoldFiles = mayHoldFiles
      self.kind = kind
      self.escapeDown = escapeDown
      self.dragInsideWheel = dragInsideWheel
    }
  }

  public enum Action: Equatable, Sendable {
    case none
    /// Open the wheel at the pointer, or switch the open one to this kind.
    case show(Kind)
    case hide
    /// The button was released: close once the drop has had time to land.
    case hideAfterDrop
  }

  /// How long a modifier may be let go before the wheel closes.
  public var graceInterval: TimeInterval

  public private(set) var isDragging = false
  public private(set) var shownKind: Kind?
  private var wasButtonDown = false
  private var wasEscapeDown = false
  private var escapedThisDrag = false
  private var changeCountAtMouseDown: Int?
  private var lastTriggerTime: TimeInterval = 0

  public init(graceInterval: TimeInterval = 0.18) {
    self.graceInterval = graceInterval
  }

  /// Records the pasteboard count at the exact moment of a mouse-down, when an event
  /// monitor sees it before the next sample.
  public mutating func mouseDown(pasteboardChangeCount: Int) {
    changeCountAtMouseDown = pasteboardChangeCount
    isDragging = false
    escapedThisDrag = false
  }

  public mutating func update(_ s: Sample) -> Action {
    defer {
      wasButtonDown = s.buttonDown
      wasEscapeDown = s.escapeDown
    }

    if s.buttonDown && !wasButtonDown && changeCountAtMouseDown == nil {
      changeCountAtMouseDown = s.pasteboardChangeCount
      escapedThisDrag = false
    }

    if !s.buttonDown {
      isDragging = false
      changeCountAtMouseDown = nil
      escapedThisDrag = false
      if shownKind != nil {
        shownKind = nil
        return .hideAfterDrop
      }
      return .none
    }

    if !isDragging, let start = changeCountAtMouseDown, s.pasteboardChangeCount != start {
      isDragging = s.mayHoldFiles
      // A non-file drag isn't re-tested on every sample.
      if !s.mayHoldFiles { changeCountAtMouseDown = nil }
    }
    guard isDragging else { return .none }

    if s.escapeDown && !wasEscapeDown && shownKind != nil {
      escapedThisDrag = true
      shownKind = nil
      return .hide
    }
    guard !escapedThisDrag else { return .none }

    if let kind = s.kind {
      lastTriggerTime = s.time
      if kind != shownKind {
        shownKind = kind
        return .show(kind)
      }
      return .none
    }

    if shownKind != nil {
      if s.dragInsideWheel {
        lastTriggerTime = s.time
      } else if s.time - lastTriggerTime > graceInterval {
        shownKind = nil
        return .hide
      }
    }
    return .none
  }
}
