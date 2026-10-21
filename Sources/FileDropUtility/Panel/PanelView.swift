import AppKit
import DropCore
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
  case files = "Files"
  case history = "History"
  var id: String { rawValue }
}

/// The main window: Files and History, switched with a segmented control in the window's
/// toolbar. Settings has its own window (`SettingsWindow`). Content sits in system group
/// boxes; glass is kept for the toolbar (drawn by the system) and the floating controls.
struct PanelView: View {
  @EnvironmentObject private var model: AppModel
  @State private var tab: PanelTab
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(initialTab: PanelTab = .files) {
    _tab = State(initialValue: initialTab)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.stack) {
      // The status line belongs with the drop zone; History has its own content to show.
      if tab == .files { StatusHeader() }
      Group {
        switch tab {
        case .files: FilesTab()
        case .history: HistoryTab()
        }
      }
      .id(tab)
      .morphTransition(reduceMotion: reduceMotion)
    }
    .padding(DesignTokens.Spacing.inset)
    .frame(width: 400)
    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: tab)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker("Section", selection: $tab) {
          ForEach(PanelTab.allCases) { tab in
            Text(tab.rawValue).tag(tab)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("sections")
      }
      ToolbarItem(placement: .primaryAction) { MoreMenu() }
    }
  }

}

/// The Settings window, opened with Settings… (⌘,) from the menu-bar menu or the More menu.
/// The grouped form scrolls itself within the room the screen allows.
struct SettingsWindow: View {
  var body: some View {
    SettingsTab()
      .frame(width: 460, height: min(Self.maxHeight, 640))
  }

  /// The screen's usable height, less the window chrome.
  static var maxHeight: CGFloat {
    max((NSScreen.main?.visibleFrame.height ?? 800) - 160, 320)
  }
}

/// Settings, Getting Started, About and Quit, in the toolbar.
struct MoreMenu: View {
  var body: some View {
    Menu {
      Button("Settings…") { WindowManager.shared.openSettings() }.keyboardShortcut(",")
      Button("Getting Started…") { WindowManager.shared.openOnboarding() }
      Button("About File Drop Utility") {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
      }
      Divider()
      Button("Quit File Drop Utility") { NSApp.terminate(nil) }.keyboardShortcut("q")
    } label: {
      Label("More", systemImage: "ellipsis")
    }
    // Toolbar items stay monochrome; teal is for the window's primary action.
    .tint(nil)
    .accessibilityIdentifier("moreMenu")
  }
}

/// "Ready" line. The modifier hints show only while the drop zone is empty: once files are
/// queued, the wheel launchers below carry the same shortcuts on their own keycaps.
struct StatusHeader: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: model.isRunning ? "hourglass" : "checkmark.circle")
        .font(.title3)
        .foregroundStyle(DesignTokens.Palette.tealInk)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(model.isRunning ? "Working…" : "Ready").font(.headline)
        if let hint {
          Text(hint).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
    }
    .padding(.horizontal, 4)
    .accessibilityElement(children: .combine)
  }

  private var hint: String? {
    guard model.settings.wheelTriggerEnabled else { return "Drag-and-hold wheels are off" }
    guard model.files.isEmpty else { return nil }
    return WheelKind.allCases.map { "\($0.keySymbol) \($0.title)" }.joined(separator: " · ")
  }
}
