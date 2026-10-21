import Foundation

/// The outcome of running an operation on a set of files.
public struct OperationResult: Equatable, Sendable {
  public var outputs: [URL] = []
  /// File name (or "" for the whole run) paired with a user-facing message.
  public var failures: [Failure] = []
  /// Text results that aren't files, such as QR code contents.
  public var notes: [String] = []
  /// Files renamed in place, so the rename can be undone.
  public var renames: [Rename] = []
  /// Some outputs went to Downloads because the chosen folder couldn't take them.
  public var savedToDownloads = false

  /// Says why outputs ended up in Downloads, when they did.
  public var downloadsNotice: String? {
    savedToDownloads ? "Saved to Downloads because the original’s folder can’t be written to." : nil
  }

  public struct Rename: Equatable, Sendable {
    public let from: URL
    public let to: URL

    public init(from: URL, to: URL) {
      self.from = from
      self.to = to
    }
  }

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
  /// Called as each file starts and ends, so a batch can show a per-file checklist.
  public var fileEvents: (@Sendable (FileEvent) -> Void)?

  public init(settings: AppSettings) {
    self.settings = settings
  }

  /// One file's step within a batch.
  public struct FileEvent: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case started, done, failed(String) }
    public let name: String
    public let phase: Phase

    public init(name: String, phase: Phase) {
      self.name = name
      self.phase = phase
    }
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
    case .stripAllMetadata:
      if let file = files.first(where: { !$0.kind.isImage && MetadataSupport($0.kind) == nil }) {
        return "\(file.name) isn't supported. Strip all metadata works on images, PDFs, audio, video "
          + "and Word, Excel and PowerPoint files."
      }
    case .stripMetadata, .imagesToPDF, .replaceBackground, .batchEdit, .frame,
      .readQRCodes, .resize,
      .grayscale:
      if !allImages { return imagesOnly(operation) }
      if case .replaceBackground(.image(let path)) = operation, !FileManager.default.fileExists(atPath: path)
      {
        return "Choose a background image."
      }
    case .makeQRCode:
      if !files.allSatisfy({ QROps.canMake(from: $0.kind) }) {
        return "QR codes are made from text and link files."
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
    case .extractSubtitles:
      if !allVideos { return videosOnly(operation) }
    case .convertAudio(let output):
      if let reason = output.unavailableReason { return "\(output.displayName): \(reason)." }
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
      if !files.allSatisfy({ $0.kind.isDocumentLike || $0.kind.isImage }) {
        return "\(operation.summary) works on documents, PDFs, tables, presentations and images."
      }
      if let problem = files.lazy.compactMap({ DocumentOps.problem($0.kind, output: output) }).first {
        return problem
      }
    case .pdfToImages(let format):
      if !files.allSatisfy(\.kind.hasPages) {
        return "\(operation.summary) works on PDFs and presentations only."
      }
      if !format.isWritable { return "\(format.displayName) can't be written on this Mac." }
    case .pdfToTIFF, .pdfToCBZ, .splitPDF:
      if files.contains(where: { $0.kind != .pdf }) { return "\(operation.summary) works on PDFs only." }
    case .organizePDF(let plan):
      if files.count != 1 || files[0].kind != .pdf { return "Organize works on one PDF at a time." }
      if plan.pages.isEmpty { return "Keep at least one page." }
    case .convertSubtitles:
      if !files.allSatisfy(\.kind.isSubtitle) {
        return "\(operation.summary) works on SRT, VTT, ASS, SSA, SAMI and LRC subtitles."
      }
    case .convertData(let output):
      if let file = files.first(where: { file in
        if case .office(let format) = file.kind, file.kind.isSpreadsheet {
          return !(output == .json || output == .vcf) || SpreadsheetOps.problem(format) != nil
        }
        return !(file.kind.dataFormat?.outputs.contains(output) ?? false)
      }) {
        return "\(file.name) can't be converted to \(output.displayName)."
      }
    case .sheetsToCSV:
      if !files.allSatisfy(\.kind.isSpreadsheet) {
        return "\(operation.summary) works on Excel, OpenDocument and Numbers spreadsheets."
      }
      if let file = files.first(where: {
        if case .office(let format) = $0.kind { SpreadsheetOps.problem(format) != nil } else { true }
      }) {
        return "Saving the sheets of \(file.name) as CSV needs Numbers."
      }
    case .extractArchive:
      if files.contains(where: { $0.kind != .archive }) {
        return "Extract works on zip, 7z, tar, gz, bz2, xz and ISO archives."
      }
    case .zipFiles:
      break
    case .transcribe:
      if !files.allSatisfy({ $0.kind.isAudio || $0.kind.isVideo }) {
        return "Transcribe works on audio and video."
      }
    case .summarize:
      if !files.allSatisfy({ $0.kind.isAudio || $0.kind.isVideo || $0.kind.hasReadableText }) {
        return "Summarize works on documents, PDFs, audio and video."
      }
      if let problem = AIOps.languageModelProblem { return problem }
    case .altText:
      if !allImages { return imagesOnly(operation) }
    case .renameByContent:
      if !files.allSatisfy({
        $0.kind.isImage || $0.kind.isAudio || $0.kind.isVideo || $0.kind.hasReadableText
      }
      ) {
        return "Rename from content works on images, documents, PDFs, audio and video."
      }
      if let problem = AIOps.languageModelProblem { return problem }
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
    case .copyMetadata(let path):
      if let file = files.first(where: { MetadataSupport($0.kind) == nil }) {
        return file.kind.isImage
          ? "\(file.name) can't hold photo metadata. Convert it to JPEG, PNG or TIFF first."
          : "\(file.name) isn't supported. Copy metadata works on images, PDFs, audio, video "
            + "and Word, Excel and PowerPoint files."
      }
      if !FileManager.default.fileExists(atPath: path) {
        return "The file to copy metadata from is no longer there."
      }
      if files.contains(where: { MetadataSupport($0.kind) == .office }),
        MetadataSupport(FileKind(url: URL(fileURLWithPath: path))) != .office
      {
        return "Word, Excel and PowerPoint files can only take metadata from another Word, Excel "
          + "or PowerPoint file."
      }
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
      let dir = outputDirectory(for: file.url, in: &result)
      return claim(dir.appendingPathComponent(name).appendingPathExtension(ext))
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

    case .stripMetadata, .stripAllMetadata:
      let complete = operation == .stripAllMetadata
      for file in files {
        if !file.kind.isImage {
          let out = target(file, suffix: "no-metadata", ext: file.url.pathExtension)
          await record(&result, file: file, output: out) {
            switch MetadataSupport(file.kind) {
            case .pdf: try await MetadataOps.stripPDF(file.url, destination: out)
            case .office: try await MetadataOps.stripOffice(file.url, destination: out)
            default: try await MetadataOps.stripMedia(file.url, destination: out)
            }
          }
          continue
        }
        // Read-only formats (SVG, and WebP without the encoder) come out as PNG.
        let format = ImageFormat(fileExtension: file.url.pathExtension)
        let ext = format.map { $0.isImageIOWritable } == true ? file.url.pathExtension : "png"
        let out = target(file, suffix: "no-metadata", ext: ext)
        await record(&result, file: file, output: out) {
          try ImageOps.stripMetadata(readable(file), destination: out, complete: complete)
          if complete { try await MetadataOps.removeEverything(from: out) }
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

    case .copyMetadata(let path):
      let source = URL(fileURLWithPath: path)
      for file in files {
        let out = target(file, suffix: "metadata", ext: file.url.pathExtension)
        await record(&result, file: file, output: out) {
          try await MetadataOps.copyExact(from: source, onto: file.url, destination: out)
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
      let out = claim(outputDirectory(for: files[0].url, in: &result).appendingPathComponent("Collage.png"))
      await record(&result, file: nil, output: out) {
        try ImageOps.write(CollageOps.render(files.map(\.url), recipe: recipe), as: .png, quality: 1, to: out)
      }

    case .makeQRCode:
      for file in files {
        guard QROps.canMake(from: file.kind), let text = QROps.payload(for: file.url) else {
          result.failures.append(
            .init(
              file: file.name,
              message: "Only text and link files shorter than \(QROps.maxPayloadLength) characters become QR codes."
            ))
          continue
        }
        let out = target(file, suffix: "QR", ext: "png")
        await record(&result, file: file, output: out) {
          try ImageOps.write(QROps.make(text), as: .png, quality: 1, to: out)
        }
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
      let options = settings.format(output.rawValue)
      for (i, file) in files.enumerated() {
        let out = target(file, suffix: output.nameSuffix, ext: output.fileExtension)
        await record(&result, file: file, output: out) {
          try await VideoOps.convert(file.url, to: output, options: options, destination: out) { p in
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
        outputDirectory(for: files[0].url, in: &result).appendingPathComponent("Joined")
          .appendingPathExtension(ext))
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

    case .extractSubtitles:
      for file in files {
        do {
          result.outputs += try await VideoOps.extractSubtitles(file.url) { label in
            target(file, suffix: label, ext: "srt")
          }
        } catch {
          result.failures.append(.init(file: file.name, message: Self.message(for: error)))
        }
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
          // A presentation is exported to PDF first, then saved slide by slide.
          var pages = file.url
          var scratch: URL?
          defer { scratch.map { try? FileManager.default.removeItem(at: $0) } }
          if case .office(let office) = file.kind, office.isPresentation {
            let dir = try SystemProcess.scratchDirectory()
            scratch = dir
            pages = dir.appendingPathComponent("slides.pdf")
            try await IWorkOps.exportPDF(
              file.url, app: office.app, powerPoint: office.powerPointExports, destination: pages)
          }
          let word = scratch == nil ? "page" : "slide"
          let outs = try PDFPageOps.images(pages, format: format) { index in
            target(file, suffix: "\(word) \(index + 1)", ext: format.fileExtension)
          }
          result.outputs += outs
        } catch {
          result.failures.append(.init(file: file.name, message: Self.message(for: error)))
        }
      }

    case .pdfToTIFF:
      for file in files {
        let out = target(file, suffix: "", ext: "tiff")
        await record(&result, file: file, output: out) { try PDFExportOps.tiff(file.url, destination: out) }
      }

    case .pdfToCBZ:
      for file in files {
        let out = target(file, suffix: "", ext: "cbz")
        await record(&result, file: file, output: out) {
          try await PDFExportOps.cbz(file.url, destination: out)
        }
      }

    case .splitPDF(let plan):
      for file in files {
        do {
          result.outputs += try PDFExportOps.split(file.url, plan: plan) { group in
            target(file, suffix: PDFSplit.label(group), ext: "pdf")
          }
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
        let out = target(file, suffix: "", ext: format.fileExtension)
        await record(&result, file: file, output: out) {
          try SubtitleOps.convert(file.url, to: format, destination: out)
        }
      }

    case .convertData(let output):
      for file in files {
        // Workbooks are saved sheet by sheet.
        if case .office(let format) = file.kind, file.kind.isSpreadsheet {
          do {
            result.outputs += try await SpreadsheetOps.exportData(file.url, format: format, to: output) {
              sheet in target(file, suffix: sheet ?? "", ext: output.fileExtension)
            }
          } catch {
            result.failures.append(.init(file: file.name, message: Self.message(for: error)))
          }
          continue
        }
        let out = target(file, suffix: "", ext: output.fileExtension)
        await record(&result, file: file, output: out) {
          try DataOps.convert(file.url, to: output, destination: out)
        }
      }

    case .sheetsToCSV:
      for (i, file) in files.enumerated() {
        guard case .office(let format) = file.kind else { continue }
        do {
          result.outputs += try await SpreadsheetOps.exportCSV(file.url, format: format) { sheet in
            target(file, suffix: sheet ?? "", ext: "csv")
          }
        } catch {
          result.failures.append(.init(file: file.name, message: Self.message(for: error)))
        }
        progress?(Double(i + 1) / Double(files.count))
      }

    case .extractArchive:
      for file in files {
        let folder = claim(
          outputDirectory(for: file.url, in: &result)
            .appendingPathComponent(ArchiveOps.outputName(for: file.url)))
        await record(&result, file: file, output: folder) {
          try await DocumentOps.extract(file.url, into: folder)
        }
      }

    case .transcribe(let format):
      for (i, file) in files.enumerated() {
        let out = target(file, suffix: "", ext: format.rawValue)
        await record(&result, file: file, output: out) {
          let cues = try await AIOps.transcribe(file.url)
          try SubtitleOps.write(cues, as: format).write(to: out, atomically: true, encoding: .utf8)
        }
        progress?(Double(i + 1) / Double(files.count))
      }

    case .summarize:
      for (i, file) in files.enumerated() {
        let out = target(file, suffix: "summary", ext: "md")
        await record(&result, file: file, output: out) {
          let text: String =
            file.kind.isAudio || file.kind.isVideo
            ? try await AIOps.transcribe(file.url).map(\.text).joined(separator: " ")
            : try await RichText.load(file.url, kind: file.kind).string
          let summary = try await AIOps.summarize(text, title: file.name)
          try summary.write(to: out, atomically: true, encoding: .utf8)
        }
        progress?(Double(i + 1) / Double(files.count))
      }

    case .altText:
      for (i, file) in files.enumerated() {
        do {
          let text = try await AIOps.altText(file.url)
          result.notes.append(files.count == 1 ? text : "\(file.name): \(text)")
        } catch {
          result.failures.append(.init(file: file.name, message: Self.message(for: error)))
        }
        progress?(Double(i + 1) / Double(files.count))
      }

    case .renameByContent:
      for (i, file) in files.enumerated() {
        do {
          let stem = try await AIOps.suggestedName(for: file)
          let renamed = try AIOps.rename(file.url, to: stem)
          result.outputs.append(renamed)
          result.renames.append(.init(from: file.url, to: renamed))
        } catch {
          result.failures.append(.init(file: file.name, message: Self.message(for: error)))
        }
        progress?(Double(i + 1) / Double(files.count))
      }

    case .zipFiles:
      let name = files.count == 1 ? files[0].name : "Archive"
      let out = claim(outputDirectory(for: files[0].url, in: &result).appendingPathComponent("\(name).zip"))
      await record(&result, file: nil, output: out) {
        try await ArchiveOps.zip(files.map(\.url), destination: out)
      }

    case .mergePDFs:
      let out = claim(outputDirectory(for: files[0].url, in: &result).appendingPathComponent("Merged.pdf"))
      await record(&result, file: nil, output: out) {
        try PDFOps.merge(files.map(\.url), destination: out)
      }

    case .imagesToPDF:
      let name = files.count == 1 ? base(files[0]) : "Images"
      let out = claim(outputDirectory(for: files[0].url, in: &result).appendingPathComponent("\(name).pdf"))
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

  private func outputDirectory(for source: URL, in result: inout OperationResult) -> URL {
    let (dir, fellBack) = OutputNamer.resolve(for: source, location: settings.outputLocation)
    if fellBack { result.savedToDownloads = true }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func record(
    _ result: inout OperationResult, file: DroppedFile?, output: URL, _ work: () async throws -> Void
  ) async {
    let name = file?.name ?? output.lastPathComponent
    fileEvents?(.init(name: name, phase: .started))
    do {
      try await work()
      result.outputs.append(output)
      fileEvents?(.init(name: name, phase: .done))
    } catch {
      let message = Self.message(for: error)
      result.failures.append(.init(file: file?.name ?? "", message: message))
      fileEvents?(.init(name: name, phase: .failed(message)))
    }
  }
}
