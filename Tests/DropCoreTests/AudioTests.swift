import Foundation
import Testing

@testable import DropCore

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

/// Generates test tones with the bundled ffmpeg: a sine wave, optionally padded with
/// silence, in mono or stereo.
enum AudioFixtures {
  static func make(
    _ url: URL, seconds: Double = 1, frequency: Int = 440, leadingSilence: Double = 0,
    trailingSilence: Double = 0,
    stereo: Bool = true, volume: Double = 0.5
  ) async throws -> URL {
    // ffmpeg's sine source peaks at 1/8.
    var filters = ["volume=\(volume * 8)"]
    if leadingSilence > 0 {
      let ms = Int(leadingSilence * 1000)
      filters.append("adelay=\(ms)|\(ms)")
    }
    if trailingSilence > 0 { filters.append("apad=pad_dur=\(trailingSilence)") }
    var args = [
      "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-f", "lavfi", "-i",
      "sine=frequency=\(frequency):sample_rate=44100:duration=\(seconds)",
    ]
    args += ["-af", filters.joined(separator: ","), "-ac", stereo ? "2" : "1"]
    switch url.pathExtension {
    case "mp3": args += ["-c:a", "libmp3lame", "-b:a", "192k"]
    case "m4a": args += ["-c:a", "aac", "-b:a", "192k"]
    default: break
    }
    args.append(url.path)
    _ = try await ToolRunner.run(.ffmpeg, args)
    return url
  }

  /// Peak level (0…1) within a time window, read back with ffmpeg.
  static func peak(_ url: URL, from start: Double, to end: Double) async throws -> Float {
    let out = try await ToolRunner.run(
      .ffmpeg,
      [
        "-hide_banner", "-nostdin", "-loglevel", "error", "-ss", "\(start)", "-to", "\(end)", "-i", url.path,
        "-ac", "1", "-f", "f32le", "-",
      ])
    let samples: [Float] = out.stdout.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    return samples.map(abs).max() ?? 0
  }

  /// Per-channel peaks, read back with ffmpeg.
  static func channelPeaks(_ url: URL) async throws -> [Float] {
    let out = try await ToolRunner.run(
      .ffmpeg, ["-hide_banner", "-nostdin", "-loglevel", "error", "-i", url.path, "-f", "f32le", "-"])
    let samples: [Float] = out.stdout.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let channels = try await VideoOps.probe(url).audioChannels
    return (0..<channels).map { c in
      stride(from: c, to: samples.count, by: channels).map { abs(samples[$0]) }.max() ?? 0
    }
  }
}

private let hasFFmpeg = ToolLocator.isAvailable(.ffmpeg) && ToolLocator.isAvailable(.ffprobe)

@Suite struct AudioModelTests {
  @Test func recognisesAudioFiles() {
    #expect(FileKind(url: URL(fileURLWithPath: "/a.MP3")) == .audio(.mp3))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.aif")) == .audio(.aiff))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.wma")).isAudio)
    #expect(!FileKind(url: URL(fileURLWithPath: "/a.mp4")).isAudio)
  }

  @Test func parsesSilenceAtBothEnds() {
    let log = """
      [silencedetect @ 0x1] silence_start: 0
      [silencedetect @ 0x1] silence_end: 0.52 | silence_duration: 0.52
      [silencedetect @ 0x1] silence_start: 1.21
      [silencedetect @ 0x1] silence_end: 1.4 | silence_duration: 0.19
      [silencedetect @ 0x1] silence_start: 2.48
      """
    #expect(AudioOps.audibleRange(silenceLog: log, duration: 3) == 0.52...2.48)
    #expect(AudioOps.audibleRange(silenceLog: "", duration: 3) == 0...3)
    // A file that's all silence keeps everything.
    #expect(AudioOps.audibleRange(silenceLog: "silence_start: 0", duration: 3) == 0...3)
  }

  @Test func bitDepthPicksTheRightPCMCodec() {
    #expect(AudioOps.codecArgs(for: .wav, bitDepth: 24).contains("pcm_s24le"))
    #expect(AudioOps.codecArgs(for: .aiff, bitDepth: 32).contains("pcm_s24be"))
    #expect(AudioOps.codecArgs(for: .wav, bitDepth: 12).contains("pcm_s16le"))
    #expect(AudioOps.codecArgs(for: .mp3, bitDepth: 24, bitrateKbps: 320).contains("320k"))
  }

  @Test func channelFiltersMixAndBalance() {
    #expect(
      AudioOps.channelFilter(AudioRecipe(channels: .mono), inputChannels: 2) == "pan=mono|c0=0.5*c0+0.5*c1")
    #expect(AudioOps.channelFilter(AudioRecipe(channels: .mono), inputChannels: 1) == nil)
    #expect(
      AudioOps.channelFilter(AudioRecipe(channels: .stereo), inputChannels: 1) == "pan=stereo|c0=1*c0|c1=1*c0"
    )
    #expect(
      AudioOps.channelFilter(AudioRecipe(leftGain: 0.5, rightGain: 0), inputChannels: 2)
        == "pan=stereo|c0=0.5*c0|c1=0*c1")
    #expect(AudioOps.channelFilter(AudioRecipe(), inputChannels: 2) == nil)
  }

  @Test func bleepGraphMutesAndAddsATone() {
    let graph = AudioOps.filterGraph(
      AudioRecipe(bleeps: [BleepRange(start: 1, end: 0.5)]), keep: 0...3, duration: 3, channels: 2,
      sampleRate: 44100)
    #expect(graph.contains("enable='between(t,0.5,1)'"))
    #expect(graph.contains("sine=frequency=1000") && graph.contains("volume=2.4,"))
    #expect(graph.hasSuffix("[bleeped]anull[out]"))
  }

  @Test func peaksBucketToTheRequestedCount() {
    let peaks = AudioOps.bucketPeaks([0, 0.5, -1, 0.25, 0, 0, 0.1, -0.2], count: 4)
    #expect(peaks == [0.5, 1, 0, 0.2])
    #expect(AudioOps.bucketPeaks([], count: 3) == [0, 0, 0])
  }

  @Test func recipeClampsAndKnowsIdentity() {
    #expect(AudioRecipe().isIdentity)
    #expect(!AudioRecipe(normalize: .podcast).isIdentity)
    #expect(AudioRecipe(silenceThreshold: -200, leftGain: 5).silenceThreshold == -80)
    #expect(AudioRecipe(leftGain: 5).leftGain == 2)
  }
}

@Suite(.enabled(if: hasFFmpeg), .serialized) struct AudioOpsTests {
  @Test(arguments: AudioOutput.allCases)
  func convertsToEachOutput(output: AudioOutput) async throws {
    let dir = try TempDir()
    let tone = try await AudioFixtures.make(dir.file("tone.wav"))
    let result = await Processor(settings: AppSettings()).run(.convertAudio(output), on: try load(tone))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.pathExtension == output.fileExtension)
    let info = try await VideoOps.probe(out)
    #expect(info.hasAudio && !info.hasVideo)
    #expect(abs(info.duration - 1) < 0.1)
  }

  @Test func extractsAudioFromVideoAndReadsOtherInputs() async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("clip.mp4"), seconds: 1)
    let mp3 = try await AudioFixtures.make(dir.file("song.mp3"))
    let result = await Processor(settings: AppSettings()).run(.convertAudio(.flac), on: try load(clip, mp3))
    #expect(result.outputs.map(\.lastPathComponent) == ["clip.flac", "song.flac"], "\(result.failures)")
  }

  @Test func honoursBitDepth() async throws {
    let dir = try TempDir()
    let tone = try await AudioFixtures.make(dir.file("tone.mp3"))
    var settings = AppSettings()
    settings.formatSettings["wav"] = FormatSettings(audioBitDepth: 24)
    let result = await Processor(settings: settings).run(.convertAudio(.wav), on: try load(tone))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let probe = try await ToolRunner.run(
      .ffprobe, ["-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0", out.path])
    #expect(String(decoding: probe.stdout, as: UTF8.self).contains("pcm_s24le"))
  }

  @Test func trimsSilentEnds() async throws {
    let dir = try TempDir()
    let tone = try await AudioFixtures.make(
      dir.file("padded.wav"), seconds: 1, leadingSilence: 0.6, trailingSilence: 0.8)
    let range = try await AudioOps.audibleRange(tone, threshold: -50)
    #expect(abs(range.lowerBound - 0.6) < 0.06 && abs(range.upperBound - 1.6) < 0.06)
    let result = await Processor(settings: AppSettings()).run(
      .editAudio(AudioRecipe(trimSilence: true)), on: try load(tone))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "padded edited.wav")
    #expect(abs(try await VideoOps.probe(out).duration - 1) < 0.08)
  }

  @Test func trimsToARange() async throws {
    let dir = try TempDir()
    let tone = try await AudioFixtures.make(dir.file("tone.m4a"), seconds: 3)
    let result = await Processor(settings: AppSettings()).run(
      .editAudio(AudioRecipe(trimStart: 0.5, trimEnd: 2)), on: try load(tone))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(abs(try await VideoOps.probe(out).duration - 1.5) < 0.1)
  }

  @Test func bleepsReplaceTheRangeWithATone() async throws {
    let dir = try TempDir()
    // A quiet tone, so the louder bleep stands out.
    let tone = try await AudioFixtures.make(dir.file("talk.wav"), seconds: 3, volume: 0.05)
    let result = await Processor(settings: AppSettings()).run(
      .editAudio(AudioRecipe(bleeps: [BleepRange(start: 1, end: 2)])), on: try load(tone))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let before = try await AudioFixtures.peak(out, from: 0.2, to: 0.8)
    let during = try await AudioFixtures.peak(out, from: 1.2, to: 1.8)
    #expect(before < 0.1)
    #expect(during > 0.2)

    let all = await Processor(settings: AppSettings()).run(
      .editAudio(AudioRecipe(bleepAll: true)), on: try load(tone))
    let allOut = try #require(all.outputs.first, "\(all.failures)")
    #expect(try await AudioFixtures.peak(allOut, from: 0.2, to: 0.8) > 0.2)
  }

  @Test func normalisesLoudness() async throws {
    let dir = try TempDir()
    let tone = try await AudioFixtures.make(dir.file("quiet.wav"), seconds: 4, volume: 0.02)
    let before = try await AudioOps.loudness(tone)
    let result = await Processor(settings: AppSettings()).run(
      .editAudio(AudioRecipe(normalize: .podcast)), on: try load(tone))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let after = try await AudioOps.loudness(out)
    #expect(before < -30)
    #expect(abs(after - -16) < 2, "measured \(after) LUFS")
  }

  @Test func mixesToMonoAndBalancesStereo() async throws {
    let dir = try TempDir()
    let tone = try await AudioFixtures.make(dir.file("tone.wav"))
    let mono = await Processor(settings: AppSettings()).run(
      .editAudio(AudioRecipe(channels: .mono)), on: try load(tone))
    let monoOut = try #require(mono.outputs.first, "\(mono.failures)")
    #expect(try await VideoOps.probe(monoOut).audioChannels == 1)

    let balanced = await Processor(settings: AppSettings()).run(
      .editAudio(AudioRecipe(channels: .stereo, leftGain: 1, rightGain: 0)), on: try load(tone))
    let balancedOut = try #require(balanced.outputs.first, "\(balanced.failures)")
    let peaks = try await AudioFixtures.channelPeaks(balancedOut)
    #expect(peaks.count == 2 && peaks[0] > 0.3 && peaks[1] < 0.01)
  }

  @Test func readsWaveformPeaks() async throws {
    let dir = try TempDir()
    let tone = try await AudioFixtures.make(dir.file("padded.wav"), seconds: 1, leadingSilence: 1)
    let peaks = try await AudioOps.peaks(tone, count: 20)
    #expect(peaks.count == 20)
    #expect(peaks[2] < 0.01 && peaks[15] > 0.3)
  }

  @Test(arguments: VisualizerStyle.allCases)
  func makesVisualizerVideos(style: VisualizerStyle) async throws {
    let dir = try TempDir()
    let tone = try await AudioFixtures.make(dir.file("tone.mp3"), seconds: 1.5)
    let recipe = VisualizerRecipe(style: style, size: .square)
    let result = await Processor(settings: AppSettings()).run(.audioVisualizer(recipe), on: try load(tone))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "tone visualizer.mp4")
    let info = try await VideoOps.probe(out)
    #expect(info.width == 1080 && info.height == 1080 && info.hasAudio)
    #expect(abs(info.duration - 1.5) < 0.2)
  }

  @Test func visualizerUsesABackgroundImage() async throws {
    let dir = try TempDir()
    let tone = try await AudioFixtures.make(dir.file("tone.wav"), seconds: 1)
    let png = try Fixtures.writeImage(to: dir.file("bg.png"), type: "public.png")
    let recipe = VisualizerRecipe(size: .landscape, backgroundImage: png.path)
    let result = await Processor(settings: AppSettings()).run(.audioVisualizer(recipe), on: try load(tone))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let info = try await VideoOps.probe(out)
    #expect(info.width == 1280 && info.height == 720)
  }

  @Test func refusesMismatchedInputs() async throws {
    let dir = try TempDir()
    let tone = try await AudioFixtures.make(dir.file("tone.wav"))
    let png = try Fixtures.writeImage(to: dir.file("b.png"), type: "public.png")
    #expect(
      Processor.validate(.editAudio(AudioRecipe(normalize: .podcast)), files: try load(tone, png))?.contains(
        "audio files only") == true)
    #expect(
      Processor.validate(.editAudio(AudioRecipe()), files: try load(tone))
        == "There are no audio changes to save.")
    #expect(
      Processor.validate(.convertAudio(.mp3), files: try load(png))?.contains("audio and video") == true)
    #expect(
      Processor.validate(.compress(quality: 0.5), files: try load(tone))
        == "Compress works on images and PDFs.")
    let bad = await Processor(settings: AppSettings()).run(
      .editAudio(AudioRecipe(trimStart: 0.5, trimEnd: 9)), on: try load(tone))
    #expect(bad.failures.first?.message == "Choose a positive time range within the file.")
  }
}
