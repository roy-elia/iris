import DropCore
import Foundation

/// `FileDropUtility --run <action> [--out <folder>] <file>…` runs one `QuickAction`
/// without starting the menu-bar app, prints each output path on its own line, and
/// exits non-zero if anything failed. Shortcuts calls it from "Run Shell Script".
enum CommandLineRunner {
  /// Returns false when the arguments have no `--run`; otherwise never returns.
  static func runIfRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
    if arguments.contains("--list-actions") {
      print(QuickAction.specForms.joined(separator: "\n"))
      exit(0)
    }
    let command: QuickActionCommand
    do {
      let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
      guard let parsed = try QuickActionCommand.parse(arguments, currentDirectory: cwd) else { return false }
      command = parsed
    } catch {
      FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
      exit(64)  // EX_USAGE
    }

    var settings = SettingsStore(fileURL: URL.appSupportFolder.appendingPathComponent("settings.json")).load()
    if let folder = command.outputFolder { settings.outputLocation = .folder(folder) }
    Task {
      let result = await QuickActionRunner.run(command.action, on: command.files, settings: settings)
      for url in result.outputs { print(url.path) }
      for failure in result.failures {
        let line = failure.file.isEmpty ? failure.message : "\(failure.file): \(failure.message)"
        FileHandle.standardError.write(Data((line + "\n").utf8))
      }
      exit(result.failures.isEmpty && !result.outputs.isEmpty ? 0 : 1)
    }
    // Some conversions use main-thread frameworks, so keep the main queue running.
    dispatchMain()
  }
}
