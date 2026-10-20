import DropCore
import SwiftUI

/// The Recipes section of Settings: saved chains of steps, each offered on the Actions wheel.
struct RecipesSection: View {
  @EnvironmentObject private var model: AppModel
  @State private var editing: Recipe?

  var body: some View {
    Section {
      if model.settings.recipes.isEmpty {
        Text("Chain steps like resize, convert and rename into one action you can drop files on.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      ForEach(model.settings.recipes) { recipe in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(recipe.displayName)
            Text(recipe.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
          Spacer()
          Button("Edit") { editing = recipe }
            .accessibilityLabel("Edit \(recipe.displayName)")
          Button(role: .destructive) {
            model.settings.recipes.removeAll { $0.id == recipe.id }
          } label: {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
          .help("Delete \(recipe.displayName)")
          .accessibilityLabel("Delete \(recipe.displayName)")
        }
      }
      HStack {
        Button("New Recipe…") { editing = Recipe(name: "", steps: []) }
          .accessibilityIdentifier("newRecipe")
        if model.settings.recipes.isEmpty {
          Button("Add Example") { model.settings.recipes += Recipe.examples }
        }
      }
    } header: {
      Text("Recipes")
    } footer: {
      Text("Recipes appear on the Actions wheel. Each step works on the files the step before it made.")
    }
    .sheet(item: $editing) { recipe in
      RecipeEditor(recipe: recipe) { saved in
        if let index = model.settings.recipes.firstIndex(where: { $0.id == saved.id }) {
          model.settings.recipes[index] = saved
        } else {
          model.settings.recipes.append(saved)
        }
        editing = nil
      } onCancel: {
        editing = nil
      }
    }
  }
}

/// Edits one recipe in a sheet: its name and its ordered steps.
struct RecipeEditor: View {
  @State var recipe: Recipe
  let onSave: (Recipe) -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField("Name", text: $recipe.name, prompt: Text("Web-ready images"))
        }
        Section {
          if recipe.steps.isEmpty {
            Text("Add the first step below.").foregroundStyle(.secondary)
          }
          ForEach(Array(recipe.steps.indices), id: \.self) { index in
            RecipeStepRow(
              number: index + 1, step: $recipe.steps[index],
              canMoveUp: index > 0, canMoveDown: index < recipe.steps.count - 1
            ) { action in
              switch action {
              case .up: recipe.steps.swapAt(index, index - 1)
              case .down: recipe.steps.swapAt(index, index + 1)
              case .delete: recipe.steps.remove(at: index)
              }
            }
          }
          Menu("Add Step") {
            ForEach(StepKind.allCases) { kind in
              Button(kind.title) { recipe.steps.append(kind.defaultStep) }
            }
          }
          .accessibilityIdentifier("addRecipeStep")
        } header: {
          Text("Steps")
        } footer: {
          Text("Rename patterns can use {name}, {n} for 1, 2, 3… and {date}.")
        }
      }
      .formStyle(.grouped)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button("Save") { onSave(recipe) }
          .buttonStyle(.glassProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(recipe.steps.isEmpty)
      }
      .padding(DesignTokens.Spacing.inset)
    }
    .frame(width: 460, height: 480)
  }
}

/// The kinds of step the editor offers, each with a sensible starting value.
enum StepKind: String, CaseIterable, Identifiable {
  case convertImage, convertAudio, convertVideo, convertDocument, compress, resize, makePDF, rename
  case transcribe, summarize, renameByContent

  var id: String { rawValue }

  var title: String {
    switch self {
    case .convertImage: "Convert Image"
    case .convertAudio: "Convert Audio"
    case .convertVideo: "Convert Video"
    case .convertDocument: "Convert Document"
    case .compress: "Compress"
    case .resize: "Resize"
    case .makePDF: "Make PDF"
    case .rename: "Rename"
    case .transcribe: "Transcribe to Subtitles"
    case .summarize: "Summarize"
    case .renameByContent: "Rename from Content"
    }
  }

  var defaultStep: RecipeStep {
    switch self {
    case .convertImage: .action(.convertImage(.jpeg))
    case .convertAudio: .action(.convertAudio(AudioOutput.allCases[0]))
    case .convertVideo: .action(.convertVideo(VideoOutput.allCases[0]))
    case .convertDocument: .action(.convertDocument(DocumentOutput.allCases[0]))
    case .compress: .action(.compress)
    case .resize: .action(.resize(.maxEdge(1600)))
    case .makePDF: .action(.makePDF)
    case .rename: .rename("{name}-{n}")
    case .transcribe: .action(.transcribe)
    case .summarize: .action(.summarize)
    case .renameByContent: .action(.renameByContent)
    }
  }

  init(_ step: RecipeStep) {
    switch step {
    case .action(.convertImage): self = .convertImage
    case .action(.convertAudio): self = .convertAudio
    case .action(.convertVideo): self = .convertVideo
    case .action(.convertDocument): self = .convertDocument
    case .action(.compress): self = .compress
    case .action(.resize): self = .resize
    case .action(.makePDF): self = .makePDF
    case .rename: self = .rename
    case .action(.transcribe): self = .transcribe
    case .action(.summarize): self = .summarize
    case .action(.renameByContent): self = .renameByContent
    }
  }
}

/// One step: its kind, its options, and buttons to move or remove it.
struct RecipeStepRow: View {
  enum Edit { case up, down, delete }

  let number: Int
  @Binding var step: RecipeStep
  let canMoveUp: Bool
  let canMoveDown: Bool
  let onEdit: (Edit) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
        Picker(
          "Step \(number)",
          selection: Binding(get: { StepKind(step) }, set: { step = $0.defaultStep })
        ) {
          ForEach(StepKind.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
        Spacer()
        Group {
          Button {
            onEdit(.up)
          } label: {
            Image(systemName: "chevron.up")
          }
          .disabled(!canMoveUp)
          .help("Move up")
          .accessibilityLabel("Move step \(number) up")
          Button {
            onEdit(.down)
          } label: {
            Image(systemName: "chevron.down")
          }
          .disabled(!canMoveDown)
          .help("Move down")
          .accessibilityLabel("Move step \(number) down")
          Button(role: .destructive) {
            onEdit(.delete)
          } label: {
            Image(systemName: "minus.circle")
          }
          .help("Remove step")
          .accessibilityLabel("Remove step \(number)")
        }
        .buttonStyle(.borderless)
      }
      options
    }
  }

  @ViewBuilder private var options: some View {
    switch step {
    case .action(.convertImage(let format)):
      Picker(
        "Format",
        selection: Binding(get: { format }, set: { step = .action(.convertImage($0)) })
      ) {
        ForEach(ImageFormat.allCases.filter(\.isWritable), id: \.self) { Text($0.displayName).tag($0) }
      }
    case .action(.convertAudio(let output)):
      Picker("Format", selection: Binding(get: { output }, set: { step = .action(.convertAudio($0)) })) {
        ForEach(AudioOutput.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }
    case .action(.convertVideo(let output)):
      Picker("Format", selection: Binding(get: { output }, set: { step = .action(.convertVideo($0)) })) {
        ForEach(VideoOutput.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }
    case .action(.convertDocument(let output)):
      Picker(
        "Format", selection: Binding(get: { output }, set: { step = .action(.convertDocument($0)) })
      ) {
        ForEach(DocumentOutput.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }
    case .action(.resize(let spec)):
      ResizeStepOptions(spec: spec) { step = .action(.resize($0)) }
    case .rename(let pattern):
      TextField("Pattern", text: Binding(get: { pattern }, set: { step = .rename($0) }))
    case .action(.compress):
      Text("Images and PDFs at your quality setting; videos at medium strength.")
        .font(.caption).foregroundStyle(.secondary)
    case .action(.makePDF):
      Text("One PDF from images, or one merged PDF from PDFs.")
        .font(.caption).foregroundStyle(.secondary)
    case .action(.transcribe):
      Text("Speech in audio and video becomes SRT subtitles, transcribed on this Mac.")
        .font(.caption).foregroundStyle(.secondary)
    case .action(.summarize):
      Text("A Markdown summary of documents, PDFs and recordings, by Apple Intelligence.")
        .font(.caption).foregroundStyle(.secondary)
    case .action(.renameByContent):
      Text("A descriptive name from what's in each file, by Apple Intelligence.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}

/// Longest side in pixels, or a percentage.
private struct ResizeStepOptions: View {
  let spec: ResizeSpec
  let onChange: (ResizeSpec) -> Void

  private var isPercent: Bool {
    if case .percent = spec { return true }
    return false
  }

  var body: some View {
    HStack {
      Picker(
        "Resize by",
        selection: Binding(
          get: { isPercent },
          set: { onChange($0 ? .percent(50) : .maxEdge(1600)) })
      ) {
        Text("Longest side").tag(false)
        Text("Percentage").tag(true)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      switch spec {
      case .percent(let percent):
        TextField(
          "Percent",
          value: Binding(
            get: { percent },
            set: {
              onChange(
                .percent(min(max($0, ResizeSpec.percentRange.lowerBound), ResizeSpec.percentRange.upperBound))
              )
            }),
          format: .number
        )
        .frame(width: 60)
        Text("%")
      case .maxEdge(let edge):
        TextField(
          "Pixels",
          value: Binding(
            get: { edge },
            set: {
              onChange(
                .maxEdge(min(max($0, ResizeSpec.edgeRange.lowerBound), ResizeSpec.edgeRange.upperBound)))
            }),
          format: .number
        )
        .frame(width: 70)
        Text("px")
      }
    }
    .labelsHidden()
  }
}
