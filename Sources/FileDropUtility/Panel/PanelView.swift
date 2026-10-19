import AppKit
import DropCore
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
  case files = "Files"
  case history = "History"
  case settings = "Settings"
  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .files: "tray.and.arrow.down"
    case .history: "clock"
    case .settings: "gearshape"
    }
  }
}

/// The main window: Files, History and Settings, switched with a segmented control in the
/// window's toolbar. Content sits in system group boxes and a grouped form; glass is kept for
/// the toolbar (drawn by the system) and the floating controls.
struct PanelView: View {
  @EnvironmentObject private var model: AppModel
  @State private var tab: PanelTab
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(initialTab: PanelTab = .files) {
    _tab = State(initialValue: initialTab)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.stack) {
      StatusHeader()
      Group {
        switch tab {
        case .files: FilesTab()
        case .history: HistoryTab()
        case .settings:
          // A grouped form scrolls itself; give it the room the screen allows.
          SettingsTab().frame(height: min(Self.settingsMaxHeight, 640))
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

  /// The screen's usable height, less the header and window chrome.
  static var settingsMaxHeight: CGFloat {
    max((NSScreen.main?.visibleFrame.height ?? 800) - 200, 320)
  }
}

/// Getting Started, About and Quit, in the toolbar.
struct MoreMenu: View {
  var body: some View {
    Menu {
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
    .accessibilityIdentifier("moreMenu")
  }
}

/// "Ready" line with the modifier hints.
struct StatusHeader: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: model.isRunning ? "hourglass" : "checkmark.circle")
        .font(.title3)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(model.isRunning ? "Working…" : "Ready").font(.headline)
        Text(hint).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 4)
    .accessibilityElement(children: .combine)
  }

  private var hint: String {
    guard model.settings.wheelTriggerEnabled else { return "Drag-and-hold wheels are off" }
    return WheelKind.allCases.map { "\($0.keySymbol) \($0.title)" }.joined(separator: " · ")
  }
}
