import DropCore
import SwiftUI
import UniformTypeIdentifiers

/// Drop zone, queued files, wheel launchers and the last result.
struct FilesTab: View {
  @EnvironmentObject private var model: AppModel
  @State private var openWheel: WheelKind?
  @State private var isTargeted = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.stack) {
      dropZone
      if !model.rejected.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(model.rejected, id: \.self) { message in
            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(
              Color.orange)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
        .groupBoxed()
      }
      if !model.files.isEmpty {
        fileList
        if let wheel = openWheel {
          wheelView(wheel)
        } else {
          wheelLaunchers
        }
      }
      if let result = model.lastResult {
        ResultCard(result: result, operation: model.lastOperation ?? "")
          .morphTransition(reduceMotion: reduceMotion)
      }
    }
    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: openWheel)
    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: model.files.count)
  }

  private var dropZone: some View {
    VStack(spacing: 6) {
      Image(systemName: "tray.and.arrow.down")
        .font(.system(size: 26, weight: .medium))
        .foregroundStyle(isTargeted ? DesignTokens.Palette.brandInk : .secondary)
        .accessibilityHidden(true)
      Text("Drop files or text here").font(.callout)
      // The window's one violet primary action.
      Button("Choose Files…") { model.chooseFiles() }
        .primaryActionStyle()
        .accessibilityIdentifier("chooseFiles")
      Button("Paste Text as Markdown") { model.pasteTextAsMarkdown() }
        .buttonStyle(.glass).tint(nil)
        .keyboardShortcut("v", modifiers: .command)
        .accessibilityIdentifier("pasteText")
    }
    .frame(maxWidth: .infinity, minHeight: 110)
    .padding(DesignTokens.Spacing.cardPadding)
    // A drop target is a control, so it's glass; it takes the accent tint while files hover.
    .glassPanel(tint: isTargeted ? DesignTokens.Palette.brand : nil, interactive: true)
    .onDrop(
      of: [.fileURL, .utf8PlainText, .plainText],
      delegate: FilesDropDelegate(model: model, isTargeted: $isTargeted)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Drop zone for files or text")
  }

  private var fileList: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("\(model.files.count) file\(model.files.count == 1 ? "" : "s") · \(model.totalSizeText)")
          .font(.headline)
        Spacer()
        Button("Clear") { model.clear() }
          .buttonStyle(.bordered).tint(nil)
          .accessibilityIdentifier("clearFiles")
      }
      // Only scroll once the list is long; a short list sizes to its rows.
      if model.files.count <= 4 {
        fileRows
      } else {
        ScrollView { fileRows }.frame(height: 130)
      }
    }
    .padding(4)
    .groupBoxed()
  }

  private var fileRows: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(model.files) { file in
        HStack(spacing: 8) {
          Image(systemName: file.kind == .pdf ? "doc.richtext" : "photo")
            .foregroundStyle(Color.secondary)
            .accessibilityHidden(true)
          Text(file.name).lineLimit(1).truncationMode(.middle)
          Spacer()
          Text(ByteCountFormatter.string(fromByteCount: file.byteSize, countStyle: .file))
            .foregroundStyle(Color.secondary)
            .monospacedDigit()
          Button {
            model.remove(file)
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove \(file.name)")
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
      }
    }
  }

  private var wheelLaunchers: some View {
    GlassEffectContainer(spacing: DesignTokens.Spacing.tight) {
      HStack(spacing: DesignTokens.Spacing.tight) {
        ForEach(WheelKind.allCases) { kind in
          Button {
            withMorph(reduceMotion: reduceMotion) { openWheel = kind }
          } label: {
            VStack(spacing: 4) {
              Image(systemName: kind.systemImage).font(.title3).accessibilityHidden(true)
              Text(kind.title).font(.callout.weight(.medium))
              Text("\(kind.keySymbol) \(kind.keyName)").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
          }
          .buttonStyle(.glass).tint(nil)
          .buttonBorderShape(.roundedRectangle(radius: DesignTokens.Radius.card))
          .accessibilityLabel("Open \(kind.longTitle) wheel")
          .accessibilityIdentifier("open-\(kind.rawValue)")
        }
      }
    }
  }

  private func wheelView(_ kind: WheelKind) -> some View {
    VStack(spacing: DesignTokens.Spacing.tight) {
      HStack {
        Button {
          withMorph(reduceMotion: reduceMotion) { openWheel = nil }
        } label: {
          Label("Back", systemImage: "chevron.left")
        }
        .buttonStyle(.glass).tint(nil)
        .accessibilityIdentifier("wheelBack")
        Spacer()
        Text(kind.longTitle).font(.headline)
      }
      RadialWheel(
        kind: kind, items: kind.items(for: model.files), centerText: model.totalSizeText, mode: .click
      ) { item, _ in
        model.perform(item.command, urls: [], origin: .panel)
        withMorph(reduceMotion: reduceMotion) { openWheel = nil }
      }
      .frame(height: 330)
    }
    .morphTransition(reduceMotion: reduceMotion)
  }
}

/// Outcome of the last operation, with follow-up actions.
struct ResultCard: View {
  @EnvironmentObject private var model: AppModel
  let result: OperationResult
  let operation: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !result.outputs.isEmpty {
        Label(
          "\(operation): \(result.renames.isEmpty ? "saved" : "renamed") \(result.outputs.count) file\(result.outputs.count == 1 ? "" : "s")",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(DesignTokens.Palette.brandInk)
        .font(.callout.weight(.semibold))
        ForEach(result.outputs, id: \.self) { url in
          Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
        }
        if let notice = result.downloadsNotice {
          Label(notice, systemImage: "arrow.down.circle")
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .accessibilityIdentifier("downloadsNotice")
        }
        HStack {
          // The result card is content, so its buttons use the standard style, not glass.
          Button("Show in Finder") { model.reveal(result.outputs) }
            .buttonStyle(.bordered).tint(nil)
            .accessibilityIdentifier("reveal")
          Button("AirDrop") { model.perform(.airDrop, urls: result.outputs, origin: .panel) }
            .buttonStyle(.bordered).tint(nil)
            .accessibilityIdentifier("airdrop")
          ShareButton(items: result.outputs).fixedSize()
          if !result.renames.isEmpty {
            Button("Undo Rename") { model.undoRenames() }
              .buttonStyle(.bordered).tint(nil)
              .accessibilityIdentifier("undoRename")
          }
        }
      }
      ForEach(Array(result.failures.enumerated()), id: \.offset) { _, failure in
        Label(
          failure.file.isEmpty ? failure.message : "\(failure.file): \(failure.message)",
          systemImage: "xmark.octagon"
        )
        .font(.caption)
        .foregroundStyle(Color.red)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(4)
    .groupBoxed()
  }
}

/// Takes files or text. A plain-text file (.txt, .md) is also readable as text, so the choice
/// comes from the drag's own types: anything carrying a file URL is a file, and only a drag
/// with no file in it is text.
private struct FilesDropDelegate: DropDelegate {
  let model: AppModel
  @Binding var isTargeted: Bool

  func validateDrop(info: DropInfo) -> Bool {
    info.hasItemsConforming(to: [.fileURL, .utf8PlainText, .plainText])
  }

  func dropEntered(info: DropInfo) { isTargeted = true }
  func dropExited(info: DropInfo) { isTargeted = false }
  func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

  func performDrop(info: DropInfo) -> Bool {
    isTargeted = false
    if info.hasItemsConforming(to: [.fileURL]) {
      URLLoader.load(info.itemProviders(for: [.fileURL])) { model.add($0) }
    } else {
      TextLoader.load(info.itemProviders(for: [.utf8PlainText, .plainText])) { model.addText($0) }
    }
    return true
  }
}
