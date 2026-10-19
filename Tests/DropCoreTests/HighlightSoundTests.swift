import Foundation
import Testing

@testable import DropCore

@Suite struct HighlightSoundTests {
  @Test func isShortSoftAndClickFree() {
    let samples = HighlightSound.samples()
    #expect(samples.count == Int(Double(HighlightSound.sampleRate) * HighlightSound.duration))
    let peak = samples.map { abs(Int($0)) }.max() ?? 0
    #expect(peak > 0)
    #expect(Double(peak) <= HighlightSound.peak * Double(Int16.max) + 1)
    // Starts and ends at silence, so it never clicks.
    #expect(samples.first == 0)
    #expect(abs(Int(samples.last ?? 1)) <= 1)
  }

  @Test func wavHeaderDescribesTheSamples() {
    let data = HighlightSound.wavData()
    #expect(data.prefix(4) == Data("RIFF".utf8))
    #expect(data.subdata(in: 8..<16) == Data("WAVEfmt ".utf8))
    #expect(data.count == 44 + HighlightSound.samples().count * 2)
  }
}
