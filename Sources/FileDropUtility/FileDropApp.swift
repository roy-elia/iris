import AppKit
import SwiftUI

@main
struct FileDropApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var model = AppModel.shared

  var body: some Scene {
    MenuBarExtra("File Drop Utility", systemImage: "tray.and.arrow.down") {
      PanelView()
        .environmentObject(model)
    }
    .menuBarExtraStyle(.window)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    MainActor.assumeIsolated {
      // Menu-bar only: no Dock icon, even when run outside the .app bundle.
      NSApp.setActivationPolicy(.accessory)
      AppModel.shared.applyAppearance()
      DragWatcher.shared.start()
      if !AppModel.shared.settings.hasCompletedOnboarding {
        WindowManager.shared.openOnboarding()
      }
    }
  }
}
