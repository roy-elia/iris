import AppKit
import SwiftUI

@main
enum Main {
  static func main() {
    if CommandLineRunner.runIfRequested() { return }
    FileDropApp.main()
  }
}

struct FileDropApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var model = AppModel.shared

  var body: some Scene {
    MenuBarExtra {
      StatusMenu()
        .environmentObject(model)
    } label: {
      // Fills a ring around the tray while a task runs.
      Image(nsImage: MenuBarIcon.image(progress: model.isRunning ? (model.progress ?? 0) : nil))
    }
    .menuBarExtraStyle(.menu)
  }
}

/// The menu-bar dropdown: a native macOS menu with the app's status, the modifier
/// hints, and the few commands that matter.
struct StatusMenu: View {
  @ObservedObject private var floats = FloatManager.shared
  @EnvironmentObject private var model: AppModel

  var body: some View {
    // Disabled items render as the menu's grey status lines.
    Button {
    } label: {
      Label(statusText, systemImage: model.isRunning ? "hourglass" : "checkmark.circle")
    }
    .disabled(true)
    // One grey line per wheel, so each shortcut reads on its own.
    ForEach(WheelKind.allCases, id: \.self) { kind in
      Button("\(kind.combo(in: model.settings.wheelModifiers).symbols)  \(kind.title)") {}
        .disabled(true)
    }
    if model.isRunning {
      Button("Stop Current Task") { model.cancelCurrentJob() }
    }
    if let update = model.availableUpdate {
      Divider()
      Button("Update Available: Version \(update.version)…") { NSWorkspace.shared.open(update.pageURL) }
    }
    if floats.stacks.count > 0 {
      Divider()
      Button(floats.stacks.count == 1 ? "Close Float" : "Close All Floats") { floats.closeAll() }
    }
    Divider()
    Button("Open File Drop Utility") { WindowManager.shared.openMain() }
    Button("Settings…") { WindowManager.shared.openSettings() }
      .keyboardShortcut(",")
    Button("Getting Started…") { WindowManager.shared.openOnboarding() }
    Button("About File Drop Utility") {
      NSApp.activate()
      NSApp.orderFrontStandardAboutPanel(nil)
    }
    Divider()
    Button("Quit File Drop Utility") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }

  private var statusText: String {
    guard model.isRunning else { return "File Drop Utility is ready" }
    guard let progress = model.progress, progress > 0 else { return "File Drop Utility is working…" }
    return "File Drop Utility is working · \(Int(progress * 100))%"
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    MainActor.assumeIsolated {
      // Menu-bar only: no Dock icon, even when run outside the .app bundle.
      NSApp.setActivationPolicy(.accessory)
      #if DEBUG
        if SnapshotRunner.runIfRequested() { return }
        if SelfTestRunner.runIfRequested() { return }
      #endif
      // Finder's Quick Actions / Services menu (see NSServices in scripts/bundle.sh).
      NSApp.servicesProvider = ServiceProvider.shared
      NSUpdateDynamicServices()
      DragWatcher.shared.start()
      FloatManager.shared.restore()
      AppModel.shared.scheduleUpdateChecks()
      AppModel.shared.startWatching()
      if !AppModel.shared.settings.hasCompletedOnboarding {
        WindowManager.shared.openOnboarding()
      }
    }
  }
}
