import AppKit
import DropCore
import ServiceManagement
import SwiftUI

/// App state shared by the menu-bar panel, the drag overlay and the windows.
@MainActor
final class AppModel: ObservableObject {
  static let shared = AppModel()

  @Published var files: [DroppedFile] = []
  @Published var rejected: [String] = []
  @Published var isRunning = false
  /// Progress of the running job, 0…1, or nil when none is running.
  @Published var progress: Double?
  private var currentJob: JobHandle?
  @Published var lastResult: OperationResult?
  @Published var lastOperation: String?
  @Published var history: [HistoryEntry]
  @Published var settings: AppSettings {
    didSet {
      saveSettings()
      if oldValue.appearance != settings.appearance { applyAppearance() }
    }
  }
  @Published var settingsError: String?

  private let settingsStore: SettingsStore
  private let historyStore: HistoryStore

  init(folder: URL = .appSupportFolder) {
    settingsStore = SettingsStore(fileURL: folder.appendingPathComponent("settings.json"))
    historyStore = HistoryStore(fileURL: folder.appendingPathComponent("history.json"))
    settings = settingsStore.load()
    history = historyStore.load()
  }

  var totalSizeText: String {
    let total = files.reduce(Int64(0)) { $0 + $1.byteSize }
    return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
  }

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
        rejected.append(Self.message(for: error, fallback: url.lastPathComponent))
      }
    }
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
    NSApp.activate()
    if panel.runModal() == .OK { add(panel.urls) }
  }

  // MARK: Wheel commands

  enum Origin { case panel, overlay }

  /// Runs a wheel command on `urls` (from a drop) or, when empty, on the queued files.
  func perform(_ command: WheelCommand, urls: [URL], origin: Origin) {
    let targets: [DroppedFile]
    if urls.isEmpty {
      targets = files
    } else {
      var loaded: [DroppedFile] = []
      var problems: [String] = []
      for url in urls {
        do { loaded.append(try DroppedFile.load(url)) } catch {
          problems.append(Self.message(for: error, fallback: url.lastPathComponent))
        }
      }
      if loaded.isEmpty {
        finish(
          OperationResult(failures: problems.map { .init(file: "", message: $0) }), operation: "Drop",
          origin: origin)
        return
      }
      targets = loaded
    }
    let fileURLs = targets.map(\.url)

    switch command {
    case .convert(let format):
      run(.convert(format, quality: settings.quality(for: format.rawValue)), on: targets, origin: origin)
    case .toPDF:
      let allPDFs = targets.allSatisfy { $0.kind == .pdf }
      run(allPDFs ? .mergePDFs : .imagesToPDF, on: targets, origin: origin)
    case .compress:
      run(.compress(quality: CompressOps.defaultQuality), on: targets, origin: origin)
    case .stripMetadata:
      run(.stripMetadata, on: targets, origin: origin)
    case .removeBackground:
      run(.replaceBackground(.transparent), on: targets, origin: origin)
    case .edit(let tool):
      guard let first = targets.first(where: \.kind.isImage) else { return }
      WindowManager.shared.openEditor(for: first.url, tool: tool)
    case .airDrop:
      NSSharingService(named: .sendViaAirDrop)?.perform(withItems: fileURLs)
    case .float:
      for url in fileURLs.prefix(6) { WindowManager.shared.openFloat(for: url) }
    case .copy:
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects(fileURLs as [NSURL])
      Toast.show("Copied \(fileURLs.count) file\(fileURLs.count == 1 ? "" : "s")", outputs: [])
    case .copyPath:
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(FileActions.pathText(for: fileURLs), forType: .string)
      Toast.show("Copied \(fileURLs.count == 1 ? "path" : "\(fileURLs.count) paths")", outputs: [])
    case .move:
      move(fileURLs, origin: origin)
    case .terminal:
      openTerminal(at: fileURLs)
    }
  }

  /// Runs a file operation off the main thread and records it.
  func run(_ operation: FileOperation, on targets: [DroppedFile], origin: Origin) {
    guard !isRunning else { return }
    isRunning = true
    progress = 0
    let handle = JobEngine.shared.submit(
      ProcessorJob(operation: operation, files: targets, settings: settings))
    currentJob = handle
    handle.observe { [weak self] state in
      guard case .running(let fraction) = state else { return }
      Task { @MainActor in
        if self?.currentJob === handle { self?.progress = fraction }
      }
    }
    Task {
      let result = await handle.result()
      currentJob = nil
      isRunning = false
      progress = nil
      switch handle.state {
      case .finished(let result):
        finish(result, operation: operation.summary, origin: origin, inputCount: targets.count)
      case .failed(let message):
        finish(
          OperationResult(outputs: [], failures: [.init(file: "", message: message)]),
          operation: operation.summary, origin: origin, inputCount: targets.count)
      default:
        _ = result
      }
    }
  }

  struct TerminalApp {
    let name: String
    let bundleID: String
  }

  /// Terminal apps installed on this Mac, Terminal first.
  var installedTerminals: [TerminalApp] {
    let known: [(String, String)] = [
      ("Terminal", "com.apple.Terminal"), ("iTerm2", "com.googlecode.iterm2"),
      ("Warp", "dev.warp.Warp-Stable"),
      ("Ghostty", "com.mitchellh.ghostty"), ("kitty", "net.kovidgoyal.kitty"), ("Alacritty", "org.alacritty"),
      ("WezTerm", "com.github.wez.wezterm"),
    ]
    return known.filter {
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.1) != nil
        || $0.1 == AppSettings.defaultTerminal
    }
    .map { TerminalApp(name: $0.0, bundleID: $0.1) }
  }

  /// Stops the running job, if any.
  func cancelCurrentJob() { currentJob?.cancel() }

  private func finish(_ result: OperationResult, operation: String, origin: Origin, inputCount: Int = 0) {
    lastResult = result
    lastOperation = operation
    let entry = HistoryEntry(
      operation: operation, inputCount: inputCount, outputs: result.outputs.map(\.lastPathComponent),
      errors: result.failures.map { $0.file.isEmpty ? $0.message : "\($0.file): \($0.message)" })
    if let entries = try? historyStore.append(entry) { history = entries }
    if origin == .overlay { Toast.show(result: result, operation: operation) }
  }

  private func move(_ urls: [URL], origin: Origin) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = "Move Here"
    NSApp.activate()
    guard panel.runModal() == .OK, let folder = panel.url else { return }
    let (moved, failures) = FileActions.move(urls, to: folder)
    // Keep the queue pointing at the files' new homes.
    for (old, new) in zip(urls, moved) {
      if let index = files.firstIndex(where: { $0.url == old }), let reloaded = try? DroppedFile.load(new) {
        files[index] = reloaded
      }
    }
    finish(
      OperationResult(outputs: moved, failures: failures), operation: "Move", origin: origin,
      inputCount: urls.count)
  }

  private func openTerminal(at urls: [URL]) {
    guard let folder = FileActions.commonFolder(of: urls),
      let terminal =
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: settings.terminalBundleID)
        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppSettings.defaultTerminal)
    else { return }
    NSWorkspace.shared.open(
      [folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
  }

  func reveal(_ urls: [URL]) {
    NSWorkspace.shared.activateFileViewerSelecting(urls)
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
    NSApp.activate()
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

  /// System appearance unless the user picked one in Settings.
  func applyAppearance() {
    switch settings.appearance {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
  }

  private func saveSettings() {
    do {
      try settingsStore.save(settings)
    } catch {
      settingsError = "Settings could not be saved."
    }
  }

  nonisolated static func message(for error: Error, fallback: String) -> String {
    (error as? LocalizedError)?.errorDescription ?? fallback
  }
}
