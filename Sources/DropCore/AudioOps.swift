import Foundation

/// Audio work, done with the bundled ffmpeg: conversion, edits in one filter pass, silence
/// detection, waveform peaks, and visualizer videos.
public enum AudioOps {
  static let lossyBitrateKbps = 192
  static let bleepFrequency = 1000
  /// Bleep peak level. ffmpeg's sine source peaks at 1/8, hence the ×8 where it's used.
  static let bleepVolume = 0.3
  /// Silence shorter than this isn't trimmed.
  static let minimumSilence = 0.05

  // MARK: Codecs

  /// Encoder arguments for an audio output. `bitDepth` applies to WAV, AIFF and FLAC.
  static func codecArgs(for output: AudioOutput, bitDepth: Int, bitrateKbps: Int? = nil) -> [String] {
    let lossyBitrateKbps = min(max(bitrateKbps ?? Self.lossyBitrateKbps, 32), 320)
    let depth = AudioOutput.bitDepths.contains(bitDepth) ? bitDepth : 16
    switch output {
    case .mp3: return ["-c:a", "libmp3lame", "-b:a", "\(lossyBitrateKbps)k"]
    case .m4a: return ["-c:a", "aac", "-b:a", "\(lossyBitrateKbps)k", "-f", "ipod"]
    case .aac: return ["-c:a", "aac", "-b:a", "\(lossyBitrateKbps)k", "-f", "adts"]
    case .wav: return ["-c:a", "pcm_s\(depth)le"]
    // The bundled ffmpeg has no 32-bit big-endian PCM encoder; 24-bit is AIFF's practical top.
    case .aiff: return ["-c:a", "pcm_s\(min(depth, 24))be"]
    case .flac:
      // FLAC stores 24 bits in 32-bit samples; it has no true 32-bit mode.
      return depth == 16
        ? ["-c:a", "flac", "-sample_fmt", "s16"]
        : ["-c:a", "flac", "-sample_fmt", "s32", "-bits_per_raw_sample", "24"]
    case .ogg: return ["-c:a", "vorbis", "-strict", "-2", "-ac", "2", "-b:a", "\(lossyBitrateKbps)k"]
    case .opus:
      return [
        "-c:a", "opus", "-strict", "-2", "-ar", "48000", "-ac", "2", "-b:a", "\(min(lossyBitrateKbps, 256))k",
      ]
    case .amr: return ["-c:a", "libopencore_amrnb", "-ac", "1", "-b:a", "12.2k"]
    case .awb: return ["-c:a", "libvo_amrwbenc", "-ac", "1", "-b:a", "23.85k", "-f", "amr"]
    // Rendered to WAV first, then compressed by `mac`.
    case .ape: return ["-c:a", "pcm_s\(min(depth, 24))le", "-f", "wav"]
    }
  }

  /// The output format edited files are written in: the source's, if it can be written.
  public static func output(for source: URL) -> AudioOutput {
    switch AudioFormat(fileExtension: source.pathExtension) {
    case .mp3: .mp3
    case .wav: .wav
    case .m4a: .m4a
    case .aac: .aac
    case .flac: .flac
    case .aiff: .aiff
    case .ogg: .ogg
    case .opus: .opus
    case .ape: .ape
    case .amr: .amr
    case .wma, .caf, .ac3, nil: .m4a
    }
  }

  // MARK: Silence

  /// Where the sound starts and stops, ignoring silent ends quieter than `threshold` dBFS.
  public static func audibleRange(
    _ source: URL, threshold: Double, duration: Double? = nil
  ) async throws -> ClosedRange<Double> {
    let total: Double
    if let duration { total = duration } else { total = try await VideoOps.probe(source).duration }
    let out = try await ToolRunner.run(
      .ffmpeg,
      [
        "-hide_banner", "-nostdin", "-i", source.path, "-vn", "-af",
        "silencedetect=noise=\(format(threshold))dB:duration=\(minimumSilence)", "-f", "null", "-",
      ])
    let log = out.stderr
    return audibleRange(silenceLog: log, duration: total)
  }

  /// Parses silencedetect output into the span between leading and trailing silence.
  static func audibleRange(silenceLog log: String, duration: Double) -> ClosedRange<Double> {
    var spans: [(start: Double, end: Double)] = []
    var openStart: Double?
    for line in log.split(whereSeparator: \.isNewline) {
      if let v = value(after: "silence_start: ", in: line) {
        openStart = max(v, 0)
      } else if let v = value(after: "silence_end: ", in: line) {
        spans.append((openStart ?? 0, v))
        openStart = nil
      }
    }
    // Silence that runs to the end of the file has no silence_end line.
    if let openStart { spans.append((openStart, duration)) }
    var start = 0.0
    var end = duration
    if let first = spans.first, first.start <= 0.01 { start = first.end }
    if let last = spans.last, last.end >= duration - 0.01, last.start > start { end = last.start }
    // All silence: keep the whole file rather than nothing.
    if end - start < minimumSilence { return 0...duration }
    return start...end
  }

  private static func value(after marker: String, in line: Substring) -> Double? {
    guard let range = line.range(of: marker) else { return nil }
    let rest = line[range.upperBound...].prefix { "0123456789.-e".contains($0) }
    return Double(rest)
  }

  // MARK: Filters

  /// Sums of `between(t,a,b)` terms for a filter's enable expression.
  static func timeExpression(_ ranges: [BleepRange]) -> String {
    ranges.map { "between(t,\(format($0.start)),\(format($0.end)))" }.joined(separator: "+")
  }

  /// The channel stage: downmix to mono, or set per-side gains for stereo output.
  static func channelFilter(_ recipe: AudioRecipe, inputChannels: Int) -> String? {
    let left = format(recipe.leftGain)
    let right = format(recipe.rightGain)
    let gains = recipe.leftGain != 1 || recipe.rightGain != 1
    switch recipe.channels {
    case .mono:
      return inputChannels >= 2 ? "pan=mono|c0=0.5*c0+0.5*c1" : nil
    case .stereo:
      return inputChannels >= 2
        ? "pan=stereo|c0=\(left)*c0|c1=\(right)*c1" : "pan=stereo|c0=\(left)*c0|c1=\(right)*c0"
    case .keep:
      guard gains else { return nil }
      return inputChannels >= 2 ? "pan=stereo|c0=\(left)*c0|c1=\(right)*c1" : "volume=\(left)"
    }
  }

  /// A filter graph for the recipe, ending in `[out]`. `keep` is the source range to keep.
  static func filterGraph(
    _ recipe: AudioRecipe, keep: ClosedRange<Double>, duration: Double, channels: Int, sampleRate: Int
  ) -> String {
    var chains: [String] = []
    var head = "[0:a]"
    let bleeps = recipe.bleepAll ? [BleepRange(start: 0, end: duration)] : recipe.bleeps
    if !bleeps.isEmpty {
      let when = timeExpression(bleeps)
      let layout = channels >= 2 ? "stereo" : "mono"
      let fmt = "aformat=sample_fmts=fltp:sample_rates=\(sampleRate):channel_layouts=\(layout)"
      chains.append("\(head)\(fmt),volume=volume=0:enable='\(when)'[muted]")
      chains.append(
        "sine=frequency=\(bleepFrequency):sample_rate=\(sampleRate):duration=\(format(duration)),\(fmt),"
          + "volume=\(format(bleepVolume * 8)),volume=volume=0:enable='not(\(when))'[tone]")
      chains.append("[muted][tone]amix=inputs=2:duration=first:normalize=0[bleeped]")
      head = "[bleeped]"
    }
    var stages: [String] = []
    if keep.lowerBound > 0.0005 || keep.upperBound < duration - 0.0005 {
      stages.append("atrim=start=\(format(keep.lowerBound)):end=\(format(keep.upperBound))")
      stages.append("asetpts=PTS-STARTPTS")
    }
    if let pan = channelFilter(recipe, inputChannels: channels) { stages.append(pan) }
    if let target = recipe.normalize {
      stages.append("loudnorm=I=\(format(target.rawValue)):TP=-1.5:LRA=11")
      // loudnorm resamples to 192 kHz internally.
      stages.append("aresample=\(sampleRate)")
    }
    if stages.isEmpty { stages.append("anull") }
    chains.append("\(head)\(stages.joined(separator: ","))[out]")
    return chains.joined(separator: ";")
  }

  static func format(_ v: Double) -> String {
    var s = String(format: "%.3f", v)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s == "-0" ? "0" : s
  }

  // MARK: Operations

  /// Converts an audio file (or a video's audio track), optionally editing it.
  public static func convert(
    _ source: URL, to output: AudioOutput, bitDepth: Int = 16, bitrateKbps: Int? = nil,
    recipe: AudioRecipe = AudioRecipe(),
    destination: URL, progress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    let info = try await VideoOps.probe(source)
    guard info.hasAudio else { throw DropError.wrongInput("\(source.lastPathComponent) has no audio track.") }
    var keep = 0...info.duration
    if recipe.trimStart != nil || recipe.trimEnd != nil {
      let start = recipe.trimStart ?? 0
      let end = recipe.trimEnd ?? info.duration
      if start < 0 || end > info.duration + 0.05 || end - start < minimumSilence {
        throw DropError.wrongInput("Choose a positive time range within the file.")
      }
      keep = start...min(end, info.duration)
    }
    if recipe.trimSilence {
      let audible = try await audibleRange(
        source, threshold: recipe.silenceThreshold, duration: info.duration)
      let start = max(keep.lowerBound, audible.lowerBound)
      let end = min(keep.upperBound, audible.upperBound)
      if end - start >= minimumSilence { keep = start...end }
    }
    for bleep in recipe.bleeps where bleep.end <= bleep.start || bleep.start >= info.duration {
      throw DropError.wrongInput("Bleeps must cover a time range within the file.")
    }
    guard output.isAvailable else {
      throw DropError.wrongInput("\(output.displayName): \(output.unavailableReason ?? "unavailable").")
    }
    let rate = output.fixedSampleRate ?? (info.sampleRate > 0 ? info.sampleRate : 48000)
    let graph = filterGraph(
      recipe, keep: keep, duration: info.duration, channels: max(info.audioChannels, 1), sampleRate: rate)
    var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "info", "-i", source.path]
    args += ["-filter_complex", graph, "-map", "[out]", "-map_metadata", "0", "-vn"]
    args += codecArgs(for: output, bitDepth: bitDepth, bitrateKbps: bitrateKbps)
    if output != .opus { args += ["-ar", "\(rate)"] }
    guard output == .ape else {
      args.append(destination.path)
      try await VideoOps.render(
        args, expectedDuration: keep.upperBound - keep.lowerBound, destination: destination,
        progress: progress)
      return
    }
    // APE: ffmpeg renders a WAV, which Monkey's Audio compresses.
    let wav = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fdu-ape-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: wav) }
    try await VideoOps.render(
      args + [wav.path], expectedDuration: keep.upperBound - keep.lowerBound, destination: wav
    ) { p in
      progress?(p * 0.8)
    }
    try await compressAPE(wav, to: destination)
    progress?(1)
  }

  /// Compresses a WAV to Monkey's Audio at the "normal" level.
  static func compressAPE(_ wav: URL, to destination: URL) async throws {
    do {
      _ = try await ToolRunner.run(.mac, [wav.path, destination.path, "-c2000"])
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
    guard FileManager.default.fileExists(atPath: destination.path) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  /// `count` peak levels (0…1) across the file, for drawing a waveform.
  public static func peaks(_ source: URL, count: Int) async throws -> [Float] {
    let out = try await ToolRunner.run(
      .ffmpeg,
      [
        "-hide_banner", "-nostdin", "-loglevel", "error", "-i", source.path, "-vn", "-ac", "1", "-ar", "4000",
        "-f", "f32le", "-",
      ])
    let samples: [Float] = out.stdout.withUnsafeBytes { raw in
      Array(raw.bindMemory(to: Float.self))
    }
    return bucketPeaks(samples, count: count)
  }

  static func bucketPeaks(_ samples: [Float], count: Int) -> [Float] {
    guard count > 0 else { return [] }
    guard !samples.isEmpty else { return Array(repeating: 0, count: count) }
    return (0..<count).map { i in
      let lo = i * samples.count / count
      let hi = max(lo + 1, (i + 1) * samples.count / count)
      var peak: Float = 0
      for s in samples[lo..<min(hi, samples.count)] { peak = max(peak, abs(s)) }
      return min(peak, 1)
    }
  }

  /// Integrated loudness in LUFS, measured with ebur128.
  public static func loudness(_ source: URL) async throws -> Double {
    let out = try await ToolRunner.run(
      .ffmpeg, ["-hide_banner", "-nostdin", "-i", source.path, "-vn", "-af", "ebur128", "-f", "null", "-"])
    let log = out.stderr
    // The summary's "I:" line comes last.
    guard
      let line = log.split(whereSeparator: \.isNewline).last(where: {
        $0.contains("I:") && $0.contains("LUFS")
      }),
      let v = value(after: "I:", in: Substring(line.replacingOccurrences(of: " ", with: "")))
    else { throw DropError.readFailed(source.lastPathComponent) }
    return v
  }

  /// Renders an MP4 of the audio's waveform over an image or solid colour.
  public static func visualize(
    _ source: URL, recipe: VisualizerRecipe, destination: URL, progress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    let info = try await VideoOps.probe(source)
    guard info.hasAudio else { throw DropError.wrongInput("\(source.lastPathComponent) has no audio track.") }
    let (w, h) = recipe.size.pixels
    var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "info"]
    if let image = recipe.backgroundImage {
      guard FileManager.default.fileExists(atPath: image) else {
        throw DropError.wrongInput("Choose a background image.")
      }
      args += ["-loop", "1", "-framerate", "30", "-i", image]
    } else {
      args += ["-f", "lavfi", "-i", "color=c=\(hex(recipe.backgroundColor)):s=\(w)x\(h):r=30"]
    }
    args += ["-i", source.path]
    args += ["-filter_complex", visualizerGraph(recipe, width: w, height: h)]
    args += [
      "-map", "[v]", "-map", "1:a", "-c:v", "h264_videotoolbox", "-b:v", "4000k", "-pix_fmt", "yuv420p",
    ]
    args += ["-c:a", "aac", "-b:a", "\(lossyBitrateKbps)k", "-shortest", "-t", format(info.duration)]
    args.append(destination.path)
    try await VideoOps.render(
      args, expectedDuration: info.duration, destination: destination, progress: progress)
  }

  static func visualizerGraph(_ recipe: VisualizerRecipe, width w: Int, height h: Int) -> String {
    let color = hex(recipe.color)
    let bandHeight = recipe.style == .wave ? h / 3 : h / 2
    let bg =
      "[0:v]scale=\(w):\(h):force_original_aspect_ratio=increase,crop=\(w):\(h),setsar=1,fps=30,format=rgba[bg]"
    let viz: String
    switch recipe.style {
    case .wave:
      viz = "[1:a]showwaves=s=\(w)x\(bandHeight):mode=cline:rate=30:colors=\(color),format=rgba[viz]"
    case .bars:
      viz =
        "[1:a]showfreqs=s=\(w)x\(bandHeight):mode=bar:ascale=sqrt:fscale=log:win_size=2048:rate=30:colors=\(color),"
        + "format=rgba,colorkey=black:0.05:0[viz]"
    case .spectrum:
      viz =
        "[1:a]showspectrum=s=\(w)x\(bandHeight):mode=combined:color=intensity:slide=scroll:scale=cbrt:fps=30,"
        + "format=rgba,colorkey=black:0.08:0.1[viz]"
    }
    let y = recipe.style == .wave ? "(H-h)/2" : "H-h"
    return "\(bg);\(viz);[bg][viz]overlay=0:\(y):shortest=1,format=yuv420p[v]"
  }

  static func hex(_ c: RGBA) -> String {
    func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    return String(format: "0x%02X%02X%02X", byte(c.red), byte(c.green), byte(c.blue))
  }
}
