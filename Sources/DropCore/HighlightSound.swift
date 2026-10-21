import Foundation

/// The wheel's highlight sound, synthesised in code: a crisp, solid mechanical click, like a
/// good keyboard switch or a detent. Three layers: a 2 ms burst of noise for the sharp
/// transient, two damped tones for the bright "tock", and a low thump for weight. The noise
/// comes from a fixed-seed generator, so the sound is identical on every run and the app
/// ships no sound file for it beyond Resources/Highlight.wav.
public enum HighlightSound {
  public static let sampleRate = 44_100
  /// Length in seconds, including the fade to silence.
  public static let duration = 0.06
  /// Peak level, under full scale so it sits comfortably next to system sounds.
  public static let peak = 0.4

  /// The sound as 16-bit mono samples.
  public static func samples() -> [Int16] {
    let count = Int(Double(sampleRate) * duration)
    let tones: [(frequency: Double, level: Double, decay: Double)] = [
      (2_350, 0.55, 0.0045),  // the tock's body
      (3_900, 0.30, 0.0028),  // its brightness
      (190, 0.75, 0.0100),  // the thump
    ]
    var seed: UInt32 = 0x1F2E3D4C
    var previousNoise = 0.0
    var raw: [Double] = []
    raw.reserveCapacity(count)
    for i in 0..<count {
      let t = Double(i) / Double(sampleRate)
      seed = seed &* 1_664_525 &+ 1_013_904_223
      let white = Double(seed >> 8) / Double(1 << 24) * 2 - 1
      // Differencing the noise keeps only its highs, so the transient is sharp, not hissy.
      let noise = white - previousNoise
      previousNoise = white
      var value = 0.9 * noise * exp(-t / 0.0007)
      for tone in tones {
        value += tone.level * exp(-t / tone.decay) * sin(2 * .pi * tone.frequency * t)
      }
      // A near-instant rise starts the sound at exactly zero; a short cosine taper over the
      // last 8 ms ends it at zero, so the file itself never pops.
      let rise = min(t / 0.0002, 1)
      let tail = duration - t
      let taper = tail < 0.008 ? 0.5 - 0.5 * cos(.pi * max(tail, 0) / 0.008) : 1
      raw.append(value * rise * taper)
    }
    let top = raw.map { abs($0) }.max() ?? 1
    return raw.map { Int16(($0 / top * peak * Double(Int16.max)).rounded()) }
  }

  /// The sound as a WAV file in memory, ready for `NSSound(data:)`.
  public static func wavData() -> Data {
    let pcm = samples()
    let dataSize = UInt32(pcm.count * 2)
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
      withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36) + dataSize)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))  // fmt chunk size
    append(UInt16(1))  // PCM
    append(UInt16(1))  // mono
    append(UInt32(sampleRate))
    append(UInt32(sampleRate * 2))  // byte rate
    append(UInt16(2))  // block align
    append(UInt16(16))  // bits per sample
    data.append(contentsOf: Array("data".utf8))
    append(dataSize)
    for sample in pcm { append(sample) }
    return data
  }
}
