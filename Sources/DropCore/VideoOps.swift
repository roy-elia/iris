import Foundation

/// Video work, done with the bundled ffmpeg and ffprobe. Encoding uses Apple's hardware
/// encoders (VideoToolbox) for H.264.
public enum VideoOps {
  /// Constant quality for plain conversions (VideoToolbox scale, 0–100).
  static let conversionQuality = 65
  static let audioBitrateKbps = 160
  /// Share of a target size reserved for container overhead.
  static let containerOverhead = 0.03
  static let minimumVideoKbps = 60.0
  static let gifFrameRate = 15
  static let gifMaxWidth = 720

  // MARK: Probe

  public static func probe(_ url: URL) async throws -> MediaInfo {
    let out = try await ToolRunner.run(
      .ffprobe, ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path])
    return try parseProbe(out.stdout, name: url.lastPathComponent)
  }

  /// Parses ffprobe's JSON. Width and height are swapped for videos rotated a quarter turn.
  static func parseProbe(_ data: Data, name: String) throws -> MediaInfo {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw DropError.readFailed(name)
    }
    let streams = json["streams"] as? [[String: Any]] ?? []
    let format = json["format"] as? [String: Any] ?? [:]
    var info = MediaInfo(duration: Double(format["duration"] as? String ?? "") ?? 0)
    if let video = streams.first(where: {
      $0["codec_type"] as? String == "video"
        && ($0["disposition"] as? [String: Any])?["attached_pic"] as? Int != 1
    }) {
      info.hasVideo = true
      var w = video["width"] as? Int ?? 0
      var h = video["height"] as? Int ?? 0
      let sideData = video["side_data_list"] as? [[String: Any]] ?? []
      let rotation =
        sideData.compactMap { $0["rotation"] as? Int }.first
        ?? Int((video["tags"] as? [String: Any])?["rotate"] as? String ?? "") ?? 0
      if abs(rotation) % 180 == 90 { swap(&w, &h) }
      info.width = w
      info.height = h
      info.frameRate =
        fraction(video["avg_frame_rate"] as? String) ?? fraction(video["r_frame_rate"] as? String) ?? 30
      if info.duration == 0 { info.duration = Double(video["duration"] as? String ?? "") ?? 0 }
    }
    if let audio = streams.first(where: { $0["codec_type"] as? String == "audio" }) {
      info.hasAudio = true
      info.audioChannels = audio["channels"] as? Int ?? 2
      info.sampleRate = Int(audio["sample_rate"] as? String ?? "") ?? 48000
      if info.duration == 0 { info.duration = Double(audio["duration"] as? String ?? "") ?? 0 }
    }
    guard info.hasVideo || info.hasAudio else {
      throw DropError.wrongInput("\(name) has no playable video or audio.")
    }
    return info
  }

  private static func fraction(_ s: String?) -> Double? {
    guard let s else { return nil }
    let parts = s.split(separator: "/").compactMap { Double($0) }
    guard parts.count == 2, parts[1] != 0 else { return parts.first }
    let value = parts[0] / parts[1]
    return value > 0 ? value : nil
  }

  // MARK: Encoders

  private static let encoderLock = NSLock()
  nonisolated(unsafe) private static var encoderNames: Set<String>?

  /// Whether the bundled ffmpeg has an encoder (checked once, then cached).
  public static func hasEncoder(_ name: String) -> Bool {
    encoderLock.withLock {
      if encoderNames == nil {
        encoderNames = []
        if let url = ToolLocator.url(for: .ffmpeg) {
          let p = Process()
          p.executableURL = url
          p.arguments = ["-hide_banner", "-encoders"]
          let pipe = Pipe()
          p.standardOutput = pipe
          p.standardError = FileHandle.nullDevice
          if (try? p.run()) != nil {
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            encoderNames = Set(
              text.split(separator: "\n").compactMap { line in
                let cols = line.split(separator: " ", omittingEmptySubsequences: true)
                return cols.count >= 2 && cols[0].count == 6 ? String(cols[1]) : nil
              })
          }
        }
      }
      return encoderNames!.contains(name)
    }
  }

  /// Codec arguments for an output. `videoKbps` switches from constant quality to a
  /// bitrate (target-size compression).
  static func codecArgs(
    for output: VideoOutput, quality: Int = conversionQuality, videoKbps: Int? = nil, mute: Bool
  )
    -> [String]
  {
    let audio: [String]
    switch output {
    case .avi: audio = ["-c:a", "libmp3lame", "-b:a", "192k"]
    // ffmpeg's own Opus encoder (marked experimental, hence -strict).
    case .webm: audio = ["-c:a", "opus", "-strict", "-2", "-b:a", "128k"]
    default: audio = ["-c:a", "aac", "-b:a", "\(audioBitrateKbps)k"]
    }
    let rate: [String] =
      videoKbps.map {
        ["-b:v", "\($0)k", "-maxrate", "\(Int(Double($0) * 1.25))k", "-bufsize", "\($0 * 2)k"]
      }
      ?? ["-q:v", "\(quality)"]
    var args: [String]
    switch output {
    case .mp4, .m4v, .mov:
      args =
        ["-c:v", "h264_videotoolbox"] + rate + [
          "-pix_fmt", "yuv420p", "-tag:v", "avc1", "-movflags", "+faststart",
        ]
    case .mkv:
      args = ["-c:v", "h264_videotoolbox"] + rate + ["-pix_fmt", "yuv420p"]
    case .avi:
      args = ["-c:v", "mpeg4", "-q:v", "4", "-tag:v", "XVID"]
    case .webm:
      args = ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1"]
    case .gif:
      return ["-an", "-loop", "0"]
    case .mp3:
      return ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
    case .m4a:
      return ["-vn", "-c:a", "aac", "-b:a", "192k"]
    }
    return args + (mute ? ["-an"] : audio)
  }

  // MARK: Filters

  /// The video filter graph for a recipe, reading `[0:v]` and writing `[vout]`, or nil if
  /// no filtering is needed. Order: redact, crop, scale, speed.
  static func videoFilter(_ recipe: VideoRecipe, info: MediaInfo, gif: Bool = false) -> String? {
    var chain: [String] = []
    var label = "0:v"
    var n = 0
    func next() -> String {
      n += 1
      return "v\(n)"
    }
    let w = Double(info.width)
    let h = Double(info.height)
    let offset = max(recipe.trimStart ?? 0, 0)

    for r in recipe.redactions where !r.rect.isEmpty {
      let px = pixelRect(r.rect, width: w, height: h)
      let enable = "enable='between(t,\(num(r.start - offset)),\(num(r.end - offset)))'"
      let out = next()
      switch r.style {
      case .blackout:
        chain.append(
          "[\(label)]drawbox=x=\(px.x):y=\(px.y):w=\(px.w):h=\(px.h):color=black:t=fill:\(enable)[\(out)]")
      case .blur, .pixelate:
        let main = next()
        let region = next()
        let soft = next()
        let effect =
          r.style == .blur
          ? "boxblur=luma_radius=\(max(2, min(px.w, px.h) / 6)):luma_power=3:chroma_radius=\(max(2, min(px.w, px.h) / 8))"
          : "scale=\(max(1, px.w / 14)):\(max(1, px.h / 14)):flags=neighbor,scale=\(px.w):\(px.h):flags=neighbor"
        chain.append("[\(label)]split[\(main)][\(region)]")
        chain.append("[\(region)]crop=\(px.w):\(px.h):\(px.x):\(px.y),\(effect)[\(soft)]")
        chain.append("[\(main)][\(soft)]overlay=\(px.x):\(px.y):\(enable)[\(out)]")
      }
      label = out
    }

    var simple: [String] = []
    if let crop = recipe.crop, crop != .full, !crop.isEmpty {
      let px = pixelRect(crop, width: w, height: h)
      simple.append("crop=\(px.w):\(px.h):\(px.x):\(px.y)")
    }
    if gif {
      simple.append("fps=\(gifFrameRate)")
      simple.append("scale='min(\(gifMaxWidth),iw)':-2:flags=lanczos")
    } else if let maxHeight = recipe.maxHeight, Double(maxHeight) < h {
      simple.append("scale=-2:\(maxHeight - maxHeight % 2)")
    }
    if recipe.speed != 1 { simple.append("setpts=PTS/\(num(recipe.speed))") }
    if gif {
      let split = next()
      let palIn = next()
      let pal = next()
      let base = simple.isEmpty ? "null" : simple.joined(separator: ",")
      chain.append("[\(label)]\(base),split[\(split)][\(palIn)]")
      chain.append("[\(palIn)]palettegen=stats_mode=diff[\(pal)]")
      chain.append("[\(split)][\(pal)]paletteuse=dither=sierra2_4a[vout]")
      return chain.joined(separator: ";")
    }
    if !simple.isEmpty || !chain.isEmpty {
      chain.append("[\(label)]\(simple.isEmpty ? "null" : simple.joined(separator: ","))[vout]")
      return chain.joined(separator: ";")
    }
    return nil
  }

  /// `atempo` steps for a speed change (each step must be within 0.5…2).
  static func audioFilter(speed: Double) -> String? {
    guard speed != 1 else { return nil }
    var remaining = speed
    var steps: [String] = []
    while remaining > 2 {
      steps.append("atempo=2")
      remaining /= 2
    }
    while remaining < 0.5 {
      steps.append("atempo=0.5")
      remaining /= 0.5
    }
    steps.append("atempo=\(num(remaining))")
    return steps.joined(separator: ",")
  }

  /// A normalised rectangle in even pixel values, as encoders require.
  static func pixelRect(_ r: NormRect, width: Double, height: Double) -> (x: Int, y: Int, w: Int, h: Int) {
    func even(_ v: Double) -> Int { max(0, Int(v.rounded()) & ~1) }
    let x = even(r.x * width)
    let y = even(r.y * height)
    let w = max(2, min(even(r.width * width), Int(width) - x))
    let h = max(2, min(even(r.height * height), Int(height) - y))
    return (x, y, w & ~1, h & ~1)
  }

  static func num(_ v: Double) -> String { String(format: "%.3f", max(v, 0)) }

  // MARK: Render

  /// Builds the full ffmpeg argument list for one render.
  static func renderArgs(
    source: URL, info: MediaInfo, recipe: VideoRecipe, output: VideoOutput, videoKbps: Int? = nil,
    quality: Int = conversionQuality, destination: URL
  ) -> [String] {
    var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:2", "-nostats"]
    if let start = recipe.trimStart, start > 0 { args += ["-ss", num(start)] }
    if let end = recipe.trimEnd, end < info.duration { args += ["-to", num(end)] }
    args += ["-i", source.path]
    let gif = output == .gif
    if !output.isAudioOnly, info.hasVideo, let graph = videoFilter(recipe, info: info, gif: gif) {
      args += ["-filter_complex", graph, "-map", "[vout]"]
      if info.hasAudio && !recipe.mute && !gif { args += ["-map", "0:a:0?"] }
    } else if !output.isAudioOnly {
      args += ["-map", "0:v:0?"]
      if !recipe.mute && !gif { args += ["-map", "0:a:0?"] }
    } else {
      args += ["-map", "0:a:0"]
    }
    if info.hasAudio, !recipe.mute, !gif, let af = audioFilter(speed: recipe.speed) { args += ["-af", af] }
    args += codecArgs(
      for: output, quality: quality, videoKbps: videoKbps, mute: recipe.mute || !info.hasAudio)
    args.append(destination.path)
    return args
  }

  /// Runs one ffmpeg render, reporting 0…1 progress.
  static func render(
    _ args: [String], expectedDuration: Double, destination: URL, progress: (@Sendable (Double) -> Void)?
  ) async throws {
    do {
      _ = try await ToolRunner.run(.ffmpeg, args) { line in
        if let p = ToolRunner.ffmpegProgress(line: line, duration: expectedDuration) { progress?(p) }
      }
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
    guard FileManager.default.fileExists(atPath: destination.path) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  // MARK: Operations

  /// Converts (and optionally edits) a video.
  public static func convert(
    _ source: URL, to output: VideoOutput, recipe: VideoRecipe = VideoRecipe(), destination: URL,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    guard output.isAvailable else {
      throw DropError.wrongInput(output.unavailableReason ?? "Unavailable for conversion.")
    }
    let info = try await probe(source)
    if output.isAudioOnly && !info.hasAudio {
      throw DropError.wrongInput("\(source.lastPathComponent) has no audio track.")
    }
    if !output.isAudioOnly && !info.hasVideo {
      throw DropError.wrongInput("\(source.lastPathComponent) has no playable video track.")
    }
    try validate(recipe, info: info, name: source.lastPathComponent)
    let args = renderArgs(
      source: source, info: info, recipe: recipe, output: output, destination: destination)
    try await render(
      args, expectedDuration: recipe.outputDuration(source: info.duration), destination: destination,
      progress: progress)
  }

  /// Checks a recipe against the file. Throws with a readable message.
  static func validate(_ recipe: VideoRecipe, info: MediaInfo, name: String) throws {
    let start = recipe.trimStart ?? 0
    let end = recipe.trimEnd ?? info.duration
    if start < 0 || end > info.duration + 0.05 || end - start < 0.05 {
      throw DropError.wrongInput("Choose a positive time range within the file.")
    }
    if let crop = recipe.crop, crop.isEmpty {
      throw DropError.wrongInput("Keep the crop inside the video frame.")
    }
  }

  /// Compresses a video by strength, or to a target size (re-encoding until it fits).
  public static func compress(
    _ source: URL, compression: VideoCompression, destination: URL,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    let info = try await probe(source)
    guard info.hasVideo else {
      throw DropError.wrongInput("\(source.lastPathComponent) has no playable video track.")
    }
    let output = VideoOutput(rawValue: destination.pathExtension.lowercased()) ?? .mp4
    let originalSize = CompressOps.fileSize(source)
    switch compression {
    case .strength(let strength):
      let args = renderArgs(
        source: source, info: info, recipe: VideoRecipe(), output: output, quality: strength.quality,
        destination: destination)
      try await render(args, expectedDuration: info.duration, destination: destination, progress: progress)
      if CompressOps.fileSize(destination) >= originalSize {
        try? FileManager.default.removeItem(at: destination)
        throw DropError.notSmaller(source.lastPathComponent)
      }
    case .target(let bytes):
      if bytes >= originalSize {
        throw DropError.wrongInput("Target size cannot exceed the original file size.")
      }
      var kbps = try targetBitrate(bytes: bytes, duration: info.duration, hasAudio: info.hasAudio)
      // VideoToolbox rate control is approximate: retry with a lower rate if it overshoots.
      for attempt in 0..<3 {
        let args = renderArgs(
          source: source, info: info, recipe: VideoRecipe(), output: output, videoKbps: kbps,
          destination: destination)
        try await render(args, expectedDuration: info.duration, destination: destination) { p in
          progress?((Double(attempt) + p) / 3)
        }
        let actual = CompressOps.fileSize(destination)
        if actual <= bytes { return }
        try? FileManager.default.removeItem(at: destination)
        kbps = Int(Double(kbps) * Double(bytes) / Double(actual) * 0.92)
        if Double(kbps) < minimumVideoKbps { break }
      }
      throw DropError.wrongInput("The target is too small for this duration. Choose a larger size.")
    }
  }

  /// Video bitrate (kbps) that fits `bytes` over `duration` seconds after audio and overhead.
  static func targetBitrate(bytes: Int64, duration: Double, hasAudio: Bool) throws -> Int {
    guard duration > 0 else { throw DropError.wrongInput("This file has no playable duration.") }
    let totalKbps = Double(bytes) * 8 * (1 - containerOverhead) / duration / 1000
    let audio = hasAudio ? Double(audioBitrateKbps) : 0
    if totalKbps <= audio {
      throw DropError.wrongInput(
        "The target is too small after audio and container overhead. Choose a larger size.")
    }
    let video = totalKbps - audio
    if video < minimumVideoKbps {
      throw DropError.wrongInput("The target leaves too little space for video.")
    }
    return Int(video)
  }

  /// Splits a video at the plan's points. Returns one output per kept clip, or one joined
  /// output. `destinations` must hold one URL per kept clip (or one when joining).
  public static func split(
    _ source: URL, plan: SplitPlan, destinations: [URL], progress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    let info = try await probe(source)
    if let message = plan.validate(duration: info.duration) { throw DropError.wrongInput(message) }
    let clips = plan.clips(duration: info.duration).enumerated().filter { !plan.removed.contains($0.offset) }
      .map(\.element)
    let output =
      VideoOutput(rawValue: source.pathExtension.lowercased()).flatMap { $0.isAvailable ? $0 : nil } ?? .mp4
    if plan.joinKept {
      // One pass: keep frames and samples inside the kept ranges, then close the gaps.
      let condition = clips.map { "between(t,\(num($0.lowerBound)),\(num($0.upperBound)))" }.joined(
        separator: "+")
      var args = [
        "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:2", "-nostats", "-i",
        source.path,
      ]
      args += ["-vf", "select='\(condition)',setpts=N/FRAME_RATE/TB"]
      if info.hasAudio { args += ["-af", "aselect='\(condition)',asetpts=N/SR/TB"] }
      args += codecArgs(for: output, mute: !info.hasAudio)
      args.append(destinations[0].path)
      let total = clips.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
      try await render(args, expectedDuration: total, destination: destinations[0], progress: progress)
      return
    }
    for (index, clip) in clips.enumerated() {
      let recipe = VideoRecipe(trimStart: clip.lowerBound, trimEnd: clip.upperBound)
      let args = renderArgs(
        source: source, info: info, recipe: recipe, output: output, destination: destinations[index])
      try await render(
        args, expectedDuration: clip.upperBound - clip.lowerBound, destination: destinations[index]
      ) { p in
        progress?((Double(index) + p) / Double(clips.count))
      }
    }
  }

  /// Joins videos end to end. Sizes are matched to the first video (letterboxed), frame
  /// rates to its rate, and silent videos get a silent track so audio stays in sync.
  public static func join(_ sources: [URL], destination: URL, progress: (@Sendable (Double) -> Void)? = nil)
    async throws
  {
    guard sources.count >= 2 else { throw DropError.wrongInput("Select at least two videos to join.") }
    var infos: [MediaInfo] = []
    for url in sources {
      let info = try await probe(url)
      guard info.hasVideo else {
        throw DropError.wrongInput("Every selected file must contain a video track.")
      }
      infos.append(info)
    }
    let w = infos[0].width & ~1
    let h = infos[0].height & ~1
    let fps = infos[0].frameRate > 0 ? infos[0].frameRate : 30
    var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:2", "-nostats"]
    for url in sources { args += ["-i", url.path] }
    var graph: [String] = []
    var pairs = ""
    for (i, info) in infos.enumerated() {
      graph.append(
        "[\(i):v]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=\(num(fps)),format=yuv420p[v\(i)]"
      )
      if info.hasAudio {
        graph.append("[\(i):a]aresample=48000,aformat=channel_layouts=stereo[a\(i)]")
      } else {
        graph.append("anullsrc=r=48000:cl=stereo,atrim=duration=\(num(info.duration))[a\(i)]")
      }
      pairs += "[v\(i)][a\(i)]"
    }
    graph.append("\(pairs)concat=n=\(sources.count):v=1:a=1[vout][aout]")
    args += ["-filter_complex", graph.joined(separator: ";"), "-map", "[vout]", "-map", "[aout]"]
    let output = VideoOutput(rawValue: destination.pathExtension.lowercased()) ?? .mp4
    args += codecArgs(for: output, mute: false)
    args.append(destination.path)
    try await render(
      args, expectedDuration: infos.reduce(0) { $0 + $1.duration }, destination: destination,
      progress: progress)
  }

  /// Saves the frames at `times` (seconds) as PNGs, one destination per time.
  public static func snapshots(_ source: URL, times: [Double], destinations: [URL]) async throws {
    let info = try await probe(source)
    guard info.hasVideo else {
      throw DropError.wrongInput("\(source.lastPathComponent) has no playable video track.")
    }
    guard !times.isEmpty else { throw DropError.wrongInput("Select at least one frame within the video.") }
    for (time, out) in zip(times, destinations) {
      guard time >= 0, time <= info.duration else {
        throw DropError.wrongInput("No frame is available at this time. Choose an earlier frame.")
      }
      // Seek a hair before the very end so a frame exists.
      let t = min(time, max(info.duration - 0.05, 0))
      _ = try await ToolRunner.run(
        .ffmpeg,
        [
          "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-ss", num(t), "-i", source.path,
          "-frames:v", "1", out.path,
        ])
      guard FileManager.default.fileExists(atPath: out.path) else {
        throw DropError.wrongInput("No frame is available at this time. Choose an earlier frame.")
      }
    }
  }

  /// "0m12.5s"-style label for file names.
  public static func timeLabel(_ seconds: Double) -> String {
    let m = Int(seconds) / 60
    let s = seconds - Double(m * 60)
    return String(format: "%dm%04.1fs", m, s)
  }
}
