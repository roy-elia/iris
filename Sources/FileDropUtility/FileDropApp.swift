import AppKit
import SwiftUI

@main
struct FileDropApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var model = AppModel.shared

  var body: some Scene {
    MenuBarExtra("File Drop Utility", systemImage: "tray.and.arrow.down") {
      StatusMenu()
        .environmentObject(model)
    }
    .menuBarExtraStyle(.menu)
  }
}

/// The menu-bar dropdown: a native macOS menu with the app's status, the modifier
/// hints, and the few commands that matter.
struct StatusMenu: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    // Disabled items render as the menu's grey status lines.
    Button {
    } label: {
      Label(
        model.isRunning ? "File Drop Utility is working…" : "File Drop Utility is ready",
        systemImage: model.isRunning ? "hourglass" : "checkmark.circle")
    }
    .disabled(true)
    Button("⇧: Convert · ⌘: Tools · ^: Actions") {}
      .disabled(true)
    Divider()
    Button("Settings…") { WindowManager.shared.openMain() }
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
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    MainActor.assumeIsolated {
      // Menu-bar only: no Dock icon, even when run outside the .app bundle.
      NSApp.setActivationPolicy(.accessory)
      #if DEBUG
        if SnapshotRunner.runIfRequested() { return }
      #endif
      AppModel.shared.applyAppearance()
      DragWatcher.shared.start()
      if !AppModel.shared.settings.hasCompletedOnboarding {
        WindowManager.shared.openOnboarding()
      }
    }
  }
}
