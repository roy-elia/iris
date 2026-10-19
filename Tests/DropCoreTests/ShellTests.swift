import CoreGraphics
import Foundation
import Testing

@testable import DropCore

@Suite struct FloatStackTests {
  @Test func addsWithoutDuplicatesNewestFirst() {
    let a = URL(fileURLWithPath: "/tmp/a.png")
    let b = URL(fileURLWithPath: "/tmp/b.png")
    let c = URL(fileURLWithPath: "/tmp/c.png")
    var stack = FloatStack(urls: [a, b])
    #expect(stack.urls == [b, a])
    #expect(stack.add([b, c, c]) == 1)
    #expect(stack.urls == [c, b, a])
    stack.remove(b)
    #expect(stack.urls == [c, a])
  }

  @Test func prunesMissingFiles() throws {
    let dir = try TempDir()
    let kept = dir.file("kept.txt")
    try "x".write(to: kept, atomically: true, encoding: .utf8)
    var stack = FloatStack(urls: [kept, dir.file("gone.txt")])
    stack.pruneMissing()
    #expect(stack.urls == [kept.standardizedFileURL])
  }

  @Test func storeRoundTripsAndDropsEmptyStacks() throws {
    let dir = try TempDir()
    let file = dir.file("a.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)
    let store = FloatStore(fileURL: dir.file("floats.json"))
    let stack = FloatStack(urls: [file], edge: .left, position: 0.3)
    try store.save([stack, FloatStack(urls: [dir.file("missing.txt")])])
    let loaded = store.load()
    #expect(loaded.count == 1)
    #expect(loaded.first?.id == stack.id && loaded.first?.edge == .left && loaded.first?.position == 0.3)
  }

  @Test func snapsToTheNearerEdge() {
    let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let left = FloatPlacement.snap(CGPoint(x: 300, y: 25 + 875 * 0.25), in: screen)
    #expect(left.edge == .left && abs(left.position - 0.25) < 0.001)
    let right = FloatPlacement.snap(CGPoint(x: 1300, y: 5000), in: screen)
    #expect(right.edge == .right && right.position == 1)
  }

  @Test func collapsedTabsTuckAndExpandedOnesStayOnScreen() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 60, height: 100)
    let tucked = FloatPlacement.frame(size: size, edge: .right, position: 0.5, in: screen, expanded: false)
    #expect(tucked.maxX == 1000 + FloatPlacement.tuck && tucked.midY == 400)
    let open = FloatPlacement.frame(
      size: CGSize(width: 220, height: 400), edge: .left, position: 1, in: screen, expanded: true)
    #expect(open.minX == 8 && open.maxY == 792)
  }
}

@Suite struct UpdateCheckTests {
  private func release(
    _ tag: String, draft: Bool = false, pre: Bool = false, page: String = "https://example.com/r"
  )
    -> Data
  {
    Data(
      """
      {"tag_name":"\(tag)","html_url":"\(page)","body":"Fixes","draft":\(draft),"prerelease":\(pre)}
      """.utf8)
  }

  @Test func comparesVersionsNumerically() {
    #expect(UpdateChecker.isNewer("1.10.0", than: "1.9.3"))
    #expect(UpdateChecker.isNewer("v2", than: "1.99"))
    #expect(!UpdateChecker.isNewer("v1.2", than: "1.2.0"))
    #expect(!UpdateChecker.isNewer("1.2.0", than: "1.3"))
  }

  @Test func reportsOnlyNewerFinalReleases() throws {
    let update = try UpdateChecker.parse(release("v0.2.0"), current: "0.1.0")
    #expect(
      update
        == AvailableUpdate(version: "0.2.0", pageURL: URL(string: "https://example.com/r")!, notes: "Fixes"))
    #expect(try UpdateChecker.parse(release("v0.1.0"), current: "0.1.0") == nil)
    #expect(try UpdateChecker.parse(release("v9", draft: true), current: "0.1.0") == nil)
    #expect(try UpdateChecker.parse(release("v9", pre: true), current: "0.1.0") == nil)
    #expect(throws: DropError.self) {
      try UpdateChecker.parse(release("v9", page: "http://insecure"), current: "0.1")
    }
    #expect(throws: DropError.self) { try UpdateChecker.parse(Data("[]".utf8), current: "0.1") }
  }

  @Test func needsAnHTTPSFeed() {
    // The test bundle has no feed configured, so the app never checks.
    #expect(UpdateChecker.feedURL() == nil)
  }
}

@Suite struct ShellSettingsTests {
  @Test func newSettingsDefaultAndDecodeTolerantly() throws {
    let defaults = AppSettings()
    #expect(defaults.wheelTheme == .dark && !defaults.checkForUpdates)
    let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"quality":0.5}"#.utf8))
    #expect(old.wheelTheme == .dark && !old.checkForUpdates)
    var changed = AppSettings()
    changed.wheelTheme = .tinted
    changed.checkForUpdates = true
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(changed))
    #expect(back.wheelTheme == .tinted && back.checkForUpdates)
    let bad = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"wheelTheme":"neon"}"#.utf8))
    #expect(bad.wheelTheme == .dark)
  }
}
