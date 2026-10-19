import Foundation
import ImageIO
import Testing

@testable import DropCore

@Suite struct RecipeTests {
  @Test func stepsRoundTripThroughSpecsAndJSON() throws {
    let recipe = Recipe(
      name: "Web",
      steps: [
        .action(.resize(.percent(50))), .action(.compress), .action(.convertImage(.jpeg)),
        .rename("{name}-{n}"),
      ])
    for step in recipe.steps { #expect(RecipeStep(spec: step.spec) == step) }
    let decoded = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe))
    #expect(decoded == recipe)
    #expect(RecipeStep(spec: "explode") == nil)
    #expect(recipe.summary == "Resize to 50% → Compress → Convert to JPEG → Rename to {name}-{n}")
  }

  @Test func settingsKeepRecipesAndOlderSettingsLoad() throws {
    var settings = AppSettings()
    settings.recipes = Recipe.examples
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.recipes == Recipe.examples)
    // Settings saved before recipes existed still load, with none.
    let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"quality":0.5}"#.utf8))
    #expect(old.recipes.isEmpty)
  }

  @Test func renamePatternFillsTokensAndStaysSafe() {
    let date = Date(timeIntervalSince1970: 1_792_400_000)  // 2026-10-19 (UTC)
    #expect(RenamePattern.apply("{name}-{n}", name: "trip", index: 2, count: 12, date: date) == "trip-03")
    #expect(RenamePattern.apply("Holiday {n}", name: "x", index: 0, count: 3, date: date) == "Holiday 1")
    #expect(RenamePattern.apply("{date} {name}", name: "a", index: 0, count: 1, date: date).hasSuffix(" a"))
    #expect(RenamePattern.apply("a/b:c", name: "x", index: 0, count: 1) == "a-b-c")
    #expect(RenamePattern.apply("  ", name: "keep", index: 0, count: 1) == "keep")
    #expect(RenamePattern.apply("..", name: "keep", index: 0, count: 1) == "keep")
  }

  @Test func chainsStepsAndKeepsOnlyTheLastFiles() async throws {
    let dir = try TempDir()
    let a = try Fixtures.writeImage(to: dir.file("a.png"), type: "public.png", width: 400, height: 200)
    let b = try Fixtures.writeImage(to: dir.file("b.png"), type: "public.png", width: 300, height: 300)
    let recipe = Recipe(
      name: "Small JPEGs",
      steps: [.action(.resize(.maxEdge(100))), .action(.convertImage(.jpeg)), .rename("{name}-small")])

    let result = await RecipeRunner.run(recipe, on: [a, b], settings: AppSettings(), engine: JobEngine())

    #expect(result.failures.isEmpty)
    #expect(Set(result.outputs.map(\.lastPathComponent)).count == 2)
    for output in result.outputs {
      // Final files land next to their originals, not in the working folder.
      #expect(output.deletingLastPathComponent().standardizedFileURL == dir.url.standardizedFileURL)
      #expect(output.pathExtension == "jpg")
      #expect(output.deletingPathExtension().lastPathComponent.hasSuffix("-small"))
      let props = Fixtures.properties(of: output)
      let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
      let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
      #expect(max(width, height) == 100)
    }
    // Originals are untouched and no intermediate files are left beside them.
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
    #expect(names.contains("a.png") && names.contains("b.png"))
    #expect(names.count == 4)
  }

  @Test func renameOnlyCopiesOriginalsToANewFolder() async throws {
    let dir = try TempDir()
    let a = try Fixtures.writeImage(to: dir.file("a.png"), type: "public.png")
    let out = dir.file("out")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let result = await RecipeRunner.run(
      Recipe(name: "Number", steps: [.rename("photo {n}")]), on: [a],
      settings: AppSettings(outputLocation: .folder(out)), engine: JobEngine())
    #expect(result.failures.isEmpty)
    #expect(result.outputs.map(\.lastPathComponent) == ["photo 1.png"])
    #expect(FileManager.default.fileExists(atPath: a.path))
  }

  @Test func stopsWhenAStepMakesNothing() async throws {
    let dir = try TempDir()
    let pdf = try Fixtures.writePDF(to: dir.file("doc.pdf"), pages: 1)
    let result = await RecipeRunner.run(
      Recipe(name: "Bad", steps: [.action(.resize(.percent(50))), .rename("x")]), on: [pdf],
      settings: AppSettings(), engine: JobEngine())
    #expect(result.outputs.isEmpty)
    #expect(result.failures.contains { $0.message.contains("made no files") })
    let empty = await RecipeRunner.run(Recipe(name: "Empty", steps: []), on: [pdf], settings: AppSettings())
    #expect(empty.failures.map(\.message) == ["Empty has no steps."])
  }
}
