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
        .glassCard()
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
        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
        .accessibilityHidden(true)
      Text("Drop files here").font(.callout)
      Button("Choose Files…") { model.chooseFiles() }
        .buttonStyle(.glass)
        .accessibilityIdentifier("chooseFiles")
    }
    .frame(maxWidth: .infinity, minHeight: 110)
    .padding(DesignTokens.Spacing.cardPadding)
    .glassPanel(tint: isTargeted ? Color.accentColor.opacity(0.35) : nil)
    .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
      URLLoader.load(providers) { model.add($0) }
      return true
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Drop zone for images or PDFs")
  }

  private var fileList: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("\(model.files.count) file\(model.files.count == 1 ? "" : "s") · \(model.totalSizeText)")
          .font(.headline)
        Spacer()
        Button("Clear") { model.clear() }
          .buttonStyle(.glass)
          .accessibilityIdentifier("clearFiles")
      }
      // Only scroll once the list is long; a short list sizes to its rows.
      if model.files.count <= 4 {
        fileRows
      } else {
        ScrollView { fileRows }.frame(height: 130)
      }
    }
    .glassCard()
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
    HStack(spacing: DesignTokens.Spacing.tight) {
      ForEach(WheelKind.allCases) { kind in
        Button {
          withMorph(reduceMotion: reduceMotion) { openWheel = kind }
        } label: {
          VStack(spacing: 4) {
            Image(systemName: kind.systemImage).font(.title3).accessibilityHidden(true)
            Text(kind.title).font(.callout.weight(.medium))
            Text("\(kind.keySymbol) \(kind.keyName)").font(.caption2).foregroundStyle(
              Color.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassPanel(interactive: true)
        .accessibilityLabel("Open \(kind.longTitle) wheel")
        .accessibilityIdentifier("open-\(kind.rawValue)")
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
        .buttonStyle(.glass)
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
          "\(operation): saved \(result.outputs.count) file\(result.outputs.count == 1 ? "" : "s")",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(Color.accentColor)
        .font(.callout.weight(.semibold))
        ForEach(result.outputs, id: \.self) { url in
          Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
        }
        HStack {
          Button("Show in Finder") { model.reveal(result.outputs) }
            .buttonStyle(.glass)
            .accessibilityIdentifier("reveal")
          Button("AirDrop") { model.perform(.airDrop, urls: result.outputs, origin: .panel) }
            .buttonStyle(.glass)
            .accessibilityIdentifier("airdrop")
          ShareButton(items: result.outputs).fixedSize()
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
    .glassCard()
  }
}
