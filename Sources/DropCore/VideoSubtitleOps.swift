import Foundation

/// A subtitle stream inside a video file.
public struct SubtitleTrack: Equatable, Sendable {
  /// Position among the file's subtitle streams (for `-map 0:s:N`).
  public var index: Int
  public var codec: String
  public var language: String?
  public var title: String?

  /// Picture-based subtitles (DVD, Blu-ray, DVB) need OCR to become text.
  public var isText: Bool { !Self.imageCodecs.contains(codec) }

  public init(index: Int, codec: String, language: String? = nil, title: String? = nil) {
    self.index = index
    self.codec = codec
    self.language = language
    self.title = title
  }

  static let imageCodecs: Set<String> = [
    "dvd_subtitle", "hdmv_pgs_subtitle", "dvb_subtitle", "dvb_teletext", "xsub",
  ]
}

extension VideoOps {
  /// The subtitle streams in `url`, in file order.
  public static func subtitleTracks(_ url: URL) async throws -> [SubtitleTrack] {
    let out = try await ToolRunner.run(
      .ffprobe, ["-v", "error", "-select_streams", "s", "-print_format", "json", "-show_streams", url.path])
    return parseSubtitleTracks(out.stdout)
  }

  static func parseSubtitleTracks(_ data: Data) -> [SubtitleTrack] {
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let streams = json?["streams"] as? [[String: Any]] ?? []
    return streams.enumerated().map { i, stream in
      let tags = stream["tags"] as? [String: Any] ?? [:]
      let language = (tags["language"] as? String).flatMap { $0 == "und" || $0.isEmpty ? nil : $0 }
      return SubtitleTrack(
        index: i, codec: stream["codec_name"] as? String ?? "", language: language,
        title: (tags["title"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }
  }

  /// A name suffix for a track when a file has several: its language, else "track N",
  /// made unique when two share a language.
  public static func trackLabels(_ tracks: [SubtitleTrack]) -> [String] {
    var used: [String: Int] = [:]
    return tracks.map { track in
      let base = track.language ?? "track \(track.index + 1)"
      used[base, default: 0] += 1
      return used[base]! == 1 ? base : "\(base) \(used[base]!)"
    }
  }

  /// Saves every text subtitle track as SRT. `destination` names each output from the
  /// track's label ("" when the file has a single text track).
  public static func extractSubtitles(_ source: URL, destination: (String) -> URL) async throws -> [URL] {
    let name = source.lastPathComponent
    let tracks = try await subtitleTracks(source)
    guard !tracks.isEmpty else { throw DropError.wrongInput("\(name) has no subtitle tracks.") }
    let text = tracks.filter(\.isText)
    guard !text.isEmpty else {
      throw DropError.wrongInput("\(name) only has picture-based subtitles, which can't be saved as text.")
    }
    let labels = text.count == 1 ? [""] : trackLabels(text)
    let outputs = labels.map(destination)
    var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-i", source.path]
    for (track, out) in zip(text, outputs) {
      args += ["-map", "0:s:\(track.index)", "-c:s", "srt", out.path]
    }
    do {
      _ = try await ToolRunner.run(.ffmpeg, args)
    } catch {
      for out in outputs { try? FileManager.default.removeItem(at: out) }
      throw error
    }
    return outputs
  }
}
