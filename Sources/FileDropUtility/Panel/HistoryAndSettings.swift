import DropCore
import SwiftUI

struct HistoryTab: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.stack) {
      if model.history.isEmpty {
        Text("Nothing yet. Finished operations appear here.")
          .foregroundStyle(DesignTokens.Palette.secondaryText)
          .frame(maxWidth: .infinity, minHeight: 90)
          .glassCard()
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(model.history) { entry in
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                  .foregroundStyle(
                    entry.succeeded ? DesignTokens.Palette.accentText : DesignTokens.Palette.warningText
                  )
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                  Text(entry.operation).font(.callout.weight(.medium))
                  Text(
                    "\(entry.inputCount) in, \(entry.outputs.count) out · "
                      + entry.date.formatted(date: .abbreviated, time: .shortened)
                  )
                  .font(.caption)
                  .foregroundStyle(DesignTokens.Palette.secondaryText)
                  ForEach(entry.errors, id: \.self) {
                    Text($0).font(.caption).foregroundStyle(DesignTokens.Palette.errorText)
                  }
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
  @State private var formatForDefaults: ImageFormat = .jpeg
  @State private var audioForDefaults: AudioOutput = .mp3

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

      formatDefaults
        .glassCard()

      VStack(alignment: .leading, spacing: 6) {
        Text("Save to").font(.callout.weight(.medium))
        Text(locationLabel)
          .font(.caption)
          .foregroundStyle(DesignTokens.Palette.secondaryText)
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
        Toggle("Wheels while dragging", isOn: $model.settings.wheelTriggerEnabled)
          .accessibilityIdentifier("wheelTrigger")
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
          ForEach(WheelKind.allCases) { kind in
            GridRow {
              Text(kind.title)
              Picker(kind.title, selection: modifierBinding(for: kind)) {
                ForEach(ModifierCombo.choices, id: \.self) { combo in
                  Text("\(combo.symbols)  \(combo.names)").tag(combo)
                }
              }
              .pickerStyle(.menu)
              .labelsHidden()
              .fixedSize()
              .accessibilityIdentifier("modifier-\(kind.rawValue)")
            }
          }
        }
        .disabled(!model.settings.wheelTriggerEnabled)
        Toggle("Sound and haptic feedback", isOn: $model.settings.soundAndHaptics)
          .accessibilityIdentifier("soundAndHaptics")
        Picker("Wheel theme", selection: $model.settings.wheelTheme) {
          ForEach(WheelTheme.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("wheelTheme")
      }
      .glassCard()

      VStack(alignment: .leading, spacing: 8) {
        Picker("Terminal app", selection: $model.settings.terminalBundleID) {
          ForEach(model.installedTerminals, id: \.bundleID) { app in
            Text(app.name).tag(app.bundleID)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("terminalApp")
        Toggle(
          "Launch at login",
          isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
        )
        .accessibilityIdentifier("launchAtLogin")
        Toggle("Check for updates daily", isOn: $model.settings.checkForUpdates)
          .disabled(UpdateChecker.feedURL() == nil)
          .help(
            UpdateChecker.feedURL() == nil
              ? "This build has no update feed." : "Looks for a newer release once a day."
          )
          .accessibilityIdentifier("checkForUpdates")
        if model.settings.checkForUpdates {
          HStack {
            Button("Check Now") { model.checkForUpdates(manual: true) }.buttonStyle(.glass).controlSize(
              .small)
            if let status = model.updateStatus {
              Text(status).font(.caption).foregroundStyle(DesignTokens.Palette.secondaryText)
            }
          }
        }
        if let error = model.settingsError {
          Text(error).font(.caption).foregroundStyle(DesignTokens.Palette.errorText)
        }
      }
      .glassCard()
    }
  }

  /// Defaults for one output format, used whenever you convert to it.
  private var formatDefaults: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Format defaults", selection: $formatForDefaults) {
        ForEach(ImageFormat.writable, id: \.self) { Text($0.displayName).tag($0) }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("formatDefaults")
      if formatForDefaults.usesQuality {
        Toggle("Own quality", isOn: ownQuality)
        if model.settings.formatSettings[formatForDefaults.rawValue]?.quality != nil {
          HStack {
            Slider(value: formatQuality, in: AppSettings.qualityRange).accessibilityLabel(
              "\(formatForDefaults.displayName) quality")
            Text("\(Int(formatQuality.wrappedValue * 100))%").monospacedDigit().frame(
              width: 42, alignment: .trailing)
          }
        }
      }
      Toggle("Preserve metadata", isOn: formatBinding(\.preserveMetadata))
      if formatForDefaults == .gif {
        Toggle("Keep animation (original dimensions)", isOn: formatBinding(\.keepOriginalDimensions))
      }
      Divider()
      Picker("Audio defaults", selection: $audioForDefaults) {
        ForEach(AudioOutput.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("audioDefaults")
      if audioForDefaults.usesBitDepth {
        Picker("Bit depth", selection: audioSetting(\.audioBitDepth, fallback: 16)) {
          ForEach(
            audioForDefaults == .aiff || audioForDefaults == .flac ? [16, 24] : AudioOutput.bitDepths,
            id: \.self
          ) {
            Text("\($0)-bit").tag($0)
          }
        }
        .pickerStyle(.segmented)
      } else {
        Picker("Bitrate", selection: audioSetting(\.audioBitrateKbps, fallback: 192)) {
          ForEach([96, 128, 192, 256, 320], id: \.self) { Text("\($0) kbps").tag($0) }
        }
        .pickerStyle(.menu)
      }
    }
  }

  private func audioSetting(_ keyPath: WritableKeyPath<FormatSettings, Int?>, fallback: Int) -> Binding<Int> {
    Binding(
      get: { model.settings.format(audioForDefaults.rawValue)[keyPath: keyPath] ?? fallback },
      set: { value in
        var f = model.settings.format(audioForDefaults.rawValue)
        f[keyPath: keyPath] = value
        model.settings.formatSettings[audioForDefaults.rawValue] = f
      })
  }

  private func formatBinding(_ keyPath: WritableKeyPath<FormatSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { model.settings.format(formatForDefaults.rawValue)[keyPath: keyPath] },
      set: { value in
        var f = model.settings.format(formatForDefaults.rawValue)
        f[keyPath: keyPath] = value
        model.settings.formatSettings[formatForDefaults.rawValue] = f
      })
  }

  private var ownQuality: Binding<Bool> {
    Binding(
      get: { model.settings.formatSettings[formatForDefaults.rawValue]?.quality != nil },
      set: { on in
        var f = model.settings.format(formatForDefaults.rawValue)
        f.quality = on ? model.settings.quality : nil
        model.settings.formatSettings[formatForDefaults.rawValue] = f
      })
  }

  private var formatQuality: Binding<Double> {
    Binding(
      get: { model.settings.quality(for: formatForDefaults.rawValue) },
      set: { value in
        var f = model.settings.format(formatForDefaults.rawValue)
        f.quality = AppSettings.clampQuality(value)
        model.settings.formatSettings[formatForDefaults.rawValue] = f
      })
  }

  /// Picking a combination another wheel uses swaps the two, so no two wheels share one.
  private func modifierBinding(for kind: WheelKind) -> Binding<ModifierCombo> {
    Binding(
      get: { kind.combo(in: model.settings.wheelModifiers) },
      set: { combo in
        var modifiers = model.settings.wheelModifiers
        let previous = kind.combo(in: modifiers)
        for other in WheelKind.allCases where other != kind && other.combo(in: modifiers) == combo {
          other.setCombo(previous, in: &modifiers)
        }
        kind.setCombo(combo, in: &modifiers)
        model.settings.wheelModifiers = modifiers
      })
  }

  private var locationLabel: String {
    switch model.settings.outputLocation {
    case .nextToSource: "Next to original"
    case .folder(let url): url.path
    }
  }
}
