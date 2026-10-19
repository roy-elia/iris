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

/// The menu-bar panel: a status header, a floating tab bar and floating content cards.
struct PanelView: View {
  @EnvironmentObject private var model: AppModel
  @State private var tab: PanelTab = .files
  @State private var settingsHeight: CGFloat = 600
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.stack) {
      StatusHeader()
      FloatingTabBar(
        tabs: PanelTab.allCases, selection: $tab, title: \.rawValue, systemImage: \.systemImage)
      Group {
        switch tab {
        case .files: FilesTab()
        case .history: HistoryTab()
        case .settings:
          // Settings is the tallest tab; scroll it rather than run off a small screen.
          ScrollView {
            SettingsTab()
              .onGeometryChange(for: CGFloat.self) {
                $0.size.height
              } action: {
                settingsHeight = $0
              }
          }
          .scrollBounceBehavior(.basedOnSize)
          // Only clip (which trims the cards' glass edges) when there's something to scroll.
          .scrollClipDisabled(settingsHeight <= Self.settingsMaxHeight)
          .frame(height: min(settingsHeight, Self.settingsMaxHeight))
        }
      }
      .id(tab)
      .morphTransition(reduceMotion: reduceMotion)
    }
    .padding(DesignTokens.Spacing.inset)
    .frame(width: 400)
  }

  /// The screen's usable height, less the header, tab bar and window chrome.
  static var settingsMaxHeight: CGFloat {
    max((NSScreen.main?.visibleFrame.height ?? 800) - 260, 320)
  }
}

/// "Ready" line with the modifier hints, plus the app menu.
struct StatusHeader: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: model.isRunning ? "hourglass" : "checkmark.circle")
        .font(.title3)
        .foregroundStyle(DesignTokens.Palette.accentText)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(model.isRunning ? "Working…" : "Ready").font(.headline)
        Text(hint).font(.caption).foregroundStyle(DesignTokens.Palette.secondaryText)
      }
      Spacer()
      Menu {
        Button("Getting Started…") { WindowManager.shared.openOnboarding() }
        Button("About File Drop Utility") {
          NSApp.activate()
          NSApp.orderFrontStandardAboutPanel(nil)
        }
        Divider()
        Button("Quit File Drop Utility") { NSApp.terminate(nil) }.keyboardShortcut("q")
      } label: {
        Image(systemName: "ellipsis")
          .font(.body.weight(.semibold))
          .frame(width: 28, height: 28)
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .glassEffect(.regular.interactive(), in: Circle())
      .accessibilityLabel("More")
      .accessibilityIdentifier("moreMenu")
    }
    .glassCard()
    .accessibilityElement(children: .contain)
  }

  private var hint: String {
    guard model.settings.wheelTriggerEnabled else { return "Drag-and-hold wheels are off" }
    return WheelKind.allCases.map { "\($0.keySymbol) \($0.title)" }.joined(separator: " · ")
  }
}
