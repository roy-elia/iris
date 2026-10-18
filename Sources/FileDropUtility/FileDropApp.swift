import AppKit
import SwiftUI

@main
struct FileDropApp: App {
  @StateObject private var model = AppModel()

  init() {
    // Menu-bar only: no Dock icon, even when run outside the .app bundle.
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  var body: some Scene {
    MenuBarExtra("File Drop Utility", systemImage: "tray.and.arrow.down") {
      PanelView()
        .environmentObject(model)
    }
    .menuBarExtraStyle(.window)
  }
}
