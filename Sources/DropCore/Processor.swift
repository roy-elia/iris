import Foundation

/// The outcome of running an operation on a set of files.
public struct OperationResult: Equatable, Sendable {
  public var outputs: [URL] = []
  /// File name (or "" for the whole run) paired with a user-facing message.
  public var failures: [Failure] = []
  /// Text results that aren't files, such as QR code contents.
  public var notes: [String] = []

  public struct Failure: Equatable, Sendable {
    public let file: String
    public let message: String

    public init(file: String, message: String) {
      self.file = file
      self.message = message
    }
  }

  public init(outputs: [URL] = [], failures: [Failure] = [], notes: [String] = []) {
    self.outputs = outputs
    self.failures = failures
    self.notes = notes
  }

  public var succeeded: Bool { failures.isEmpty && (!outputs.isEmpty || !notes.isEmpty) }

  public func historyEntry(for operation: FileOperation, inputCount: Int) -> HistoryEntry {
    HistoryEntry(
      operation: operation.summary,
      inputCount: inputCount,
      outputs: outputs.map(\.lastPathComponent),
      errors: failures.map { $0.file.isEmpty ? $0.message : "\($0.file): \($0.message)" })
  }
}

/// Runs operations on dropped files. Never overwrites existing files.
public struct Processor: Sendable {
  public var settings: AppSettings

  public init(settings: AppSettings) {
    self.settings = settings
  }

  /// Checks that the inputs suit the operation. Returns a message if they do not.
  public static func validate(_ operation: FileOperation, files: [DroppedFile]) -> String? {
    if files.isEmpty { return "Drop some files first." }
    let allImages = !files.contains(where: { !$0.kind.isImage })
    let allVideos = !files.contains(where: { !$0.kind.isVideo })
    let allAudio = !files.contains(where: { !$0.kind.isAudio })
    let allSound = !files.contains(where: { !$0.kind.isAudio && !$0.kind.isVideo })
    switch operation {
    case .convert(let format, _):
      if !format.isWritable { return "\(format.displayName) can't be written on this Mac." }
      if !allImages { return imagesOnly(operation) }
    case .stripMetadata, .imagesToPDF, .replaceBackground, .batchEdit, .frame, .readQRCodes, .resize,
      .grayscale:
      if !allImages { return imagesOnly(operation) }
      if case .replaceBackground(.image(let path)) = operation, !FileManager.default.fileExists(atPath: path)
      {
        return "Choose a background image."
      }
    case .edit:
      if files.count != 1 || !files[0].kind.isImage { return "Edit works on one image at a time." }
    case .compress:
      if files.contains(where: { !$0.kind.isImage && $0.kind != .pdf }) {
        return "Compress works on images and PDFs."
      }
    case .convertVideo(let output):
      if !allVideos { return videosOnly(operation) }
      if let reason = output.unavailableReason { return "\(output.displayName): \(reason)." }
    case .compressVideo(let compression):
      if !allVideos { return videosOnly(operation) }
      if case .target(let bytes) = compression, bytes < TargetSizeOps.minimumTarget {
        return "Enter a target size of at least 1 KB."
      }
    case .editVideo, .splitVideo, .videoSnapshots:
      if files.count != 1 || !files[0].kind.isVideo {
        return "\(operation.summary) works on one video at a time."
      }
      if case .videoSnapshots(let times) = operation, times.isEmpty {
        return "Select at least one frame within the video."
      }
    case .convertAudio:
      if !allSound { return "\(operation.summary) works on audio and video files." }
    case .editAudio(let recipe):
      if !allAudio { return audioOnly(operation) }
      if recipe.isIdentity { return "There are no audio changes to save." }
    case .audioVisualizer(let recipe):
      if !allAudio { return audioOnly(operation) }
      if let path = recipe.backgroundImage, !FileManager.default.fileExists(atPath: path) {
        return "Choose a background image."
      }
    case .convertDocument(let output):
      if let reason = output.unavailableReason { return "\(output.displayName): \(reason)." }
      if !files.allSatisfy(\.kind.isDocumentLike) {
        return "\(operation.summary) works on documents, PDFs, tables and presentations."
      }
      if let problem = files.lazy.compactMap({ DocumentOps.problem($0.kind, output: output) }).first {
        return problem
      }
    case .pdfToImages(let format):
      if files.contains(where: { $0.kind != .pdf }) { return "\(operation.summary) works on PDFs only." }
      if !format.isWritable { return "\(format.displayName) can't be written on this Mac." }
    case .organizePDF(let plan):
      if files.count != 1 || files[0].kind != .pdf { return "Organize works on one PDF at a time." }
      if plan.pages.isEmpty { return "Keep at least one page." }
    case .convertSubtitles:
      if !files.allSatisfy(\.kind.isSubtitle) {
        return "\(operation.summary) works on SRT and VTT subtitles."
      }
    case .extractArchive:
      if files.contains(where: { $0.kind != .archive }) { return "Extract works on zip archives." }
    case .joinVideos:
      if !allVideos { return videosOnly(operation) }
      if files.count < 2 { return "Select at least two videos to join." }
    case .compressToSize(let bytes):
      if !allImages { return imagesOnly(operation) }
      if bytes < TargetSizeOps.minimumTarget { return "Enter a target size of at least 1 KB." }
    case .editMetadata(let edits):
      if !allImages { return imagesOnly(operation) }
      if let file = files.first(where: { !Self.canEditMetadata($0) }) {
        return "\(file.name) can't hold photo metadata. Convert it to JPEG, PNG or TIFF first."
      }
      if edits.isEmpty { return "There are no metadata changes to save." }
    case .collage:
      if !allImages { return imagesOnly(operation) }
      if files.count < 2 { return "Drop at least two images to make a collage." }
    case .mergePDFs:
      if files.contains(where: { $0.kind != .pdf }) { return "Merge PDFs works on PDF files only." }
      if files.count < 2 { return "Drop at least two PDFs to merge." }
    }
    return nil
  }

  /// Whether ExifTool can write `file`'s metadata.
  public static func canEditMetadata(_ file: DroppedFile) -> Bool {
    if case .image(let format) = file.kind { return format.supportsMetadataEditing }
    return false
  }

  private static func videosOnly(_ operation: FileOperation) -> String {
    let names = VideoFormat.allCases.map(\.displayName).joined(separator: ", ")
    return "\(operation.summary) works on videos only (\(names))."
  }

  private static func audioOnly(_ operation: FileOperation) -> String {
    let names = AudioFormat.allCases.map(\.displayName).joined(separator: ", ")
    return "\(operation.summary) works on audio files only (\(names))."
  }

  private static func imagesOnly(_ operation: FileOperation) -> String {
    let names = ImageFormat.allCases.map(\.displayName).joined(separator: ", ")
    return "\(operation.summary) works on images only (\(names))."
  }

  /// Runs `operation`. Per-file operations keep going past individual failures.
  public func run(
    _ operation: FileOperation, on files: [DroppedFile], progress: (@Sendable (Double) -> Void)? = nil
  ) async -> OperationResult {
    var result = OperationResult()
    if let message = Self.validate(operation, files: files) {
      result.failures.append(.init(file: "", message: message))
      return result
    }

    var reserved: Set<URL> = []
    func claim(_ desired: URL) -> URL {
      let url = OutputNamer.uniqueURL(for: desired, reserved: reserved)
      reserved.insert(url.standardizedFileURL)
      return url
    }
    func base(_ file: DroppedFile) -> String { file.url.deletingPathExtension().lastPathComponent }
    func target(_ file: DroppedFile, suffix: String, ext: String) -> URL {
      let name = suffix.isEmpty ? base(file) : "\(base(file)) \(suffix)"
      return claim(outputDirectory(for: file.url).appendingPathComponent(name).appendingPathExtension(ext))
    }
    /// A file ImageIO can read: SVG is rasterised first.
    func readable(_ file: DroppedFile) throws -> URL { try ImageInput.readableURL(for: file.url) }

    switch operation {
    case .convert(let format, let quality):
      let options = settings.format(format.rawValue)
      for file in files {
        let out = target(file, suffix: "", ext: format.fileExtension)
        await record(&result, file: file, output: out) {
          try await ImageConvert.convert(
            file.url, to: format, quality: quality, options: options, destination: out)
        }
      }

    case .stripMetadata:
      for file in files {
        // Read-only formats (SVG, and WebP without the encoder) come out as PNG.
        let format = ImageFormat(fileExtension: file.url.pathExtension)
        let ext = format.map { $0.isImageIOWritable } == true ? file.url.pathExtension : "png"
        let out = target(file, suffix: "no-metadata", ext: ext)
        await record(&result, file: file, output: out) {
          try ImageOps.stripMetadata(readable(file), destination: out)
        }
      }

    case .compress(let quality):
      for file in files {
        let input = (try? file.kind.isImage ? readable(file) : file.url) ?? file.url
        let ext = CompressOps.outputExtension(for: input, kind: file.kind)
        let out = target(file, suffix: "compressed", ext: ext)
        await record(&result, file: file, output: out) {
          try CompressOps.compress(input, kind: file.kind, quality: quality, destination: out)
        }
      }

    case .compressToSize(let bytes):
      for file in files {
        let format = TargetSizeOps.outputFormat(for: file.url)
        let out = target(file, suffix: "compressed", ext: format.fileExtension)
        await record(&result, file: file, output: out) {
          try await TargetSizeOps.compress(file.url, target: bytes, format: format, destination: out)
        }
      }

    case .replaceBackground(let fill):
      for file in files {
        let ext = BackgroundOps.outputFormat(for: file.url, fill: fill).fileExtension
        let out = target(file, suffix: "no-bg", ext: ext)
        await record(&result, file: file, output: out) {
          try BackgroundOps.replaceBackground(readable(file), fill: fill, destination: out)
        }
      }

    case .resize(let spec):
      for file in files {
        let out = target(file, suffix: "resized", ext: EditOps.outputFormat(for: file.url).fileExtension)
        await record(&result, file: file, output: out) {
          try ImageToolOps.resize(readable(file), spec: spec, destination: out)
        }
      }

    case .grayscale:
      for file in files {
        let out = target(file, suffix: "grayscale", ext: EditOps.outputFormat(for: file.url).fileExtension)
        await record(&result, file: file, output: out) {
          try ImageToolOps.grayscale(readable(file), destination: out)
        }
      }

    case .edit(let recipe):
      let file = files[0]
      let out = target(file, suffix: "edited", ext: EditOps.outputFormat(for: file.url).fileExtension)
      await record(&result, file: file, output: out) {
        try EditOps.apply(readable(file), recipe: recipe, destination: out)
      }

    case .batchEdit(let recipe):
      for file in files {
        let out = target(file, suffix: "edited", ext: EditOps.outputFormat(for: file.url).fileExtension)
        await record(&result, file: file, output: out) {
          try EditOps.apply(readable(file), recipe: recipe, destination: out)
        }
      }

    case .editMetadata(let edits):
      for file in files {
        let out = target(file, suffix: "metadata", ext: file.url.pathExtension)
        await record(&result, file: file, output: out) {
          try await MetadataOps.write(file.url, edits: edits, destination: out)
        }
      }

    case .frame(let recipe):
      for file in files {
        let out = target(file, suffix: "framed", ext: "png")
        await record(&result, file: file, output: out) {
          let image = try ImageOps.loadOriented(readable(file))
          try ImageOps.write(FrameOps.render(image, recipe: recipe), as: .png, quality: 1, to: out)
        }
      }

    case .collage(let recipe):
      let out = claim(outputDirectory(for: files[0].url).appendingPathComponent("Collage.png"))
      await record(&result, file: nil, output: out) {
        try ImageOps.write(CollageOps.render(files.map(\.url), recipe: recipe), as: .png, quality: 1, to: out)
      }

    case .readQRCodes:
      for file in files {
        do {
          let codes = try QROps.read(file.url)
          if codes.isEmpty {
            result.failures.append(.init(file: file.name, message: "No QR codes found."))
          } else {
            result.notes += codes
          }
        } catch {
          result.failures.append(.init(file: file.name, message: Self.message(for: error)))
        }
      }

    case .convertVideo(let output):
      for (i, file) in files.enumerated() {
        let out = target(file, suffix: "", ext: output.fileExtension)
        await record(&result, file: file, output: out) {
          try await VideoOps.convert(file.url, to: output, destination: out) { p in
            progress?((Double(i) + p) / Double(files.count))
          }
        }
      }

    case .compressVideo(let compression):
      for (i, file) in files.enumerated() {
        let out = target(file, suffix: "compressed", ext: Self.videoContainer(for: file.url).fileExtension)
        await record(&result, file: file, output: out) {
          try await VideoOps.compress(file.url, compression: compression, destination: out) { p in
            progress?((Double(i) + p) / Double(files.count))
          }
        }
      }

    case .editVideo(let recipe):
      let file = files[0]
      let out = target(file, suffix: "edited", ext: Self.videoContainer(for: file.url).fileExtension)
      await record(&result, file: file, output: out) {
        try await VideoOps.convert(
          file.url, to: Self.videoContainer(for: file.url), recipe: recipe, destination: out,
          progress: progress)
      }

    case .splitVideo(let plan):
      let file = files[0]
      let ext = Self.videoContainer(for: file.url).fileExtension
      do {
        let info = try await VideoOps.probe(file.url)
        let keptCount = plan.clips(duration: info.duration).indices.filter { !plan.removed.contains($0) }
          .count
        let outs =
          plan.joinKept
          ? [target(file, suffix: "edited", ext: ext)]
          : (1...max(keptCount, 1)).map { target(file, suffix: "part \($0)", ext: ext) }
        try await VideoOps.split(file.url, plan: plan, destinations: outs, progress: progress)
        result.outputs += outs
      } catch {
        result.failures.append(.init(file: file.name, message: Self.message(for: error)))
      }

    case .joinVideos:
      let ext = Self.videoContainer(for: files[0].url).fileExtension
      let out = claim(
        outputDirectory(for: files[0].url).appendingPathComponent("Joined").appendingPathExtension(ext))
      await record(&result, file: nil, output: out) {
        try await VideoOps.join(files.map(\.url), destination: out, progress: progress)
      }

    case .videoSnapshots(let times):
      let file = files[0]
      let outs = times.map { target(file, suffix: VideoOps.timeLabel($0), ext: "png") }
      do {
        try await VideoOps.snapshots(file.url, times: times, destinations: outs)
        result.outputs += outs
      } catch {
        for out in outs { try? FileManager.default.removeItem(at: out) }
        result.failures.append(.init(file: file.name, message: Self.message(for: error)))
      }

    case .convertAudio(let output):
      let options = settings.format(output.rawValue)
      for (i, file) in files.enumerated() {
        let out = target(file, suffix: "", ext: output.fileExtension)
        await record(&result, file: file, output: out) {
          try await AudioOps.convert(
            file.url, to: output, bitDepth: options.audioBitDepth ?? 16,
            bitrateKbps: options.audioBitrateKbps,
            destination: out
          ) { p in progress?((Double(i) + p) / Double(files.count)) }
        }
      }

    case .editAudio(let recipe):
      for (i, file) in files.enumerated() {
        let output = AudioOps.output(for: file.url)
        let options = settings.format(output.rawValue)
        let out = target(file, suffix: "edited", ext: output.fileExtension)
        await record(&result, file: file, output: out) {
          try await AudioOps.convert(
            file.url, to: output, bitDepth: options.audioBitDepth ?? 16,
            bitrateKbps: options.audioBitrateKbps,
            recipe: recipe, destination: out
          ) { p in progress?((Double(i) + p) / Double(files.count)) }
        }
      }

    case .audioVisualizer(let recipe):
      for (i, file) in files.enumerated() {
        let out = target(file, suffix: "visualizer", ext: "mp4")
        await record(&result, file: file, output: out) {
          try await AudioOps.visualize(file.url, recipe: recipe, destination: out) { p in
            progress?((Double(i) + p) / Double(files.count))
          }
        }
      }

    case .convertDocument(let output):
      for (i, file) in files.enumerated() {
        let out = target(file, suffix: "", ext: output.fileExtension)
        await record(&result, file: file, output: out) {
          try await DocumentOps.convert(file, to: output, destination: out)
        }
        progress?(Double(i + 1) / Double(files.count))
      }

    case .pdfToImages(let format):
      for file in files {
        do {
          let outs = try PDFPageOps.images(file.url, format: format) { index in
            target(file, suffix: "page \(index + 1)", ext: format.fileExtension)
          }
          result.outputs += outs
        } catch {
          result.failures.append(.init(file: file.name, message: Self.message(for: error)))
        }
      }

    case .organizePDF(let plan):
      let file = files[0]
      let out = target(file, suffix: "organized", ext: "pdf")
      await record(&result, file: file, output: out) {
        try PDFPageOps.organize(file.url, plan: plan, destination: out)
      }

    case .convertSubtitles(let format):
      for file in files {
        let out = target(file, suffix: "", ext: format.rawValue)
        await record(&result, file: file, output: out) {
          try SubtitleOps.convert(file.url, to: format, destination: out)
        }
      }

    case .extractArchive:
      for file in files {
        let folder = claim(outputDirectory(for: file.url).appendingPathComponent(base(file)))
        await record(&result, file: file, output: folder) {
          try await DocumentOps.extract(file.url, into: folder)
        }
      }

    case .mergePDFs:
      let out = claim(outputDirectory(for: files[0].url).appendingPathComponent("Merged.pdf"))
      await record(&result, file: nil, output: out) {
        try PDFOps.merge(files.map(\.url), destination: out)
      }

    case .imagesToPDF:
      let name = files.count == 1 ? base(files[0]) : "Images"
      let out = claim(outputDirectory(for: files[0].url).appendingPathComponent("\(name).pdf"))
      await record(&result, file: nil, output: out) {
        try PDFOps.imagesToPDF(files.map { (try? readable($0)) ?? $0.url }, destination: out)
      }
    }
    return result
  }

  /// The container edited videos are written in: the source's, if it can be written.
  static func videoContainer(for source: URL) -> VideoOutput {
    let output = VideoOutput(rawValue: source.pathExtension.lowercased())
    return output.flatMap { !$0.isAudioOnly && $0 != .gif && $0.isAvailable ? $0 : nil } ?? .mp4
  }

  static func message(for error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  }

  private func outputDirectory(for source: URL) -> URL {
    let dir = OutputNamer.directory(for: source, location: settings.outputLocation)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func record(
    _ result: inout OperationResult, file: DroppedFile?, output: URL, _ work: () async throws -> Void
  ) async {
    do {
      try await work()
      result.outputs.append(output)
    } catch {
      result.failures.append(.init(file: file?.name ?? "", message: Self.message(for: error)))
    }
  }
}
