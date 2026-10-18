import AppKit
import DropCore
import ServiceManagement
import SwiftUI

/// The operation the user has picked in the panel.
enum OperationChoice: String, CaseIterable, Identifiable {
  case convert, stripMetadata, mergePDFs, imagesToPDF
  var id: String { rawValue }

  var title: String {
    switch self {
    case .convert: "Convert"
    case .stripMetadata: "Strip metadata"
    case .mergePDFs: "Merge PDFs"
    case .imagesToPDF: "Images to PDF"
    }
  }
}

@MainActor
final class AppModel: ObservableObject {
  @Published var files: [DroppedFile] = []
  @Published var rejected: [String] = []
  @Published var choice: OperationChoice = .convert
  @Published var format: ImageFormat
  @Published var quality: Double
  @Published var isRunning = false
  @Published var lastResult: OperationResult?
  @Published var history: [HistoryEntry]
  @Published var settings: AppSettings {
    didSet { saveSettings() }
  }
  @Published var settingsError: String?

  private let settingsStore: SettingsStore
  private let historyStore: HistoryStore

  init(folder: URL = .appSupportFolder) {
    settingsStore = SettingsStore(fileURL: folder.appendingPathComponent("settings.json"))
    historyStore = HistoryStore(fileURL: folder.appendingPathComponent("history.json"))
    let loaded = settingsStore.load()
    settings = loaded
    format = loaded.defaultFormat
    quality = loaded.quality
    history = historyStore.load()
  }

  var operation: FileOperation {
    switch choice {
    case .convert: .convert(format, quality: quality)
    case .stripMetadata: .stripMetadata
    case .mergePDFs: .mergePDFs
    case .imagesToPDF: .imagesToPDF
    }
  }

  var validationMessage: String? { Processor.validate(operation, files: files) }

  // MARK: Queue

  func add(_ urls: [URL]) {
    rejected = []
    lastResult = nil
    for url in urls {
      guard !files.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else {
        continue
      }
      do {
        files.append(try DroppedFile.load(url))
      } catch {
        rejected.append((error as? LocalizedError)?.errorDescription ?? url.lastPathComponent)
      }
    }
    suggestOperation()
  }

  func remove(_ file: DroppedFile) {
    files.removeAll { $0.id == file.id }
  }

  func clear() {
    files = []
    rejected = []
    lastResult = nil
  }

  func chooseFiles() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    NSApp.activate(ignoringOtherApps: true)
    if panel.runModal() == .OK { add(panel.urls) }
  }

  /// Picks a sensible operation for what was dropped, without overriding a valid choice.
  private func suggestOperation() {
    guard validationMessage != nil, !files.isEmpty else { return }
    if files.allSatisfy({ $0.kind == .pdf }) {
      choice = .mergePDFs
    } else if files.allSatisfy(\.kind.isImage) {
      choice = .convert
    }
  }

  // MARK: Run

  func run() {
    guard !isRunning else { return }
    let operation = operation
    let files = files
    let processor = Processor(settings: settings)
    let store = historyStore
    isRunning = true
    Task {
      let result = await Task.detached { processor.run(operation, on: files) }.value
      lastResult = result
      if let entries = try? store.append(result.historyEntry(for: operation, inputCount: files.count)) {
        history = entries
      }
      isRunning = false
    }
  }

  func reveal(_ urls: [URL]) {
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  func airDrop(_ urls: [URL]) {
    NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
  }

  func clearHistory() {
    try? historyStore.clear()
    history = []
  }

  // MARK: Settings

  func chooseOutputFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = "Use Folder"
    NSApp.activate(ignoringOtherApps: true)
    if panel.runModal() == .OK, let url = panel.url {
      settings.outputLocation = .folder(url)
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    settingsError = nil
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      settings.launchAtLogin = enabled
    } catch {
      settingsError = "Launch at login needs the app bundle: \(error.localizedDescription)"
      settings.launchAtLogin = false
    }
  }

  private func saveSettings() {
    do {
      try settingsStore.save(settings)
    } catch {
      settingsError = "Settings could not be saved."
    }
  }
}
