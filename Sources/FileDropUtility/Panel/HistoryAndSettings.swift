import DropCore
import SwiftUI

struct HistoryTab: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.stack) {
      if model.history.isEmpty {
        Text("Nothing yet. Finished operations appear here.")
          .foregroundStyle(Color.secondary)
          .frame(maxWidth: .infinity, minHeight: 90)
          .groupBoxed()
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(model.history) { entry in
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                  .foregroundStyle(
                    entry.succeeded ? DesignTokens.Palette.brandInk : Color.orange
                  )
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                  Text(entry.operation).font(.callout.weight(.medium))
                  Text(
                    "\(entry.inputCount) in, \(entry.outputs.count) out · "
                      + entry.date.formatted(date: .abbreviated, time: .shortened)
                  )
                  .font(.caption)
                  .foregroundStyle(Color.secondary)
                  ForEach(entry.errors, id: \.self) {
                    Text($0).font(.caption).foregroundStyle(Color.red)
                  }
                }
              }
              .accessibilityElement(children: .combine)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 300)
        .padding(4)
        .groupBoxed()
        HStack {
          Spacer()
          // History is content, so its controls use the standard style, not glass.
          Button("Clear History") { model.clearHistory() }
            .buttonStyle(.bordered).tint(nil)
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
  @State private var videoForDefaults: VideoOutput = .mp4

  var body: some View {
    Form {
      Section("Output") {
        Picker("Default format", selection: $model.settings.defaultFormat) {
          ForEach(ImageFormat.writable, id: \.self) { Text($0.displayName).tag($0) }
        }
        .accessibilityIdentifier("defaultFormat")
        LabeledContent("Quality") {
          HStack {
            Slider(value: $model.settings.quality, in: AppSettings.qualityRange)
              .labelsHidden()
              .accessibilityLabel("Quality")
              .accessibilityValue("\(Int(model.settings.quality * 100)) percent")
            Text("\(Int(model.settings.quality * 100))%").monospacedDigit().frame(
              width: 42, alignment: .trailing)
          }
        }
      }

      Section("Format defaults") { formatDefaults }

      Section("Save to") {
        // One pop-up instead of three buttons: the choices people make, with a custom folder
        // shown by name and Choose Folder… at the end, as in Safari's download location.
        Picker("Location", selection: locationChoice) {
          Text("Next to Original").tag(LocationChoice.nextToSource)
          Text("Downloads").tag(LocationChoice.downloads)
          if case .folder(let url) = model.settings.outputLocation,
            url.standardizedFileURL != Self.downloads
          {
            Text(url.lastPathComponent).tag(LocationChoice.custom).help(url.path)
          }
          Divider()
          Text("Choose Folder…").tag(LocationChoice.choose)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("saveLocation")
        if model.settings.outputLocation == .nextToSource {
          Text(
            "If the original’s folder is read-only or hidden, such as a Mail attachment, files go to Downloads."
          )
          .font(.caption)
          .foregroundStyle(Color.secondary)
        }
      }

      RecipesSection()
      WatchFoldersSection()
      Section("Wheels") {
        Toggle("Wheels while dragging", isOn: $model.settings.wheelTriggerEnabled)
          .accessibilityIdentifier("wheelTrigger")
        ForEach(WheelKind.allCases) { kind in
          Picker(kind.title, selection: modifierBinding(for: kind)) {
            ForEach(ModifierCombo.choices, id: \.self) { combo in
              Text("\(combo.symbols)  \(combo.names)").tag(combo)
            }
          }
          .pickerStyle(.menu)
          .disabled(!model.settings.wheelTriggerEnabled)
          .accessibilityIdentifier("modifier-\(kind.rawValue)")
        }
        Toggle("Sound and haptic feedback", isOn: $model.settings.soundAndHaptics)
          .accessibilityIdentifier("soundAndHaptics")
        Picker("Wheel theme", selection: $model.settings.wheelTheme) {
          ForEach(WheelTheme.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("wheelTheme")
      }

      Section("General") {
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
            Button("Check Now") { model.checkForUpdates(manual: true) }.buttonStyle(.bordered).tint(nil)
              .controlSize(
                .small)
            if let status = model.updateStatus {
              Text(status).font(.caption).foregroundStyle(Color.secondary)
            }
          }
        }
        if let error = model.settingsError {
          Text(error).font(.caption).foregroundStyle(Color.red)
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }

  /// Defaults for one output format, used whenever you convert to it.
  @ViewBuilder private var formatDefaults: some View {
    Group {
      Picker("Image format", selection: $formatForDefaults) {
        ForEach(ImageFormat.writable, id: \.self) { Text($0.displayName).tag($0) }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("formatDefaults")
      if formatForDefaults.usesQuality {
        Toggle("Custom \(formatForDefaults.displayName) quality", isOn: ownQuality)
          .help("Use its own quality instead of the default quality above.")
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
      Picker("Video format", selection: $videoForDefaults) {
        ForEach(VideoOutput.allCases.filter(\.usesVideoDefaults), id: \.self) { Text($0.displayName).tag($0) }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("videoDefaults")
      Toggle("Keep original dimensions", isOn: videoKeepDimensions)
      if !model.settings.format(videoForDefaults.rawValue).keepOriginalDimensions {
        Picker("Maximum video height", selection: videoSetting(\.maxVideoHeight, fallback: 1080)) {
          ForEach(FormatSettings.videoHeights, id: \.self) { Text("\($0)p").tag($0) }
        }
        .pickerStyle(.menu)
      }
      if videoForDefaults.usesBitrate {
        Picker("Video bitrate", selection: videoBitrate) {
          Text("Automatic").tag(0)
          ForEach(FormatSettings.videoBitrates, id: \.self) { Text("\($0 / 1000) Mbps").tag($0) }
        }
        .pickerStyle(.menu)
      }
      Picker("Audio format", selection: $audioForDefaults) {
        ForEach(AudioOutput.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("audioDefaults")
      if audioForDefaults.usesBitDepth {
        Picker("Bit depth", selection: audioSetting(\.audioBitDepth, fallback: 16)) {
          ForEach(audioForDefaults.bitDepthChoices, id: \.self) {
            Text("\($0)-bit").tag($0)
          }
        }
        .pickerStyle(.segmented)
      } else if audioForDefaults.usesBitrate {
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

  private func videoSetting(_ keyPath: WritableKeyPath<FormatSettings, Int?>, fallback: Int) -> Binding<Int> {
    Binding(
      get: { model.settings.format(videoForDefaults.rawValue)[keyPath: keyPath] ?? fallback },
      set: { value in
        var f = model.settings.format(videoForDefaults.rawValue)
        f[keyPath: keyPath] = value
        model.settings.formatSettings[videoForDefaults.rawValue] = f
      })
  }

  /// Turning "keep original dimensions" off starts from 1080p.
  private var videoKeepDimensions: Binding<Bool> {
    Binding(
      get: { model.settings.format(videoForDefaults.rawValue).keepOriginalDimensions },
      set: { keep in
        var f = model.settings.format(videoForDefaults.rawValue)
        f.keepOriginalDimensions = keep
        if !keep && f.maxVideoHeight == nil { f.maxVideoHeight = 1080 }
        model.settings.formatSettings[videoForDefaults.rawValue] = f
      })
  }

  /// 0 stands for "Automatic" (constant quality).
  private var videoBitrate: Binding<Int> {
    Binding(
      get: { model.settings.format(videoForDefaults.rawValue).videoBitrateKbps ?? 0 },
      set: { value in
        var f = model.settings.format(videoForDefaults.rawValue)
        f.videoBitrateKbps = value == 0 ? nil : value
        model.settings.formatSettings[videoForDefaults.rawValue] = f
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

  private static let downloads = OutputNamer.downloadsDirectory().standardizedFileURL

  private enum LocationChoice: Hashable { case nextToSource, downloads, custom, choose }

  private var locationChoice: Binding<LocationChoice> {
    Binding(
      get: {
        switch model.settings.outputLocation {
        case .nextToSource: .nextToSource
        case .folder(let url) where url.standardizedFileURL == Self.downloads: .downloads
        case .folder: .custom
        }
      },
      set: { choice in
        switch choice {
        case .nextToSource: model.settings.outputLocation = .nextToSource
        case .downloads: model.settings.outputLocation = .folder(OutputNamer.downloadsDirectory())
        case .custom: break
        // Opens the folder panel; cancelling it leaves the current location selected.
        case .choose: DispatchQueue.main.async { model.chooseOutputFolder() }
        }
      })
  }
}
