import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import DropCore

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

/// Generates small test clips with the bundled ffmpeg: a moving test pattern, plus a
/// 440 Hz tone when `audio` is on.
enum VideoFixtures {
  static func make(
    _ url: URL, seconds: Double = 2, width: Int = 320, height: Int = 240, audio: Bool = true,
    bitrateKbps: Int = 4000
  ) async throws -> URL {
    var args = [
      "-hide_banner", "-nostdin", "-y", "-loglevel", "error",
      "-f", "lavfi", "-i", "testsrc2=size=\(width)x\(height):rate=30:duration=\(seconds)",
    ]
    if audio { args += ["-f", "lavfi", "-i", "sine=frequency=440:duration=\(seconds)"] }
    switch url.pathExtension {
    case "avi": args += ["-c:v", "mpeg4", "-b:v", "\(bitrateKbps)k"]
    default: args += ["-c:v", "h264_videotoolbox", "-b:v", "\(bitrateKbps)k", "-pix_fmt", "yuv420p"]
    }
    if audio { args += ["-c:a", url.pathExtension == "avi" ? "libmp3lame" : "aac", "-shortest"] }
    args.append(url.path)
    _ = try await ToolRunner.run(.ffmpeg, args)
    return url
  }
}

private let hasFFmpeg = ToolLocator.isAvailable(.ffmpeg) && ToolLocator.isAvailable(.ffprobe)

@Suite struct VideoModelTests {
  @Test func recognisesVideoFiles() {
    #expect(FileKind(url: URL(fileURLWithPath: "/a.MOV")) == .video(.mov))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.webm")) == .video(.webm))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.mp4")).isVideo)
  }

  @Test func speedFilterChainsAtempoWithinRange() {
    #expect(VideoOps.audioFilter(speed: 1) == nil)
    #expect(VideoOps.audioFilter(speed: 2) == "atempo=2.000")
    #expect(VideoOps.audioFilter(speed: 4)?.components(separatedBy: ",").count == 2)
    #expect(VideoOps.audioFilter(speed: 0.25)?.components(separatedBy: ",").count == 2)
  }

  @Test func pixelRectsAreEvenAndInside() {
    let r = VideoOps.pixelRect(NormRect(x: 0.333, y: 0.333, width: 0.9, height: 0.9), width: 321, height: 241)
    #expect(r.x % 2 == 0 && r.w % 2 == 0 && r.h % 2 == 0)
    #expect(r.x + r.w <= 321 && r.y + r.h <= 241)
  }

  @Test func outputDurationAccountsForTrimAndSpeed() {
    #expect(VideoRecipe(trimStart: 1, trimEnd: 5, speed: 2).outputDuration(source: 10) == 2)
    #expect(VideoRecipe().outputDuration(source: 3) == 3)
  }

  @Test func splitPlanClipsAndValidation() {
    let plan = SplitPlan(points: [3, 1])
    #expect(plan.clips(duration: 4) == [0...1, 1...3, 3...4])
    #expect(plan.validate(duration: 4) == nil)
    #expect(
      SplitPlan(points: [1, 1.01]).validate(duration: 4)
        == "Split points must be at least 0.05 seconds apart.")
    #expect(SplitPlan(points: [0.01]).validate(duration: 4)?.contains("inside the video") == true)
    #expect(SplitPlan(points: [1], removed: [0, 1]).validate(duration: 4) == "Keep at least one clip.")
  }

  @Test func rotatedVideosReportDisplaySize() throws {
    let json =
      #"{"format":{"duration":"2.0"},"streams":[{"codec_type":"video","width":1920,"height":1080,"avg_frame_rate":"30/1","side_data_list":[{"rotation":-90}]}]}"#
    let info = try VideoOps.parseProbe(Data(json.utf8), name: "a.mov")
    #expect(info.width == 1080 && info.height == 1920)
    #expect(info.frameRate == 30 && !info.hasAudio)
  }

  @Test func targetBitrateLeavesRoomForAudio() throws {
    let kbps = try VideoOps.targetBitrate(bytes: 1_000_000, duration: 10, hasAudio: true)
    #expect(kbps > 500 && kbps < 800 - VideoOps.audioBitrateKbps + 100)
    #expect(throws: DropError.self) {
      try VideoOps.targetBitrate(bytes: 10_000, duration: 10, hasAudio: true)
    }
  }

  @Test func webmNeedsAVP9Encoder() {
    #expect(VideoOutput.webm.isAvailable == (hasFFmpeg && VideoOps.hasEncoder("libvpx-vp9")))
    if hasFFmpeg { #expect(VideoOps.hasEncoder("h264_videotoolbox")) }
  }
}

@Suite(.enabled(if: hasFFmpeg), .serialized) struct VideoOpsTests {
  @Test func probesDurationSizeAndAudio() async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("a.mp4"))
    let info = try await VideoOps.probe(clip)
    #expect(abs(info.duration - 2) < 0.15)
    #expect(info.width == 320 && info.height == 240)
    #expect(info.hasVideo && info.hasAudio)
  }

  @Test(arguments: [VideoOutput.mov, .mkv, .avi, .m4v, .gif, .mp3, .m4a])
  func convertsToEachOutput(output: VideoOutput) async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("a.mp4"), seconds: 1)
    let result = await Processor(settings: AppSettings()).run(.convertVideo(output), on: try load(clip))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.pathExtension == output.fileExtension)
    let info = try await VideoOps.probe(out)
    #expect(info.hasVideo == !output.isAudioOnly)
    if output == .gif { #expect(ImageConvert.frameCount(out) > 5) }
  }

  @Test func compressesByStrength() async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("big.mp4"), bitrateKbps: 8000)
    let result = await Processor(settings: AppSettings()).run(
      .compressVideo(.strength(.strong)), on: try load(clip))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "big compressed.mp4")
    #expect(CompressOps.fileSize(out) < CompressOps.fileSize(clip))
  }

  @Test func compressesToATargetSize() async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("big.mp4"), seconds: 3, bitrateKbps: 6000)
    let target = CompressOps.fileSize(clip) / 4
    let result = await Processor(settings: AppSettings()).run(
      .compressVideo(.target(bytes: target)), on: try load(clip))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(CompressOps.fileSize(out) <= target)
  }

  @Test func trimsSpeedsUpAndCrops() async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("a.mp4"), seconds: 3)
    let recipe = VideoRecipe(
      trimStart: 0.5, trimEnd: 2.5, speed: 2, crop: NormRect(x: 0, y: 0, width: 0.5, height: 0.5))
    let result = await Processor(settings: AppSettings()).run(.editVideo(recipe), on: try load(clip))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let info = try await VideoOps.probe(out)
    #expect(abs(info.duration - 1) < 0.2)
    #expect(info.width == 160 && info.height == 120)
    #expect(info.hasAudio)
  }

  @Test func timedRedactionHidesTheRegionOnlyInItsRange() async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("a.mp4"), seconds: 2)
    let box = NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    let recipe = VideoRecipe(redactions: [TimedRedaction(rect: box, start: 0, end: 1, style: .blackout)])
    let result = await Processor(settings: AppSettings()).run(.editVideo(recipe), on: try load(clip))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let early = dir.file("early.png")
    let late = dir.file("late.png")
    try await VideoOps.snapshots(out, times: [0.5, 1.6], destinations: [early, late])
    let a = try ImageOps.loadOriented(early)
    let b = try ImageOps.loadOriented(late)
    #expect(Fixtures.pixel(a, x: 160, y: 120)[0...2].allSatisfy { $0 < 30 })
    #expect(!Fixtures.pixel(b, x: 160, y: 120)[0...2].allSatisfy { $0 < 30 })
  }

  @Test func splitsIntoPartsOrCutsAndJoins() async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("a.mp4"), seconds: 3)
    let parts = await Processor(settings: AppSettings()).run(
      .splitVideo(SplitPlan(points: [1])), on: try load(clip))
    #expect(parts.outputs.map(\.lastPathComponent) == ["a part 1.mp4", "a part 2.mp4"], "\(parts.failures)")
    let d1 = try await VideoOps.probe(parts.outputs[0]).duration
    let d2 = try await VideoOps.probe(parts.outputs[1]).duration
    #expect(abs(d1 - 1) < 0.2 && abs(d2 - 2) < 0.2)

    let cut = await Processor(settings: AppSettings()).run(
      .splitVideo(SplitPlan(points: [1, 2], removed: [1], joinKept: true)), on: try load(clip))
    let joined = try #require(cut.outputs.first, "\(cut.failures)")
    #expect(abs(try await VideoOps.probe(joined).duration - 2) < 0.25)
  }

  @Test func joinsMismatchedVideos() async throws {
    let dir = try TempDir()
    let a = try await VideoFixtures.make(dir.file("a.mp4"), seconds: 1)
    let b = try await VideoFixtures.make(dir.file("b.mp4"), seconds: 1, width: 640, height: 360, audio: false)
    let result = await Processor(settings: AppSettings()).run(.joinVideos, on: try load(a, b))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "Joined.mp4")
    let info = try await VideoOps.probe(out)
    #expect(abs(info.duration - 2) < 0.25)
    #expect(info.width == 320 && info.height == 240 && info.hasAudio)
  }

  @Test func savesSnapshots() async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("a.mp4"))
    let result = await Processor(settings: AppSettings()).run(
      .videoSnapshots([0.5, 1.25]), on: try load(clip))
    #expect(
      result.outputs.map(\.lastPathComponent) == ["a 0m00.5s.png", "a 0m01.2s.png"], "\(result.failures)")
    let image = try ImageOps.loadOriented(result.outputs[0])
    #expect(image.width == 320 && image.height == 240)
  }

  @Test func refusesMismatchedInputs() async throws {
    let dir = try TempDir()
    let clip = try await VideoFixtures.make(dir.file("a.mp4"), seconds: 1)
    let png = try Fixtures.writeImage(to: dir.file("b.png"), type: "public.png")
    let files = try load(clip, png)
    #expect(Processor.validate(.joinVideos, files: files)?.contains("videos only") == true)
    #expect(Processor.validate(.joinVideos, files: try load(clip)) == "Select at least two videos to join.")
    #expect(
      Processor.validate(.compress(quality: 0.5), files: try load(clip))
        == "Compress works on images and PDFs.")
    let tooLong = await Processor(settings: AppSettings()).run(
      .editVideo(VideoRecipe(trimStart: 0.5, trimEnd: 9)), on: try load(clip))
    #expect(tooLong.failures.first?.message == "Choose a positive time range within the file.")
  }
}
