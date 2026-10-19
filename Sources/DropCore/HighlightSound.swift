import Foundation

/// The wheel's highlight sound, synthesised in code: a short, soft two-tone tap. It is built
/// from plain sine partials with a quick attack and an exponential fade, so the app ships no
/// sound file for it.
public enum HighlightSound {
  public static let sampleRate = 44_100
  /// Length in seconds, including the fade to silence.
  public static let duration = 0.075
  /// Peak level, well under full scale so it stays soft next to system sounds.
  public static let peak = 0.3

  /// The sound as 16-bit mono samples.
  public static func samples() -> [Int16] {
    let count = Int(Double(sampleRate) * duration)
    // A low fundamental with a quieter fifth above it, both fading fast; the fifth
    // fades faster, so the tap softens as it dies away.
    let partials: [(frequency: Double, level: Double, decay: Double)] = [
      (1_174.66, 1.0, 0.020),  // D6
      (1_760.00, 0.35, 0.012),  // A6
    ]
    let attack = 0.003
    let total = partials.reduce(0) { $0 + $1.level }
    return (0..<count).map { i in
      let t = Double(i) / Double(sampleRate)
      let rise = min(t / attack, 1)
      // A short cosine taper over the last 10 ms ends exactly at zero, without a click.
      let tail = duration - t
      let taper = tail < 0.01 ? 0.5 - 0.5 * cos(.pi * max(tail, 0) / 0.01) : 1
      var value = 0.0
      for p in partials {
        value += p.level * exp(-t / p.decay) * sin(2 * .pi * p.frequency * t)
      }
      return Int16((value / total * rise * taper * peak * Double(Int16.max)).rounded())
    }
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
