import AppKit
import DropCore
import SwiftUI

/// A running batch: one row per file, updated as the processor reports each one.
struct BatchProgress: Equatable {
  struct Item: Identifiable, Equatable {
    enum State: Equatable { case waiting, working, done, failed(String) }
    let id = UUID()
    let name: String
    var state: State = .waiting
  }

  var title: String
  var items: [Item]

  init(title: String, names: [String]) {
    self.title = title
    items = names.map { Item(name: $0) }
  }

  var finishedCount: Int {
    items.filter { $0.state != .waiting && $0.state != .working }.count
  }

  /// Applies a processor event to the first row it can belong to, so repeated names work.
  mutating func apply(_ event: Processor.FileEvent) {
    switch event.phase {
    case .started:
      if let i = items.firstIndex(where: { $0.name == event.name && $0.state == .waiting }) {
        items[i].state = .working
      }
    case .done:
      if let i = items.firstIndex(where: { $0.name == event.name && $0.state == .working }) {
        items[i].state = .done
      }
    case .failed(let message):
      if let i = items.firstIndex(where: { $0.name == event.name && $0.state == .working }) {
        items[i].state = .failed(message)
      }
    }
  }
}

/// A floating glass capsule with the running batch's checklist, a Cancel button and, when
/// done, hands over to the result toast.
@MainActor
enum ProgressCapsule {
  private static var panel: NSPanel?

  static func show() {
    let host = NSHostingView(
      rootView: ProgressCapsuleView(model: AppModel.shared).padding(DesignTokens.Spacing.inset).brandTint())
    let size = host.fittingSize
    let panel =
      self.panel
      ?? {
        let p = NSPanel(
          contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.animationBehavior = AppWindowAnimation.behavior
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
  }

  static func hide() { panel?.orderOut(nil) }
}

struct ProgressCapsuleView: View {
  @ObservedObject var model: AppModel
  private let visibleRows = 6

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Text(model.batch?.title ?? "Working…").font(.headline).lineLimit(1)
        Spacer(minLength: 16)
        if let batch = model.batch {
          Text("\(batch.finishedCount) of \(batch.items.count)")
            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        Button("Cancel") { model.cancelCurrentJob() }
          .buttonStyle(.borderless).fontWeight(.semibold)
      }
      ProgressView(value: model.progress ?? 0).progressViewStyle(.linear)
      if let batch = model.batch, batch.items.count > 1 {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(rows(batch)) { item in
            HStack(spacing: 8) {
              icon(item.state).frame(width: 16)
              Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(item.state == .waiting ? .secondary : .primary)
            }
          }
          if batch.items.count > visibleRows {
            Text("+ \(batch.items.count - visibleRows) more").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    .frame(width: 320)
    .padding(.horizontal, 18).padding(.vertical, 14)
    .glassPanel(cornerRadius: 22)
    .accessibilityElement(children: .contain)
  }

  /// The rows around the current work: finished ones scroll off the top.
  private func rows(_ batch: BatchProgress) -> [BatchProgress.Item] {
    let start = min(
      max(0, batch.items.firstIndex { $0.state == .working || $0.state == .waiting } ?? 0),
      max(0, batch.items.count - visibleRows))
    return Array(batch.items[start...].prefix(visibleRows))
  }

  @ViewBuilder private func icon(_ state: BatchProgress.Item.State) -> some View {
    switch state {
    case .waiting: Image(systemName: "circle").foregroundStyle(.tertiary)
    case .working: ProgressView().controlSize(.small)
    case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(DesignTokens.Palette.tealInk)
    case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    }
  }
}

/// For snapshots: the capsule's content without its floating panel.
typealias ProgressCapsulePreview = ProgressCapsuleView
