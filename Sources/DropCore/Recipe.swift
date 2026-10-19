import Foundation

/// A saved chain of steps run on dropped files in order: each step works on the files the
/// previous one made, and only the last step's files are kept.
public struct Recipe: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var steps: [RecipeStep]

  public init(id: UUID = UUID(), name: String, steps: [RecipeStep]) {
    self.id = id
    self.name = name
    self.steps = steps
  }

  /// The name to show, never empty.
  public var displayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Untitled Recipe" : trimmed
  }

  /// "Resize to 50% → Compress → Rename", for menus and help.
  public var summary: String {
    steps.isEmpty ? "No steps" : steps.map(\.title).joined(separator: " → ")
  }

  /// A starting point for new users.
  public static let examples: [Recipe] = [
    Recipe(
      name: "Web-ready images",
      steps: [.action(.resize(.maxEdge(1600))), .action(.convertImage(.jpeg)), .rename("{name}-web")])
  ]
}

/// One step of a recipe: any Quick Action, or renaming the files so far.
public enum RecipeStep: Equatable, Hashable, Sendable, Codable {
  case action(QuickAction)
  /// A name pattern; see `RenamePattern`.
  case rename(String)

  public init?(spec: String) {
    if spec.lowercased().hasPrefix("rename:") {
      self = .rename(String(spec.dropFirst("rename:".count)))
    } else if let action = QuickAction(spec: spec) {
      self = .action(action)
    } else {
      return nil
    }
  }

  /// Stored as the same short text form the `--run` command line uses.
  public var spec: String {
    switch self {
    case .action(let action): action.spec
    case .rename(let pattern): "rename:\(pattern)"
    }
  }

  public var title: String {
    switch self {
    case .action(let action): action.title
    case .rename(let pattern): "Rename to \(pattern.isEmpty ? RenamePattern.nameToken : pattern)"
    }
  }

  public init(from decoder: any Decoder) throws {
    let spec = try decoder.singleValueContainer().decode(String.self)
    guard let step = RecipeStep(spec: spec) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: spec))
    }
    self = step
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(spec)
  }
}

/// Builds file names from a pattern with `{name}` (the current name without extension),
/// `{n}` (1, 2, 3… padded to the same width) and `{date}` (today, as 2026-10-19).
public enum RenamePattern {
  public static let nameToken = "{name}"
  public static let numberToken = "{n}"
  public static let dateToken = "{date}"

  /// The new name without extension for file `index` (0-based) of `count`.
  public static func apply(
    _ pattern: String, name: String, index: Int, count: Int, date: Date = Date()
  ) -> String {
    let template = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !template.isEmpty else { return name }
    let width = String(max(count, 1)).count
    let number = String(index + 1)
    let padded = String(repeating: "0", count: max(width - number.count, 0)) + number
    let day = date.formatted(.iso8601.year().month().day())
    let result =
      template
      .replacingOccurrences(of: nameToken, with: name)
      .replacingOccurrences(of: numberToken, with: padded)
      .replacingOccurrences(of: dateToken, with: day)
      // Path separators and Finder's colon can't be part of a name.
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty || result == "." || result == ".." ? name : result
  }
}

/// Runs a `Recipe`. Each step's files go to a private working folder; the last step's files
/// are then moved where the settings say, next to the original they came from.
public enum RecipeRunner {
  public static func run(
    _ recipe: Recipe, on urls: [URL], settings: AppSettings, engine: JobEngine = .shared,
    fileManager: FileManager = .default, date: Date = Date(),
    progress: (@Sendable (Double) -> Void)? = nil
  ) async -> OperationResult {
    var result = OperationResult()
    guard !recipe.steps.isEmpty else {
      result.failures.append(.init(file: "", message: "\(recipe.displayName) has no steps."))
      return result
    }
    guard !urls.isEmpty else {
      result.failures.append(.init(file: "", message: "No files were given."))
      return result
    }
    let work = fileManager.temporaryDirectory
      .appendingPathComponent("FileDropUtility-Recipe-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: work) }

    // Each current file remembers the original it came from, to decide where it ends up.
    var current = urls.map { (url: $0, origin: $0) }
    let stepCount = Double(recipe.steps.count)

    for (index, step) in recipe.steps.enumerated() {
      if Task.isCancelled {
        result.failures.append(.init(file: "", message: "\(recipe.displayName) was cancelled."))
        return result
      }
      let folder = work.appendingPathComponent("step-\(index + 1)", isDirectory: true)
      do {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
      } catch {
        result.failures.append(.init(file: "", message: error.localizedDescription))
        return result
      }
      switch step {
      case .action(let action):
        var stepSettings = settings
        stepSettings.outputLocation = .folder(folder)
        let stepResult = await QuickActionRunner.run(
          action, on: current.map(\.url), settings: stepSettings, engine: engine
        ) { fraction in
          progress?((Double(index) + fraction) / stepCount)
        }
        result.failures += stepResult.failures
        result.notes += stepResult.notes
        current = stepResult.outputs.map { ($0, origin(of: $0, among: current)) }
      case .rename(let pattern):
        var renamed: [(url: URL, origin: URL)] = []
        var reserved = Set<URL>()
        for (fileIndex, file) in current.enumerated() {
          let stem = file.url.deletingPathExtension().lastPathComponent
          let newStem = RenamePattern.apply(
            pattern, name: stem, index: fileIndex, count: current.count, date: date)
          let ext = file.url.pathExtension
          let desired = folder.appendingPathComponent(ext.isEmpty ? newStem : "\(newStem).\(ext)")
          let target = OutputNamer.uniqueURL(for: desired, reserved: reserved, fileManager: fileManager)
          reserved.insert(target.standardizedFileURL)
          do {
            // Copy, never move: before any other step these are the user's originals.
            try fileManager.copyItem(at: file.url, to: target)
            renamed.append((target, file.origin))
          } catch {
            result.failures.append(
              .init(file: file.url.lastPathComponent, message: error.localizedDescription))
          }
        }
        current = renamed
        progress?(Double(index + 1) / stepCount)
      }
      if current.isEmpty {
        result.failures.append(
          .init(file: "", message: "Step \(index + 1), \(step.title), made no files, so the recipe stopped."))
        return result
      }
    }

    var reserved = Set<URL>()
    for file in current {
      let folder = OutputNamer.directory(for: file.origin, location: settings.outputLocation)
      let desired = folder.appendingPathComponent(file.url.lastPathComponent)
      let target = OutputNamer.uniqueURL(for: desired, reserved: reserved, fileManager: fileManager)
      reserved.insert(target.standardizedFileURL)
      do {
        try fileManager.moveItem(at: file.url, to: target)
        result.outputs.append(target)
      } catch {
        result.failures.append(.init(file: file.url.lastPathComponent, message: error.localizedDescription))
      }
    }
    return result
  }

  /// The original an output came from: the input whose name it starts with (outputs keep
  /// their source's name), else the first input, as for a PDF made from many files.
  static func origin(of output: URL, among inputs: [(url: URL, origin: URL)]) -> URL {
    let name = output.deletingPathExtension().lastPathComponent
    let match =
      inputs
      .filter { name.hasPrefix($0.url.deletingPathExtension().lastPathComponent) }
      .max {
        $0.url.deletingPathExtension().lastPathComponent.count
          < $1.url.deletingPathExtension().lastPathComponent.count
      }
    return match?.origin ?? inputs.first?.origin ?? output
  }
}
