import DropCore
import SwiftUI

struct HistoryTab: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.stack) {
      if model.history.isEmpty {
        Text("Nothing yet. Finished operations appear here.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 90)
          .glassCard()
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(model.history) { entry in
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                  .foregroundStyle(entry.succeeded ? DesignTokens.Palette.accentText : .orange)
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                  Text(entry.operation).font(.callout.weight(.medium))
                  Text(
                    "\(entry.inputCount) in, \(entry.outputs.count) out · "
                      + entry.date.formatted(date: .abbreviated, time: .shortened)
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  ForEach(entry.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                }
              }
              .accessibilityElement(children: .combine)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 300)
        .glassCard()
        HStack {
          Spacer()
          Button("Clear History") { model.clearHistory() }
            .buttonStyle(.subtleGlass)
            .accessibilityIdentifier("clearHistory")
        }
      }
    }
  }
}

struct SettingsTab: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.stack) {
      VStack(alignment: .leading, spacing: 10) {
        Picker("Appearance", selection: $model.settings.appearance) {
          Text("System").tag(AppearancePreference.system)
          Text("Light").tag(AppearancePreference.light)
          Text("Dark").tag(AppearancePreference.dark)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("appearance")
        Picker("Default format", selection: $model.settings.defaultFormat) {
          ForEach(ImageFormat.writable, id: \.self) { Text($0.displayName).tag($0) }
        }
        .accessibilityIdentifier("defaultFormat")
        HStack {
          Text("Quality")
          Slider(value: $model.settings.quality, in: AppSettings.qualityRange)
            .accessibilityLabel("Quality")
            .accessibilityValue("\(Int(model.settings.quality * 100)) percent")
          Text("\(Int(model.settings.quality * 100))%").monospacedDigit().frame(
            width: 42, alignment: .trailing)
        }
      }
      .glassCard()

      VStack(alignment: .leading, spacing: 6) {
        Text("Save to").font(.callout.weight(.medium))
        Text(locationLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .accessibilityIdentifier("saveLocation")
        HStack {
          Button("Next to Original") { model.settings.outputLocation = .nextToSource }
            .buttonStyle(.subtleGlass)
            .accessibilityIdentifier("nextToOriginal")
          Button("Choose Folder…") { model.chooseOutputFolder() }
            .buttonStyle(.subtleGlass)
            .accessibilityIdentifier("chooseFolder")
        }
      }
      .glassCard()

      VStack(alignment: .leading, spacing: 8) {
        Toggle("Wheels while dragging (⇧ ⌘ ⌃)", isOn: $model.settings.wheelTriggerEnabled)
          .accessibilityIdentifier("wheelTrigger")
        Toggle(
          "Launch at login",
          isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
        )
        .accessibilityIdentifier("launchAtLogin")
        if let error = model.settingsError {
          Text(error).font(.caption).foregroundStyle(.red)
        }
      }
      .glassCard()
    }
  }

  private var locationLabel: String {
    switch model.settings.outputLocation {
    case .nextToSource: "Next to original"
    case .folder(let url): url.path
    }
  }
}
