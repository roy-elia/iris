import Foundation
import Testing

@testable import DropCore

private let hasTools = ToolLocator.isAvailable(.ffmpeg) && ToolLocator.isAvailable(.ffprobe)

private func ffmpeg(_ args: [String]) async throws {
  _ = try await ToolRunner.run(.ffmpeg, ["-hide_banner", "-nostdin", "-y", "-loglevel", "error"] + args)
}

private let testPattern = [
  "-f", "lavfi", "-i", "testsrc=size=320x240:rate=25:duration=1", "-f", "lavfi", "-i",
  "sine=frequency=500:duration=1",
]

@Suite struct MediaFormatTests {
  @Test func recognisesNewContainers() async {
    let video: [String: VideoFormat] = [
      "wmv": .wmv, "asf": .wmv, "flv": .flv, "mpg": .mpeg, "mpeg": .mpeg, "ts": .ts, "m2ts": .m2ts,
      "mts": .m2ts, "3gp": .threeGP, "ogv": .ogv, "vob": .vob,
    ]
    for (ext, format) in video {
      #expect(FileKind(url: URL(fileURLWithPath: "/a.\(ext)")) == .video(format), "\(ext)")
    }
    for (ext, format) in [("amr", AudioFormat.amr), ("ape", .ape), ("ac3", .ac3)] {
      #expect(FileKind(url: URL(fileURLWithPath: "/a.\(ext)")) == .audio(format), "\(ext)")
    }
    #expect(VideoFormat.threeGP.displayName == "3GP")
    #expect(AudioOps.output(for: URL(fileURLWithPath: "/a.ape")) == .flac)
    #expect(VideoOutput.hevc.fileExtension == "mp4" && VideoOutput.mp4720.displayName == "720p")
  }

  @Test(
    .enabled(if: hasTools),
    arguments: [
      ("a.wmv", ["-c:v", "wmv2", "-c:a", "wmav2"]),
      ("a.flv", ["-c:v", "flv", "-c:a", "libmp3lame", "-ar", "44100"]),
      ("a.mpg", ["-c:v", "mpeg2video", "-c:a", "mp2"]),
      ("a.ts", ["-c:v", "h264_videotoolbox", "-c:a", "aac"]),
      ("a.3gp", ["-s", "176x144", "-c:v", "h263", "-c:a", "aac", "-ar", "8000", "-ac", "1"]),
      ("a.ogv", ["-c:v", "libvpx", "-c:a", "opus", "-strict", "-2", "-ar", "48000"]),
      ("a.vob", ["-c:v", "mpeg2video", "-c:a", "ac3", "-f", "vob"]),
    ])
  func convertsLegacyContainersToMP4(name: String, codecs: [String]) async throws {
    let dir = try TempDir()
    let src = dir.file(name)
    try await ffmpeg(testPattern + codecs + ["-shortest", src.path])
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convertVideo(.mp4), on: [try DroppedFile.load(src)])
    let out = try #require(result.outputs.first, "\(name): \(result.failures)")
    let info = try await VideoOps.probe(out)
    #expect(info.hasVideo && info.hasAudio && abs(info.duration - 1) < 0.2, "\(name)")
  }

  @Test(.enabled(if: hasTools)) func readsAC3Audio() async throws {
    let dir = try TempDir()
    let src = dir.file("s.ac3")
    try await ffmpeg([
      "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-ac", "2", "-c:a", "ac3", src.path,
    ])
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convertAudio(.mp3), on: [try DroppedFile.load(src)])
    #expect(result.outputs.first?.lastPathComponent == "s.mp3", "\(result.failures)")
  }

  @Test(.enabled(if: hasTools && VideoOps.hasEncoder("hevc_videotoolbox")))
  func writesHEVC() async throws {
    let dir = try TempDir()
    let src = try await VideoFixtures.make(dir.file("clip.mp4"), seconds: 1)
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convertVideo(.hevc), on: [try DroppedFile.load(src)])
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "clip HEVC.mp4")
    let probe = try await ToolRunner.run(
      .ffprobe,
      [
        "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name,codec_tag_string", "-of",
        "csv=p=0", out.path,
      ])
    #expect(
      String(decoding: probe.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        == "hevc,hvc1")
  }

  @Test(.enabled(if: hasTools)) func scalesTo720p() async throws {
    let dir = try TempDir()
    let big = try await VideoFixtures.make(dir.file("big.mp4"), seconds: 1, width: 1920, height: 1080)
    let small = try await VideoFixtures.make(dir.file("small.mp4"), seconds: 1, width: 640, height: 360)
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convertVideo(.mp4720), on: [try DroppedFile.load(big), try DroppedFile.load(small)])
    #expect(
      result.outputs.map(\.lastPathComponent) == ["big 720p.mp4", "small 720p.mp4"], "\(result.failures)")
    let bigInfo = try await VideoOps.probe(result.outputs[0])
    #expect(bigInfo.width == 1280 && bigInfo.height == 720)
    // Never scaled up.
    #expect(try await VideoOps.probe(result.outputs[1]).height == 360)
  }

  @Test(.enabled(if: hasTools)) func extractsTextSubtitleTracks() async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("clip.mp4"), seconds: 2)
    let en = try dir.touch("en.srt", contents: "1\n00:00:00,500 --> 00:00:01,000\nHello\n")
    let fr = try dir.touch("fr.srt", contents: "1\n00:00:00,500 --> 00:00:01,000\nBonjour\n")
    let mkv = dir.file("film.mkv")
    try await ffmpeg([
      "-i", clip.path, "-i", en.path, "-i", fr.path, "-map", "0", "-map", "1", "-map", "2", "-c", "copy",
      "-c:s", "srt", "-metadata:s:s:0", "language=eng", "-metadata:s:s:1", "language=fre", mkv.path,
    ])
    let out = dir.file("out")
    let result = await Processor(settings: AppSettings(outputLocation: .folder(out)))
      .run(.extractSubtitles, on: [try DroppedFile.load(mkv)])
    #expect(
      result.outputs.map(\.lastPathComponent) == ["film eng.srt", "film fre.srt"], "\(result.failures)")
    let french = try String(contentsOf: result.outputs[1], encoding: .utf8)
    #expect(SubtitleOps.parse(french).map(\.text) == ["Bonjour"])

    let none = await Processor(settings: AppSettings(outputLocation: .folder(out)))
      .run(.extractSubtitles, on: [try DroppedFile.load(clip)])
    #expect(none.failures.first?.message == "clip.mp4 has no subtitle tracks.")
  }

  @Test func labelsTracks() async {
    let tracks = [
      SubtitleTrack(index: 0, codec: "subrip", language: "eng"),
      SubtitleTrack(index: 1, codec: "ass", language: "eng"),
      SubtitleTrack(index: 2, codec: "mov_text", language: nil),
    ]
    #expect(VideoOps.trackLabels(tracks) == ["eng", "eng 2", "track 3"])
    #expect(!SubtitleTrack(index: 0, codec: "hdmv_pgs_subtitle").isText)
  }
}
