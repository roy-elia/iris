#if DEBUG
  import AppKit
  import CoreImage
  import DropCore
  import ImageIO
  import PDFKit
  import SwiftUI

  /// Debug-only: `FileDropUtility --selftest <folder>` builds sample files of every kind, then
  /// for each kind and each wheel segment the app offers, runs the segment the way a drop would:
  /// operations run through the Processor and their outputs are checked; segments that open a
  /// window must open it, and the operation the window saves is run with typical settings;
  /// actions are checked by their effect. Writes `report.md` to the folder.
  @MainActor
  enum SelfTestRunner {
    struct Row {
      let group: String
      let wheel: String
      let segment: String
      let status: String
      let detail: String
    }

    static func runIfRequested() -> Bool {
      let args = CommandLine.arguments
      guard let index = args.firstIndex(of: "--selftest"), index + 1 < args.count else { return false }
      let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
      setvbuf(stdout, nil, _IONBF, 0)
      Task {
        await run(into: folder)
        NSApp.terminate(nil)
      }
      return true
    }

    private static var rows: [Row] = []

    static func run(into folder: URL) async {
      let fm = FileManager.default
      let inputs = folder.appendingPathComponent("inputs")
      let outputs = folder.appendingPathComponent("outputs")
      try? fm.createDirectory(at: inputs, withIntermediateDirectories: true)
      try? fm.createDirectory(at: outputs, withIntermediateDirectories: true)
      // Copy and Copy Path use the clipboard; put back whatever was on it afterwards.
      let saved = (NSPasteboard.general.pasteboardItems ?? []).map { item in
        item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
      }
      defer {
        NSPasteboard.general.clearContents()
        let items = saved.map { pairs -> NSPasteboardItem in
          let item = NSPasteboardItem()
          for (type, data) in pairs { item.setData(data, forType: type) }
          return item
        }
        NSPasteboard.general.writeObjects(items)
      }
      let fixtures: Fixtures
      do {
        fixtures = try await Fixtures.make(in: inputs)
      } catch {
        print("SELFTEST FIXTURES FAILED: \(error)")
        return
      }
      if ProcessInfo.processInfo.environment["FDU_SELFTEST_ONLY"] == nil {
        await shellChecks()
      }
      for (name, urls) in fixtures.groups {
        let files = urls.compactMap { try? DroppedFile.load($0) }
        guard files.count == urls.count else {
          rows.append(
            Row(group: name, wheel: "-", segment: "load", status: "FAIL", detail: "couldn't load inputs"))
          continue
        }
        for kind in WheelKind.allCases {
          for item in kind.items(for: files) {
            if let only = ProcessInfo.processInfo.environment["FDU_SELFTEST_ONLY"],
              !"\(name)/\(item.title)".localizedCaseInsensitiveContains(only)
            {
              continue
            }
            let out = outputs.appendingPathComponent(name).appendingPathComponent(
              "\(kind.rawValue)-\(item.id)")
            try? fm.createDirectory(at: out, withIntermediateDirectories: true)
            print("…\t\(name)\t\(kind.title)\t\(item.title)")
            let (status, detail): (String, String)
            if let reason = item.disabledReason {
              (status, detail) = ("off", reason)
            } else {
              let command = item.command
              (status, detail) =
                await withTimeout(segmentTimeout) {
                  await exercise(command, files: files, out: out, fixtures: fixtures)
                } ?? ("FAIL", "no result after \(segmentTimeout.formatted()) s; the self-test moved on")
            }
            rows.append(
              Row(group: name, wheel: kind.title, segment: item.title, status: status, detail: detail))
            print("\(status)\t\(name)\t\(kind.title)\t\(item.title)\t\(detail)")
          }
        }
      }
      writeReport(to: folder.appendingPathComponent("report.md"))
      let failed = rows.filter { $0.status == "FAIL" }.count
      print("SELFTEST DONE: \(rows.filter { $0.status == "PASS" }.count) passed, \(failed) failed")
    }

    /// The windows the menu opens.
    private static func shellChecks() async {
      for name in ["Settings…", "Getting Started…"] {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        if name == "Settings…" {
          WindowManager.shared.openMain()
        } else {
          WindowManager.shared.openOnboarding()
        }
        try? await Task.sleep(for: .milliseconds(1200))
        let opened = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) && $0.isVisible }
        let size = opened.first.map { "\(Int($0.frame.width))×\(Int($0.frame.height))" } ?? ""
        rows.append(
          Row(
            group: "menu", wheel: "-", segment: name, status: opened.isEmpty ? "FAIL" : "PASS",
            detail: opened.isEmpty ? "no window" : "window opened, \(size)"))
        for w in opened { w.close() }
      }
    }

    /// Longer than any segment takes (the slowest, a video split, takes a few seconds).
    /// `FDU_SELFTEST_TIMEOUT` (seconds) overrides it.
    static let segmentTimeout: Double =
      Double(ProcessInfo.processInfo.environment["FDU_SELFTEST_TIMEOUT"] ?? "") ?? 120

    /// `work`'s result, or nil if it takes longer than `seconds`. A segment that hangs is left
    /// running so the rest of the self-test (and its report) still happens.
    private static func withTimeout(
      _ seconds: Double, _ work: @escaping @MainActor () async -> (String, String)
    ) async -> (String, String)? {
      final class Once {
        var done = false
      }
      let once = Once()
      return await withCheckedContinuation { continuation in
        Task { @MainActor in
          let result = await work()
          guard !once.done else { return }
          once.done = true
          continuation.resume(returning: result)
        }
        Task { @MainActor in
          try? await Task.sleep(for: .seconds(seconds))
          guard !once.done else { return }
          once.done = true
          continuation.resume(returning: nil)
        }
      }
    }

    // MARK: Exercising one segment

    private static func exercise(_ command: WheelCommand, files: [DroppedFile], out: URL, fixtures: Fixtures)
      async
      -> (String, String)
    {
      var settings = AppModel.shared.settings
      settings.outputLocation = .folder(out)
      let processor = Processor(settings: settings)
      let urls = files.map(\.url)

      func check(_ op: FileOperation) async -> (String, String) {
        let result = await processor.run(op, on: files)
        if !result.failures.isEmpty {
          let text = result.failures.map { "\($0.file) \($0.message)" }.joined(separator: "; ")
          // Inputs that rightly have nothing to find get a clear message instead of output.
          let refusals = [
            "No QR codes found", "No clear subject", "already as small as it gets", "has no subtitle tracks",
          ]
          if result.failures.allSatisfy({ f in refusals.contains { f.message.contains($0) } }) {
            return ("refused", text)
          }
          return ("FAIL", text)
        }
        if result.outputs.isEmpty && result.notes.isEmpty { return ("FAIL", "no output") }
        for url in result.outputs {
          var isDir: ObjCBool = false
          guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return ("FAIL", "missing \(url.lastPathComponent)")
          }
          if !isDir.boolValue, ((try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) == 0 {
            return ("FAIL", "empty \(url.lastPathComponent)")
          }
        }
        let names = result.outputs.map(\.lastPathComponent).prefix(3).joined(separator: ", ")
        let more = result.outputs.count > 3 ? " +\(result.outputs.count - 3)" : ""
        return (
          "PASS", result.notes.isEmpty ? names + more : "read: \(result.notes.joined(separator: " | "))"
        )
      }

      /// Opens the segment's window, checks it appeared, closes it, then runs `op`.
      func window(_ titleContains: String, then op: FileOperation?) async -> (String, String) {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        AppModel.shared.perform(command, urls: urls, origin: .overlay)
        try? await Task.sleep(for: .milliseconds(600))
        let opened = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) && $0.isVisible }
        guard let win = opened.first else { return ("FAIL", "no window opened") }
        let title = win.title
        try? await Task.sleep(for: .milliseconds(900))
        for w in opened { w.close() }
        guard let op else { return ("PASS", "window \"\(title)\"") }
        let (status, detail) = await check(op)
        return (status, "window \"\(title)\"; saved: \(detail)")
      }

      let first = files[0]
      switch command {
      case .convert(let format): return await check(.convert(format, quality: 0.8))
      case .toPDF: return await check(files.allSatisfy { $0.kind == .pdf } ? .mergePDFs : .imagesToPDF)
      case .readQR: return await check(.readQRCodes)
      case .grayscale: return await check(.grayscale)
      case .resize: return await window("Resize", then: .resize(.percent(50)))
      case .convertVideo(let o): return await check(.convertVideo(o))
      case .convertAudio(let o): return await check(.convertAudio(o))
      case .convertDocument(let o): return await check(.convertDocument(o))
      case .pdfToImages(let f): return await check(.pdfToImages(f))
      case .pdfToTIFF: return await check(.pdfToTIFF)
      case .pdfToCBZ: return await check(.pdfToCBZ)
      case .splitPDF: return await window("Split", then: .splitPDF(.ranges("1, 2-")))
      case .convertSubtitles(let f): return await check(.convertSubtitles(f))
      case .extractArchive: return await check(.extractArchive)
      case .extractSubtitles: return await check(.extractSubtitles)
      case .convertData(let f): return await check(.convertData(f))
      case .sheetsToCSV: return await check(.sheetsToCSV)
      case .zip: return await check(.zipFiles)

      case .compress:
        if first.kind.isVideo { return await window("Compress", then: .compressVideo(.strength(.medium))) }
        return await window("Compress", then: .compress(quality: 0.5))
      case .metadata:
        return await window(
          "Metadata", then: .editMetadata([MetadataEdit(tag: "XMP-dc:Title", value: "Self test")]))
      case .background: return await window("Background", then: .replaceBackground(.color(.white)))
      case .frame: return await window("Frame", then: .frame(FrameRecipe()))
      case .collage: return await window("Collage", then: .collage(CollageRecipe()))
      case .joinVideos: return await window("Join", then: .joinVideos)
      case .visualizer:
        return await window("Visualizer", then: .audioVisualizer(VisualizerRecipe(size: .square)))
      case .organizePDF:
        let count = PDFDocument(url: first.url)?.pageCount ?? 1
        let plan = PDFPagePlan(
          pages: (0..<count).reversed().map { PDFPageRef(index: $0, rotation: $0 == 0 ? 90 : 0) })
        return await window("Organize", then: .organizePDF(plan))
      case .edit(let tool):
        let recipe: EditRecipe =
          switch tool {
          case .adjust: EditRecipe(brightness: 0.1, contrast: 1.1, saturation: 1.2)
          case .crop: EditRecipe(crop: NormRect(x: 0.1, y: 0.1, width: 0.6, height: 0.6))
          case .annotate:
            EditRecipe(marks: [
              .arrow(
                from: NormPoint(x: 0.2, y: 0.2), to: NormPoint(x: 0.6, y: 0.6),
                color: RGBA(red: 1, green: 0, blue: 0), width: 0.01),
              .text("Self test", at: NormPoint(x: 0.1, y: 0.8), color: .white, size: 0.06, boxWidth: 0.6),
            ])
          case .redact:
            EditRecipe(redactions: [NormRect(x: 0.3, y: 0.3, width: 0.3, height: 0.2)], redactStyle: .blur)
          }
        let op: FileOperation = tool == .crop && files.count > 1 ? .batchEdit(recipe) : .edit(recipe)
        return await window("Edit", then: files.count > 1 && tool != .crop ? nil : op)
      case .videoEditor(let tool):
        let op: FileOperation =
          switch tool {
          case .trim: .editVideo(VideoRecipe(trimStart: 0.3, trimEnd: 1.5))
          case .speed: .editVideo(VideoRecipe(speed: 2))
          case .crop: .editVideo(VideoRecipe(crop: NormRect(x: 0, y: 0, width: 0.5, height: 0.5)))
          case .redact:
            .editVideo(
              VideoRecipe(redactions: [
                TimedRedaction(
                  rect: NormRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), start: 0, end: 1, style: .pixelate)
              ]))
          case .split: .splitVideo(SplitPlan(points: [1]))
          case .frames: .videoSnapshots([0.5, 1.2])
          }
        return await window("Edit", then: op)
      case .audioEditor(let tool):
        let recipe: AudioRecipe =
          switch tool {
          case .trim: AudioRecipe(trimStart: 0.2, trimSilence: true)
          case .bleep: AudioRecipe(bleeps: [BleepRange(start: 0.8, end: 1.2)])
          case .volume: AudioRecipe(normalize: .podcast)
          case .channels: AudioRecipe(channels: .stereo, leftGain: 1, rightGain: 0.4)
          }
        return await window("Edit", then: .editAudio(recipe))

      case .copy:
        AppModel.shared.perform(command, urls: urls, origin: .overlay)
        let copied = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        return copied.map(\.standardizedFileURL) == urls.map(\.standardizedFileURL)
          ? ("PASS", "\(copied.count) file(s) on the pasteboard") : ("FAIL", "pasteboard has \(copied)")
      case .copyPath:
        AppModel.shared.perform(command, urls: urls, origin: .overlay)
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        return text.contains(first.url.lastPathComponent)
          ? ("PASS", "path text copied") : ("FAIL", "pasteboard: \(text)")
      case .float:
        let before = FloatManager.shared.stacks.count
        AppModel.shared.perform(command, urls: urls, origin: .overlay)
        let made = FloatManager.shared.stacks.last
        guard FloatManager.shared.stacks.count == before + 1, let made, made.urls.count == urls.count else {
          return ("FAIL", "no Float made")
        }
        let visible = NSApp.windows.contains { $0 is NSPanel && $0.isVisible }
        FloatManager.shared.close(made.id)
        return visible
          ? ("PASS", "Float with \(made.urls.count) file(s) shown, then closed")
          : ("FAIL", "Float panel not visible")
      case .addToFloat:
        FloatManager.shared.create(with: [fixtures.extra])
        AppModel.shared.perform(command, urls: urls, origin: .overlay)
        guard let stack = FloatManager.shared.stacks.last else { return ("FAIL", "no Float") }
        let ok = stack.urls.count == urls.count + 1
        FloatManager.shared.close(stack.id)
        return ok
          ? ("PASS", "added \(urls.count) to an open Float") : ("FAIL", "Float has \(stack.urls.count)")
      case .airDrop:
        return NSSharingService(named: .sendViaAirDrop) != nil
          ? ("skip", "AirDrop service available; sending needs a person") : ("FAIL", "no AirDrop service")
      case .share:
        var shared: [URL] = []
        SharePresenter.presentOverride = { shared = $0 }
        defer { SharePresenter.presentOverride = nil }
        AppModel.shared.perform(command, urls: urls, origin: .overlay)
        return shared.map(\.standardizedFileURL) == urls.map(\.standardizedFileURL)
          ? ("PASS", "share picker asked for \(shared.count) file(s)") : ("FAIL", "picker got \(shared)")
      case .move:
        return ("skip", "opens a folder picker (FileActions.move is unit-tested)")
      case .terminal:
        let app = NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: AppModel.shared.settings.terminalBundleID)
        return app != nil
          ? ("skip", "would open \(app!.lastPathComponent) at the folder") : ("FAIL", "terminal app missing")
      }
    }

    private static var fm: FileManager { .default }

    // MARK: Report

    private static func writeReport(to url: URL) {
      let pass = rows.filter { $0.status == "PASS" }.count
      let fail = rows.filter { $0.status == "FAIL" }.count
      let skip = rows.filter { $0.status == "skip" }.count
      let off = rows.filter { $0.status == "off" }.count
      let refused = rows.filter { $0.status == "refused" }.count
      var md = "# Feature self-test\n\n\(Date().formatted())\n\n"
      md +=
        "**\(pass) passed, \(fail) failed, \(refused) correctly refused (nothing to find in that input), \(skip) skipped (system UI), \(off) disabled for the input (with the reason shown).**\n\n"
      md += "| Input | Wheel | Segment | Result | Detail |\n|---|---|---|---|---|\n"
      for r in rows {
        let detail = r.detail.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(
          of: "\n", with: " ")
        md += "| \(r.group) | \(r.wheel) | \(r.segment) | \(r.status) | \(detail) |\n"
      }
      try? md.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  // MARK: - Fixtures

  /// Sample inputs of every kind, made locally (images with Core Graphics, media with the
  /// bundled ffmpeg, documents with AppKit).
  struct Fixtures {
    var groups: [(String, [URL])] = []
    var extra: URL

    static func make(in dir: URL) async throws -> Fixtures {
      func file(_ name: String) -> URL { dir.appendingPathComponent(name) }
      // Images: a photo-like scene with a subject, a QR code, and an SVG.
      let scene = try writeScene(file("scene.png"))
      let jpg = file("scene.jpg")
      try ImageOps.write(try ImageOps.loadOriented(scene), as: .jpeg, quality: 0.9, to: jpg)
      let heic = file("scene.heic")
      try ImageOps.write(try ImageOps.loadOriented(scene), as: .heic, quality: 0.8, to: heic)
      let qr = try writeQR(file("menu-qr.png"), text: "https://example.com/menu")
      let svg = file("logo.svg")
      try
        ##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="120"><rect width="200" height="120" fill="#0a6"/><circle cx="100" cy="60" r="40" fill="#fff"/></svg>"##
        .write(to: svg, atomically: true, encoding: .utf8)

      // Formats ImageIO reads: written by ImageIO, as an icon, or (HDR) by hand.
      let psd = file("layers.psd")
      try writeImageIO(scene, to: psd, type: ImageFormat.psd.typeIdentifier)
      let tga = file("texture.tga")
      try writeImageIO(scene, to: tga, type: ImageFormat.tga.typeIdentifier)
      let exr = file("render.exr")
      try writeImageIO(scene, to: exr, type: ImageFormat.exr.typeIdentifier)
      let ico = file("favicon.ico")
      try ImageToolOps.writeIcon(scene, as: .ico, to: ico)
      let dng = file("camera.dng")
      try SampleFiles.writeDNG(to: dng)
      let hdr = file("sky.hdr")
      var rgbe = Data("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 4 +X 4\n".utf8)
      for _ in 0..<16 { rgbe.append(contentsOf: [200, 120, 60, 128]) }
      try rgbe.write(to: hdr)

      // Media.
      func ffmpeg(_ args: [String]) async throws {
        _ = try await ToolRunner.run(
          .ffmpeg, ["-hide_banner", "-nostdin", "-y", "-loglevel", "error"] + args)
      }
      let mp4 = file("clip.mp4")
      try await ffmpeg([
        "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30:duration=2", "-f", "lavfi", "-i",
        "sine=frequency=440:duration=2", "-c:v", "h264_videotoolbox", "-b:v", "2000k", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-shortest", mp4.path,
      ])
      let mov = file("intro.mov")
      try await ffmpeg([
        "-f", "lavfi", "-i", "testsrc=size=640x360:rate=30:duration=1.5", "-f", "lavfi", "-i",
        "sine=frequency=660:duration=1.5", "-c:v", "h264_videotoolbox", "-b:v", "2000k", "-pix_fmt",
        "yuv420p",
        "-c:a", "aac", "-shortest", mov.path,
      ])
      let wav = file("voice.wav")
      try await ffmpeg([
        "-f", "lavfi", "-i", "sine=frequency=330:sample_rate=44100:duration=2", "-af",
        "volume=2,adelay=400|400,apad=pad_dur=0.5", "-ac", "2", wav.path,
      ])
      let mp3 = file("song.mp3")
      try await ffmpeg([
        "-f", "lavfi", "-i", "sine=frequency=523:duration=2", "-ac", "2", "-c:a", "libmp3lame", "-b:a",
        "192k",
        mp3.path,
      ])

      // Other containers the bundled ffmpeg decodes, each with its usual codecs.
      let pattern = [
        "-f", "lavfi", "-i", "testsrc=size=320x240:rate=25:duration=2", "-f", "lavfi", "-i",
        "sine=frequency=550:duration=2",
      ]
      let containers: [(String, [String])] = [
        ("legacy.wmv", ["-c:v", "wmv2", "-c:a", "wmav2"]),
        ("flash.flv", ["-c:v", "flv", "-c:a", "libmp3lame", "-ar", "44100"]),
        ("broadcast.mpg", ["-c:v", "mpeg2video", "-c:a", "mp2"]),
        ("stream.ts", ["-c:v", "h264_videotoolbox", "-c:a", "aac"]),
        ("phone.3gp", ["-s", "176x144", "-c:v", "h263", "-c:a", "aac", "-ar", "8000", "-ac", "1"]),
        ("open.ogv", ["-c:v", "libvpx", "-c:a", "opus", "-strict", "-2", "-ar", "48000"]),
        ("disc.vob", ["-c:v", "mpeg2video", "-c:a", "ac3", "-f", "vob"]),
      ]
      var legacyVideos: [(String, [URL])] = []
      for (name, codecs) in containers {
        try await ffmpeg(pattern + codecs + ["-shortest", file(name).path])
        legacyVideos.append((URL(fileURLWithPath: name).pathExtension, [file(name)]))
      }
      // A video with an English subtitle track.
      let subsSource = file("subs-src.srt")
      try "1\n00:00:00,200 --> 00:00:01,200\nSubtitle track\n".write(
        to: subsSource, atomically: true, encoding: .utf8)
      let subbed = file("subbed.mkv")
      try await ffmpeg([
        "-i", mp4.path, "-i", subsSource.path, "-map", "0", "-map", "1", "-c", "copy", "-c:s", "srt",
        "-metadata:s:s:0", "language=eng", subbed.path,
      ])
      let amr = file("memo.amr")
      try await ffmpeg([
        "-f", "lavfi", "-i", "sine=frequency=440:duration=1.5", "-ar", "8000", "-ac", "1", "-c:a",
        "libopencore_amrnb", "-b:a", "12.2k", amr.path,
      ])
      // APE comes from Monkey's Audio's own encoder.
      let ape = file("album.ape")
      _ = try await ToolRunner.run(.mac, [wav.path, ape.path, "-c2000"])
      let ac3 = file("surround.ac3")
      try await ffmpeg([
        "-f", "lavfi", "-i", "sine=frequency=440:duration=1.5", "-ac", "2", "-c:a", "ac3", ac3.path,
      ])

      // Documents.
      let rich = NSMutableAttributedString()
      rich.append(
        NSAttributedString(
          string: "Quarterly Report\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 26)]))
      rich.append(
        NSAttributedString(
          string: "Revenue grew in every region. ", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
      rich.append(
        NSAttributedString(string: "Costs fell.\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]))
      rich.append(
        NSAttributedString(string: "Outlook\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]))
      rich.append(
        NSAttributedString(
          string: "Steady through next year.\n", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
      let range = NSRange(location: 0, length: rich.length)
      let docx = file("report.docx")
      try rich.data(
        from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
      ).write(to: docx)
      let rtf = file("memo.rtf")
      try rich.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        .write(to: rtf)
      let md = file("notes.md")
      try
        "# Notes\n\nA **bold** plan:\n\n- design\n- build\n- test\n\n| Step | Owner |\n|---|---|\n| Build | Sam |\n"
        .write(to: md, atomically: true, encoding: .utf8)
      let html = file("page.html")
      try "<h1>Welcome</h1><p>Hello <em>world</em>.</p>".write(to: html, atomically: true, encoding: .utf8)
      let csv = file("scores.csv")
      try "Name,Score\nAda,9\n\"Lin, M\",8\n".write(to: csv, atomically: true, encoding: .utf8)
      let json = file("people.json")
      try
        #"[{"name":"Ada","email":"ada@example.com","tags":["math"],"address":{"city":"London"}},{"name":"Lin","email":"lin@example.com","phone":"555-0100"}]"#
        .write(to: json, atomically: true, encoding: .utf8)
      let xml = file("catalog.xml")
      try
        #"<?xml version="1.0"?><catalog><book id="1"><title>Swift</title></book><book id="2"><title>Rust</title></book></catalog>"#
        .write(to: xml, atomically: true, encoding: .utf8)
      let plist = file("settings.plist")
      try PropertyListSerialization.data(
        fromPropertyList: ["theme": "dark", "volume": 7, "recent": ["a.txt", "b.txt"]], format: .xml,
        options: 0
      ).write(to: plist)
      let vcf = file("contacts.vcf")
      try
        "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ada Lovelace\r\nN:Lovelace;Ada;;;\r\nEMAIL:ada@example.com\r\nTEL:555-0100\r\nEND:VCARD\r\n"
        .write(to: vcf, atomically: true, encoding: .utf8)
      let contactsCSV = file("contacts.csv")
      try "Name,Email,Phone\nAda Lovelace,ada@example.com,555-0100\nAlan Turing,alan@example.com,\n"
        .write(to: contactsCSV, atomically: true, encoding: .utf8)
      let pdf = file("deck.pdf")
      try RichText.renderPDF(
        NSAttributedString(
          string: (1...160).map { "Line \($0) of the deck, with enough words to wrap across the page width." }
            .joined(separator: "\n"),
          attributes: [.font: NSFont.systemFont(ofSize: 12)]), to: pdf)
      let pdf2 = file("appendix.pdf")
      let figure = try writeCaption(file("figure.png"), text: "Appendix A: Figures 1 to 4")
      try PDFOps.imagesToPDF([figure, scene], destination: pdf2)
      let srt = file("film.srt")
      try
        "1\n00:00:01,000 --> 00:00:02,500\nHello there\n\n2\n00:00:03,000 --> 00:00:04,000\nGeneral Kenobi\n"
        .write(to: srt, atomically: true, encoding: .utf8)
      let vtt = file("talk.vtt")
      try "WEBVTT\n\n00:00.500 --> 00:02.000\nWelcome\n".write(to: vtt, atomically: true, encoding: .utf8)
      let ass = file("anime.ass")
      try SubtitleOps.write(
        [
          SubtitleCue(start: 1, end: 2.5, text: "Hello <i>there</i>"),
          SubtitleCue(start: 3, end: 4, text: "Bye"),
        ],
        as: .ass
      ).write(to: ass, atomically: true, encoding: .utf8)
      // A Korean SAMI file in CP949, the legacy encoding most of them use.
      let smi = file("drama.smi")
      let cp949 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
          CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
      try
        "<SAMI><BODY>\n<SYNC Start=1000><P Class=KRCC>안녕하세요<br>반갑습니다\n<SYNC Start=2500><P Class=KRCC>&nbsp;\n</BODY></SAMI>\n"
        .data(using: cp949)!.write(to: smi)
      let lrc = file("song.lrc")
      try "[ti:Song]\n[00:01.00]First line\n[00:03.50]Second line\n".write(
        to: lrc, atomically: true, encoding: .utf8)
      let zipSource = file("zip-src")
      try FileManager.default.createDirectory(
        at: zipSource.appendingPathComponent("photos"), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: scene, to: zipSource.appendingPathComponent("photos/scene.png"))
      let zip = file("photos.zip")
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
      p.arguments = ["-rq", zip.path, "photos"]
      p.currentDirectoryURL = zipSource
      try p.run()
      p.waitUntilExit()
      // Other archives, made by the bsdtar that unpacks them.
      func bsdtar(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        p.arguments = args
        p.currentDirectoryURL = zipSource
        try p.run()
        p.waitUntilExit()
      }
      let sevenZip = file("photos.7z")
      try bsdtar(["-c", "--format", "7zip", "-f", sevenZip.path, "photos"])
      let tarball = file("photos.tar.gz")
      try bsdtar(["-czf", tarball.path, "photos"])
      let iso = file("disc.iso")
      try bsdtar(["-c", "--format", "iso9660", "-f", iso.path, "photos"])
      let gz = file("notes.md.gz")
      try bsdtar(["-c", "--format", "raw", "-z", "-f", gz.path, "-C", dir.path, "notes.md"])
      let clip = file("snippet.textClipping")
      try PropertyListSerialization.data(
        fromPropertyList: ["UTI-Data": ["public.utf8-plain-text": "Clipped words"]], format: .binary,
        options: 0
      ).write(to: clip)

      var f = Fixtures(extra: md)
      f.groups = [
        ("png", [scene]), ("jpg", [jpg]), ("heic", [heic]), ("svg", [svg]), ("qr", [qr]),
        ("psd", [psd]), ("tga", [tga]), ("exr", [exr]), ("ico", [ico]), ("hdr", [hdr]), ("dng", [dng]),
        ("images×2", [scene, jpg]),
        ("mp4", [mp4]), ("videos×2", [mp4, mov]), ("subbed.mkv", [subbed]),
        ("wav", [wav]), ("audio×2", [wav, mp3]), ("ac3", [ac3]), ("amr", [amr]),
        ("ape", [ape]),
        ("pdf", [pdf]), ("pdfs×2", [pdf, pdf2]),
        ("docx", [docx]), ("rtf", [rtf]), ("md", [md]), ("html", [html]), ("csv", [csv]),
        ("contacts.csv", [contactsCSV]), ("json", [json]), ("xml", [xml]), ("plist", [plist]), ("vcf", [vcf]),
        ("clipping", [clip]),
        ("srt", [srt]), ("vtt", [vtt]), ("ass", [ass]), ("smi", [smi]), ("lrc", [lrc]), ("zip", [zip]),
        ("7z", [sevenZip]), ("tar.gz", [tarball]), ("iso", [iso]), ("gz", [gz]),
      ]
      f.groups += legacyVideos
      return f
    }

    static func writeImageIO(_ source: URL, to url: URL, type: String) throws {
      let image = try ImageOps.loadOriented(source)
      guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
        throw DropError.writeFailed(url.lastPathComponent)
      }
      CGImageDestinationAddImage(dest, image, nil)
      guard CGImageDestinationFinalize(dest) else { throw DropError.writeFailed(url.lastPathComponent) }
    }

    /// A sky, ground and a person-like figure, so background removal has a subject.
    static func writeScene(_ url: URL) throws -> URL {
      let w = 900
      let h = 600
      let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      ctx.setFillColor(CGColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1))
      ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
      ctx.setFillColor(CGColor(red: 0.35, green: 0.6, blue: 0.3, alpha: 1))
      ctx.fill(CGRect(x: 0, y: 0, width: w, height: 180))
      ctx.setFillColor(CGColor(red: 0.85, green: 0.3, blue: 0.2, alpha: 1))
      ctx.fillEllipse(in: CGRect(x: 390, y: 380, width: 120, height: 120))
      ctx.fill(CGRect(x: 370, y: 140, width: 160, height: 250))
      ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
      ctx.fillEllipse(in: CGRect(x: 720, y: 470, width: 90, height: 90))
      try ImageOps.write(ctx.makeImage()!, as: .png, quality: 1, to: url)
      return url
    }

    /// An image of a line of text (a scanned page, for OCR).
    static func writeCaption(_ url: URL, text: String) throws -> URL {
      let ctx = CGContext(
        data: nil, width: 1400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
      ctx.setFillColor(.white)
      ctx.fill(CGRect(x: 0, y: 0, width: 1400, height: 400))
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(
          string: text, attributes: [.font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black]))
      ctx.textPosition = CGPoint(x: 60, y: 170)
      CTLineDraw(line, ctx)
      try ImageOps.write(ctx.makeImage()!, as: .png, quality: 1, to: url)
      return url
    }

    static func writeQR(_ url: URL, text: String) throws -> URL {
      let filter = CIFilter(name: "CIQRCodeGenerator")!
      filter.setValue(Data(text.utf8), forKey: "inputMessage")
      let image = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
      let padded = image.composited(
        over: CIImage(color: .white).cropped(to: image.extent.insetBy(dx: -40, dy: -40)))
      let cg = CIContext().createCGImage(padded, from: padded.extent)!
      try ImageOps.write(cg, as: .png, quality: 1, to: url)
      return url
    }
  }
#endif
