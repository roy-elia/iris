import DropCore
import PDFKit
import SwiftUI

/// State for the PDF organizer: the page order, each page's turn, and the selection.
@MainActor
final class PDFOrganizerModel: ObservableObject {
  let url: URL
  @Published private(set) var loadError: String?
  @Published private(set) var sourceCount = 0
  @Published var pages: [PDFPageRef] = []
  @Published var selection: Set<Int> = []
  @Published var equalWidths = false
  @Published private(set) var thumbnails: [Int: NSImage] = [:]

  init(url: URL) {
    self.url = url
    load()
  }

  /// A model with sample pages, for previews.
  init(previewURL url: URL, thumbnails: [NSImage]) {
    self.url = url
    sourceCount = thumbnails.count
    pages = (0..<thumbnails.count).map { PDFPageRef(index: $0) }
    self.thumbnails = Dictionary(
      uniqueKeysWithValues: thumbnails.enumerated().map { ($0.offset, $0.element) })
  }

  private func load() {
    guard let doc = PDFDocument(url: url) else {
      loadError = "This PDF could not be opened."
      return
    }
    if doc.isLocked {
      loadError = "This PDF is password-protected."
      return
    }
    sourceCount = doc.pageCount
    pages = (0..<doc.pageCount).map { PDFPageRef(index: $0) }
    for i in 0..<doc.pageCount {
      if let page = doc.page(at: i) {
        thumbnails[i] = page.thumbnail(of: CGSize(width: 240, height: 240), for: .cropBox)
      }
    }
  }

  var plan: PDFPagePlan { PDFPagePlan(pages: pages, equalWidths: equalWidths) }
  var canSave: Bool { !pages.isEmpty && (!plan.isIdentity(pageCount: sourceCount) || equalWidths) }

  /// Selected positions, or every page when nothing is selected.
  private var targets: [Int] { selection.isEmpty ? Array(pages.indices) : selection.sorted() }

  func rotate(by degrees: Int) {
    for i in targets { pages[i] = PDFPageRef(index: pages[i].index, rotation: pages[i].rotation + degrees) }
  }

  func deleteSelected() {
    guard !selection.isEmpty else { return }
    for i in selection.sorted(by: >) { pages.remove(at: i) }
    selection = []
  }

  /// Moves the page at `from` to sit before position `to`.
  func move(from: Int, to: Int) {
    guard pages.indices.contains(from), from != to else { return }
    let page = pages.remove(at: from)
    let target = min(max(to > from ? to - 1 : to, 0), pages.count)
    pages.insert(page, at: target)
    selection = [target]
  }

  func shiftSelected(by offset: Int) {
    guard selection.count == 1, let i = selection.first else { return }
    let j = i + offset
    guard pages.indices.contains(j) else { return }
    pages.swapAt(i, j)
    selection = [j]
  }

  func reset() {
    pages = (0..<sourceCount).map { PDFPageRef(index: $0) }
    selection = []
    equalWidths = false
  }

  func toggle(_ position: Int, extend: Bool) {
    if extend {
      if selection.contains(position) { selection.remove(position) } else { selection.insert(position) }
    } else {
      selection = selection == [position] ? [] : [position]
    }
  }

  func save() {
    guard let file = try? DroppedFile.load(url) else { return }
    AppModel.shared.run(.organizePDF(plan), on: [file], origin: .overlay)
  }
}

/// A grid of page thumbnails to reorder (drag, or the arrow buttons), turn and delete.
struct PDFOrganizerView: View {
  @StateObject var model: PDFOrganizerModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 18)]

  var body: some View {
    ZStack {
      Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()
      if let error = model.loadError {
        ContentUnavailableView("Can't Open PDF", systemImage: "doc.questionmark", description: Text(error))
      } else {
        ScrollView {
          LazyVGrid(columns: columns, spacing: 22) {
            ForEach(Array(model.pages.enumerated()), id: \.offset) { position, ref in
              tile(position: position, ref: ref)
            }
          }
          .padding(.horizontal, 24)
          .padding(.top, 76)
          .padding(.bottom, 24)
        }
      }
      VStack {
        toolbar
        Spacer()
      }
      .padding(DesignTokens.Spacing.inset)
    }
    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: model.pages)
    .onDeleteCommand { model.deleteSelected() }
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      GlassEffectContainer(spacing: 4) {
        HStack(spacing: 2) {
          iconButton("rotate.left", "Turn left") { model.rotate(by: 270) }
          iconButton("rotate.right", "Turn right") { model.rotate(by: 90) }
          iconButton("arrow.left", "Move earlier") { model.shiftSelected(by: -1) }
            .disabled(model.selection.count != 1)
          iconButton("arrow.right", "Move later") { model.shiftSelected(by: 1) }
            .disabled(model.selection.count != 1)
          iconButton("trash", "Delete selected pages") { model.deleteSelected() }
            .disabled(model.selection.isEmpty || model.selection.count == model.pages.count)
        }
        .padding(4)
        .glassPanel(cornerRadius: 999)
      }
      Toggle("Equal widths", isOn: $model.equalWidths)
        .toggleStyle(.checkbox)
        .help("Scale every page to the widest page's width")
      Text(summary).font(.callout.monospacedDigit()).foregroundStyle(Color.secondary)
      Spacer()
      Button("Reset") { model.reset() }.buttonStyle(.glass).tint(nil)
      Button("Save Organized PDF") { model.save() }
        .primaryActionStyle()
        .disabled(!model.canSave)
        .keyboardShortcut("s")
    }
    .padding(.leading, 70)  // Clear the traffic lights.
  }

  private var summary: String {
    let removed = model.sourceCount - model.pages.count
    let base = "\(model.pages.count) page\(model.pages.count == 1 ? "" : "s")"
    return removed > 0 ? "\(base), \(removed) removed" : base
  }

  private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).frame(width: 30, height: 26)
    }
    .buttonStyle(.plain)
    .help(model.selection.isEmpty && label.hasPrefix("Turn") ? "\(label) (all pages)" : label)
    .accessibilityLabel(label)
  }

  private func tile(position: Int, ref: PDFPageRef) -> some View {
    let selected = model.selection.contains(position)
    return VStack(spacing: 8) {
      Group {
        if let thumb = model.thumbnails[ref.index] {
          Image(nsImage: thumb).resizable().scaledToFit()
        } else {
          Rectangle().fill(.white)
        }
      }
      .frame(width: 130, height: 130)
      .rotationEffect(.degrees(Double(ref.rotation)))
      .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
      .frame(width: 150, height: 150)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(selected ? DesignTokens.Palette.brand.opacity(0.22) : .clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(selected ? DesignTokens.Palette.brand : .clear, lineWidth: 2)
      )
      Text("\(position + 1)")
        .font(.callout.monospacedDigit().weight(selected ? .semibold : .regular))
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule())
        .foregroundStyle(selected ? Color(nsColor: .alternateSelectedControlTextColor) : .primary)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      model.toggle(
        position, extend: NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift))
    }
    .draggable(String(position))
    .dropDestination(for: String.self) { items, _ in
      guard let from = items.first.flatMap(Int.init) else { return false }
      model.move(from: from, to: position)
      return true
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Page \(position + 1), from original page \(ref.index + 1)")
    .accessibilityValue(ref.rotation == 0 ? (selected ? "Selected" : "") : "Turned \(ref.rotation) degrees")
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction { model.toggle(position, extend: false) }
  }
}
