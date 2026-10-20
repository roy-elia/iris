import DropCore
import SwiftUI

/// The Watch Folders section of Settings: folders whose new files run a recipe by themselves.
struct WatchFoldersSection: View {
  @EnvironmentObject private var model: AppModel

  /// Saved recipes first, then the presets.
  private var choices: [Recipe] { model.settings.recipes + WatchFolder.presets }

  var body: some View {
    Section {
      if model.settings.watchFolders.isEmpty {
        Text("Pick a folder, and files saved or dropped into it are converted automatically.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      ForEach($model.settings.watchFolders) { $folder in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Toggle(isOn: $folder.enabled) {
              Label(folder.name, systemImage: "folder.badge.gearshape")
            }
            .help(folder.path)
            .accessibilityLabel("Watch \(folder.name)")
            Spacer()
            Button {
              NSWorkspace.shared.open(folder.url)
            } label: {
              Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Open \(folder.name)")
            .accessibilityLabel("Open \(folder.name)")
            Button(role: .destructive) {
              model.settings.watchFolders.removeAll { $0.id == folder.id }
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Stop watching \(folder.name)")
            .accessibilityLabel("Stop watching \(folder.name)")
          }
          Picker("Run", selection: recipeBinding($folder)) {
            // A deleted recipe still shows, since the folder keeps its own copy.
            let extra = choices.contains { $0.id == folder.recipe.id } ? [] : [folder.recipe]
            ForEach(choices + extra) { Text($0.displayName).tag($0.id) }
          }
          Picker("Afterwards", selection: $folder.afterwards) {
            ForEach(WatchFolder.Afterwards.allCases, id: \.self) { Text($0.title).tag($0) }
          }
        }
        .padding(.vertical, 2)
      }
      Button("Add Folder…") { model.addWatchFolder() }
        .accessibilityIdentifier("addWatchFolder")
    } header: {
      Text("Watch Folders")
    } footer: {
      Text(
        "Results go into a \"\(WatchFolder.outputFolderName)\" folder inside each watched folder. Files already there when watching starts are left alone."
      )
    }
  }

  /// Selects by id, so a saved recipe that's edited later is picked up again by its id.
  private func recipeBinding(_ folder: Binding<WatchFolder>) -> Binding<UUID> {
    Binding {
      folder.wrappedValue.recipe.id
    } set: { id in
      if let recipe = choices.first(where: { $0.id == id }) { folder.wrappedValue.recipe = recipe }
    }
  }
}
