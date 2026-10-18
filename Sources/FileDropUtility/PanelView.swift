import DropCore
import SwiftUI
import UniformTypeIdentifiers

enum PanelTab: String, CaseIterable, Identifiable {
  case drop = "Files"
  case history = "History"
  case settings = "Settings"
  var id: String { rawValue }
}

struct PanelView: View {
  @EnvironmentObject private var model: AppModel
  @State private var tab: PanelTab = .drop

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Section", selection: $tab) {
        ForEach(PanelTab.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      switch tab {
      case .drop: DropTab()
      case .history: HistoryTab()
      case .settings: SettingsTab()
      }

      Divider()
      HStack {
        Text("File Drop Utility").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Quit") { NSApplication.shared.terminate(nil) }
          .accessibilityIdentifier("quit")
          .keyboardShortcut("q")
      }
    }
    .padding(14)
    .frame(width: 380)
  }
}

// MARK: - Files tab

struct DropTab: View {
  @EnvironmentObject private var model: AppModel
  @State private var isTargeted = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      dropZone
      if !model.rejected.isEmpty {
        ForEach(model.rejected, id: \.self) { message in
          Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
      if !model.files.isEmpty {
        fileList
        operationControls
      }
      if let result = model.lastResult {
        ResultView(result: result)
      }
    }
  }

  private var dropZone: some View {
    VStack(spacing: 6) {
      Image(systemName: "tray.and.arrow.down").font(.system(size: 26))
        .accessibilityHidden(true)
      Text("Drop images or PDFs here")
      Button("Choose Files…") { model.chooseFiles() }
        .accessibilityIdentifier("chooseFiles")
        .buttonStyle(.link)
    }
    .frame(maxWidth: .infinity, minHeight: 100)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
    )
    .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
      loadURLs(from: providers)
      return true
    }
    // Keep the Choose Files button reachable on its own; label the container as the drop target.
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Drop zone for images or PDFs")
  }

  private var fileList: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("\(model.files.count) file\(model.files.count == 1 ? "" : "s")").font(.headline)
        Spacer()
        Button("Clear") { model.clear() }.buttonStyle(.borderless)
          .accessibilityIdentifier("clearFiles")
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(model.files) { file in
            HStack {
              Image(systemName: file.kind == .pdf ? "doc.richtext" : "photo")
              Text(file.name).lineLimit(1).truncationMode(.middle)
              Spacer()
              Text(kindLabel(file.kind)).foregroundStyle(.secondary)
              Text(ByteCountFormatter.string(fromByteCount: file.byteSize, countStyle: .file))
                .foregroundStyle(.secondary)
                .monospacedDigit()
              Button {
                model.remove(file)
              } label: {
                Image(systemName: "xmark.circle.fill")
              }
              .buttonStyle(.borderless)
              .accessibilityLabel("Remove \(file.name)")
            }
            .font(.callout)
          }
        }
      }
      .frame(maxHeight: 120)
    }
  }

  private var operationControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Action", selection: $model.choice) {
        ForEach(OperationChoice.allCases) { Text($0.title).tag($0) }
      }
      .accessibilityIdentifier("action")
      if model.choice == .convert {
        Picker("Format", selection: $model.format) {
          ForEach(ImageFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .accessibilityIdentifier("format")
        if model.format.usesQuality {
          HStack {
            Text("Quality")
            Slider(value: $model.quality, in: AppSettings.qualityRange)
            Text("\(Int(model.quality * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
          }
        }
      }
      if let message = model.validationMessage {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        if model.isRunning { ProgressView().controlSize(.small) }
        Button("Run") { model.run() }
          .accessibilityIdentifier("run")
          .keyboardShortcut(.defaultAction)
          .disabled(model.validationMessage != nil || model.isRunning)
      }
    }
  }

  private func kindLabel(_ kind: FileKind) -> String {
    switch kind {
    case .image(let format): format.displayName
    case .pdf: "PDF"
    case .unsupported: "?"
    }
  }

  private func loadURLs(from providers: [NSItemProvider]) {
    let group = DispatchGroup()
    let collected = URLCollector()
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      group.enter()
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        if let url { collected.append(url) }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      MainActor.assumeIsolated { model.add(collected.urls) }
    }
  }
}

/// Gathers URLs from item-provider callbacks, which arrive on arbitrary threads.
private final class URLCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [URL] = []

  func append(_ url: URL) {
    lock.withLock { storage.append(url) }
  }

  var urls: [URL] { lock.withLock { storage } }
}

struct ResultView: View {
  @EnvironmentObject private var model: AppModel
  let result: OperationResult

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !result.outputs.isEmpty {
        Label(
          "Saved \(result.outputs.count) file\(result.outputs.count == 1 ? "" : "s")",
          systemImage: "checkmark.circle"
        )
        .foregroundStyle(.green)
        ForEach(result.outputs, id: \.self) { url in
          Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
        }
        HStack {
          Button("Show in Finder") { model.reveal(result.outputs) }
            .accessibilityIdentifier("reveal")
          Button("AirDrop") { model.airDrop(result.outputs) }
            .accessibilityIdentifier("airdrop")
          ShareButton(items: result.outputs)
            .fixedSize()
        }
        .controlSize(.small)
      }
      ForEach(Array(result.failures.enumerated()), id: \.offset) { _, failure in
        Label(
          failure.file.isEmpty ? failure.message : "\(failure.file): \(failure.message)",
          systemImage: "xmark.octagon"
        )
        .font(.caption)
        .foregroundStyle(.red)
      }
    }
  }
}

// MARK: - History tab

struct HistoryTab: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if model.history.isEmpty {
        Text("Nothing yet. Finished operations appear here.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 80)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(model.history) { entry in
              HStack(alignment: .top) {
                Image(systemName: entry.succeeded ? "checkmark.circle" : "exclamationmark.circle")
                  .foregroundStyle(entry.succeeded ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                  Text(entry.operation).font(.callout)
                  Text(
                    "\(entry.inputCount) in, \(entry.outputs.count) out · "
                      + entry.date.formatted(date: .abbreviated, time: .shortened)
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  ForEach(entry.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                }
              }
            }
          }
        }
        .frame(maxHeight: 260)
        HStack {
          Spacer()
          Button("Clear History") { model.clearHistory() }.buttonStyle(.borderless)
            .accessibilityIdentifier("clearHistory")
        }
      }
    }
  }
}

// MARK: - Settings tab

struct SettingsTab: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Form {
      Picker("Default format", selection: $model.settings.defaultFormat) {
        ForEach(ImageFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }
      .accessibilityIdentifier("defaultFormat")
      HStack {
        Text("Default quality")
        Slider(value: $model.settings.quality, in: AppSettings.qualityRange)
        Text("\(Int(model.settings.quality * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
      }
      // Own rows rather than a LabeledContent column, which is too narrow for two buttons.
      VStack(alignment: .leading, spacing: 4) {
        Text("Save to")
        Text(locationLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .accessibilityIdentifier("saveLocation")
        HStack {
          Button("Next to Original") { model.settings.outputLocation = .nextToSource }
            .accessibilityIdentifier("nextToOriginal")
          Button("Choose Folder…") { model.chooseOutputFolder() }
            .accessibilityIdentifier("chooseFolder")
        }
        .controlSize(.small)
      }
      Toggle(
        "Launch at login",
        isOn: Binding(
          get: { model.settings.launchAtLogin },
          set: { model.setLaunchAtLogin($0) })
      )
      .accessibilityIdentifier("launchAtLogin")
      if let error = model.settingsError {
        Text(error).font(.caption).foregroundStyle(.red)
      }
    }
    .onChange(of: model.settings.defaultFormat) { _, newValue in model.format = newValue }
    .onChange(of: model.settings.quality) { _, newValue in model.quality = newValue }
  }

  private var locationLabel: String {
    switch model.settings.outputLocation {
    case .nextToSource: "Next to original"
    case .folder(let url): url.path
    }
  }
}
