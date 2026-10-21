import Foundation
import Testing

@testable import DropCore

@Suite struct WheelPageFlipTests {
  private func sample(_ time: Double, _ kind: String?, inside: Bool = false) -> DragTrigger<String>.Sample {
    .init(time: time, buttonDown: true, pasteboardChangeCount: 5, kind: kind, dragInsideWheel: inside)
  }

  @Test func pressingTheOpenWheelsModifierAgainTurnsThePage() {
    var trigger = DragTrigger<String>(graceInterval: 0.45)
    trigger.mouseDown(pasteboardChangeCount: 4)
    #expect(trigger.update(sample(0.0, nil)) == .none)
    #expect(trigger.update(sample(0.1, "tools")) == .show("tools"))
    // Holding the key doesn't turn the page.
    #expect(trigger.update(sample(0.2, "tools")) == .none)
    // Let go, then press again.
    #expect(trigger.update(sample(0.3, nil, inside: true)) == .none)
    #expect(trigger.update(sample(0.4, "tools")) == .nextPage)
    #expect(trigger.update(sample(0.5, "tools")) == .none)
  }

  @Test func anotherWheelsModifierSwitchesInsteadOfTurning() {
    var trigger = DragTrigger<String>(graceInterval: 0.45)
    trigger.mouseDown(pasteboardChangeCount: 4)
    _ = trigger.update(sample(0.0, nil))
    _ = trigger.update(sample(0.1, "tools"))
    #expect(trigger.update(sample(0.2, nil)) == .none)
    #expect(trigger.update(sample(0.3, "convert")) == .show("convert"))
  }
}

@Suite struct QRMakeTests {
  @Test func linkFilesBecomeScannableCodes() throws {
    let link = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).webloc")
    try PropertyListSerialization.data(fromPropertyList: ["URL": "https://example.com/a?b=1"], format: .xml, options: 0)
      .write(to: link)
    defer { try? FileManager.default.removeItem(at: link) }
    #expect(QROps.canMake(from: FileKind(url: link)))
    #expect(QROps.payload(for: link) == "https://example.com/a?b=1")

    let png = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: png) }
    try ImageOps.write(try QROps.make("https://example.com/a?b=1"), as: .png, quality: 1, to: png)
    #expect(try QROps.read(png) == ["https://example.com/a?b=1"])
  }

  @Test func imagesAndLongTextAreNotEncoded() {
    #expect(!QROps.canMake(from: .image(.png)))
  }
}
