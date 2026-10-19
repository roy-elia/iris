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
      Label(statusText, systemImage: model.isRunning ? "hourglass" : "checkmark.circle")
    }
    .disabled(true)
    Button(hints) {}
      .disabled(true)
    if model.isRunning {
      Button("Stop Current Task") { model.cancelCurrentJob() }
    }
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

  private var statusText: String {
    guard model.isRunning else { return "File Drop Utility is ready" }
    guard let progress = model.progress, progress > 0 else { return "File Drop Utility is working…" }
    return "File Drop Utility is working · \(Int(progress * 100))%"
  }

  /// "⇧: Convert · ⌘: Tools · ⌃: Actions", from the wheel settings.
  private var hints: String {
    WheelKind.allCases.map { "\($0.combo(in: model.settings.wheelModifiers).symbols): \($0.title)" }
      .joined(separator: " · ")
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
