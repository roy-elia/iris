import Foundation
import Testing

@testable import DropCore

@Suite struct BatchEventTests {
  private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [Processor.FileEvent] = []
    func add(_ e: Processor.FileEvent) { lock.withLock { events.append(e) } }
    var all: [Processor.FileEvent] { lock.withLock { events } }
  }

  @Test func reportsEachFileStartingAndFinishing() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = try Fixtures.writeCGImage(Fixtures.noisyImage(width: 40, height: 40), to: dir.appendingPathComponent("a.png"))
    let b = try Fixtures.writeCGImage(Fixtures.noisyImage(width: 40, height: 40), to: dir.appendingPathComponent("b.png"))
    let files = try [a, b].map { try DroppedFile.load($0) }

    let log = Log()
    var processor = Processor(settings: AppSettings())
    processor.fileEvents = { log.add($0) }
    let result = await processor.run(.convert(.jpeg, quality: 0.8), on: files)

    #expect(result.outputs.count == 2)
    #expect(
      log.all.map(\.name) == ["a.png", "a.png", "b.png", "b.png"])
    #expect(log.all.map(\.phase) == [.started, .done, .started, .done])
  }

  @Test func jobHandleForwardsFileEvents() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = try Fixtures.writeCGImage(Fixtures.noisyImage(width: 40, height: 40), to: dir.appendingPathComponent("a.png"))
    let files = [try DroppedFile.load(a)]

    let log = Log()
    let handle = JobEngine().submit(
      ProcessorJob(operation: .convert(.png, quality: 1), files: files, settings: AppSettings()))
    handle.observeFiles { log.add($0) }
    _ = await handle.result()
    #expect(log.all.last?.phase == .done)
  }
}
