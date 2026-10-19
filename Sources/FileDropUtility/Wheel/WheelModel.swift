import AppKit
import DropCore

/// The three wheels, each opened by holding a modifier key while dragging files.
enum WheelKind: String, CaseIterable, Identifiable {
  case convert, tools, actions
  var id: String { rawValue }

  var title: String {
    switch self {
    case .convert: "Convert"
    case .tools: "Tools"
    case .actions: "Actions"
    }
  }

  var longTitle: String {
    switch self {
    case .convert: "File Converter"
    case .tools: "File Tools"
    case .actions: "File Actions"
    }
  }

  /// The modifier combination that opens this wheel, from Settings.
  func combo(in modifiers: WheelModifiers) -> ModifierCombo {
    switch self {
    case .convert: modifiers.convert
    case .tools: modifiers.tools
    case .actions: modifiers.actions
    }
  }

  func setCombo(_ combo: ModifierCombo, in modifiers: inout WheelModifiers) {
    switch self {
    case .convert: modifiers.convert = combo
    case .tools: modifiers.tools = combo
    case .actions: modifiers.actions = combo
    }
  }

  @MainActor var keySymbol: String { combo(in: AppModel.shared.settings.wheelModifiers).symbols }
  @MainActor var keyName: String { combo(in: AppModel.shared.settings.wheelModifiers).names }

  var systemImage: String {
    switch self {
    case .convert: "arrow.triangle.2.circlepath"
    case .tools: "wrench.and.screwdriver"
    case .actions: "bolt"
    }
  }

  /// Which wheel the held modifiers ask for, if any. The combination must match
  /// exactly, so ⇧⌘ doesn't open the ⇧ wheel.
  static func forModifiers(_ flags: NSEvent.ModifierFlags, in modifiers: WheelModifiers) -> WheelKind? {
    let combo = ModifierCombo(
      shift: flags.contains(.shift), command: flags.contains(.command), control: flags.contains(.control),
      option: flags.contains(.option))
    guard !combo.isEmpty else { return nil }
    return allCases.first { $0.combo(in: modifiers) == combo }
  }
}

/// Editor tool to start in when a tool segment opens the editor.
enum EditorTool: String, CaseIterable, Identifiable {
  case adjust, crop, annotate, redact
  var id: String { rawValue }

  var title: String {
    switch self {
    case .adjust: "Adjust"
    case .crop: "Crop"
    case .annotate: "Annotate"
    case .redact: "Redact"
    }
  }

  var systemImage: String {
    switch self {
    case .adjust: "slider.horizontal.3"
    case .crop: "crop"
    case .annotate: "pencil.tip.crop.circle"
    case .redact: "eye.slash"
    }
  }
}

/// What a wheel segment does.
enum WheelCommand: Equatable {
  case convert(ImageFormat)
  case toPDF
  case compress
  case metadata
  case background
  case frame
  case collage
  case readQR
  case resize
  case grayscale
  case edit(EditorTool)
  case convertVideo(VideoOutput)
  case videoEditor(VideoTool)
  case joinVideos
  case extractSubtitles
  case convertAudio(AudioOutput)
  case audioEditor(AudioTool)
  case visualizer
  case convertDocument(DocumentOutput)
  case pdfToImages(ImageFormat)
  case pdfToTIFF
  case pdfToCBZ
  case splitPDF
  case organizePDF
  case convertSubtitles(SubtitleFormat)
  case convertData(DataFormat)
  case sheetsToCSV
  case extractArchive
  case airDrop
  case share
  case float
  case addToFloat
  case copy
  case copyPath
  case zip
  case move
  case terminal
}

struct WheelItem: Identifiable, Equatable {
  let id: String
  let title: String
  let systemImage: String?
  let command: WheelCommand
  /// Why the segment can't be used right now, if it can't.
  var disabledReason: String?

  var isEnabled: Bool { disabledReason == nil }
}

extension WheelKind {
  /// Segments when every dropped file is a video.
  func videoItems(count: Int) -> [WheelItem] {
    let oneVideo: String? = count == 1 ? nil : "One video at a time"
    switch self {
    case .convert:
      let outputs: [VideoOutput] = [.mp4, .hevc, .mp4720, .mov, .m4v, .mkv, .avi, .webm, .gif, .mp3, .m4a]
      return outputs.map { output in
        WheelItem(
          id: "v-\(output.rawValue)", title: output.displayName, systemImage: nil,
          command: .convertVideo(output),
          disabledReason: output.unavailableReason)
      }
    case .tools:
      func tool(_ t: VideoTool, _ reason: String? = nil) -> WheelItem {
        WheelItem(
          id: "v-\(t.rawValue)", title: t.title, systemImage: t.systemImage, command: .videoEditor(t),
          disabledReason: reason)
      }
      return [
        WheelItem(
          id: "v-compress", title: "Compress", systemImage: "arrow.down.right.and.arrow.up.left",
          command: .compress),
        tool(.trim, oneVideo), tool(.split, oneVideo),
        WheelItem(
          id: "v-join", title: "Join", systemImage: "rectangle.stack.badge.plus", command: .joinVideos,
          disabledReason: count >= 2 ? nil : "Two or more videos"),
        tool(.speed, oneVideo), tool(.frames, oneVideo), tool(.crop, oneVideo), tool(.redact, oneVideo),
        WheelItem(
          id: "v-subtitles", title: "Subtitles", systemImage: "captions.bubble", command: .extractSubtitles),
      ]
    case .actions:
      return items(for: [])
    }
  }

  /// Segments when every dropped file is audio.
  func audioItems(count: Int) -> [WheelItem] {
    let oneFile: String? = count == 1 ? nil : "One file at a time"
    switch self {
    case .convert:
      return AudioOutput.allCases.map { output in
        WheelItem(
          id: "a-\(output.rawValue)", title: output.displayName, systemImage: nil,
          command: .convertAudio(output), disabledReason: output.unavailableReason)
      }
    case .tools:
      return AudioTool.allCases.map { tool in
        WheelItem(
          id: "a-\(tool.rawValue)", title: tool.title, systemImage: tool.systemImage,
          command: .audioEditor(tool),
          disabledReason: oneFile)
      } + [
        WheelItem(id: "a-visualizer", title: "Visualizer", systemImage: "waveform", command: .visualizer)
      ]
    case .actions:
      return items(for: [])
    }
  }

  /// Segments when every dropped file is a document, PDF, table or presentation.
  func documentItems(for files: [DroppedFile]) -> [WheelItem] {
    let allPDFs = files.allSatisfy { $0.kind == .pdf }
    func convert(_ output: DocumentOutput) -> WheelItem {
      let problem = files.lazy.compactMap { DocumentOps.problem($0.kind, output: output) }.first
      return WheelItem(
        id: "d-\(output.rawValue)", title: output == .epubFixed ? "EPUB Pages" : output.displayName,
        systemImage: nil, command: .convertDocument(output),
        disabledReason: output.unavailableReason ?? problem)
    }
    let merge = WheelItem(
      id: "d-merge", title: "Merge", systemImage: "doc.on.doc", command: .toPDF,
      disabledReason: files.count >= 2 ? nil : "Two or more PDFs")
    switch self {
    case .convert:
      if allPDFs {
        return [
          WheelItem(id: "d-png", title: "PNG", systemImage: nil, command: .pdfToImages(.png)),
          WheelItem(id: "d-jpeg", title: "JPEG", systemImage: nil, command: .pdfToImages(.jpeg)),
          WheelItem(id: "d-tiff", title: "TIFF", systemImage: nil, command: .pdfToTIFF),
          WheelItem(id: "d-cbz", title: "CBZ", systemImage: nil, command: .pdfToCBZ),
        ] + [DocumentOutput.docx, .rtf, .txt, .md, .html, .epub, .epubFixed].map(convert)
      }
      if files.allSatisfy(\.kind.hasPages) {
        // Presentations: PDF, or one image per slide.
        return [convert(.pdf)]
          + [ImageFormat.png, .jpeg].map {
            WheelItem(
              id: "d-\($0.rawValue)", title: $0.displayName, systemImage: nil, command: .pdfToImages($0))
          }
      }
      if files.allSatisfy(\.kind.isSpreadsheet) {
        let problem = files.lazy.compactMap { file -> String? in
          guard case .office(let format) = file.kind else { return nil }
          return SpreadsheetOps.problem(format)
        }.first
        return [
          convert(.pdf),
          WheelItem(
            id: "d-csv", title: "CSV", systemImage: nil, command: .sheetsToCSV, disabledReason: problem),
        ]
      }
      // CSV tables also convert to JSON and vCard.
      return [DocumentOutput.pdf, .docx, .rtf, .txt, .md, .html, .epub, .pages].map(convert)
        + (files.allSatisfy { $0.kind == .office(.csv) } ? dataItems(for: files) : [])
    case .tools:
      return [
        WheelItem(
          id: "d-organize", title: "Organize", systemImage: "square.grid.3x3.square", command: .organizePDF,
          disabledReason: files.count == 1 ? nil : "One PDF at a time"),
        WheelItem(
          id: "d-split", title: "Split", systemImage: "rectangle.split.3x1", command: .splitPDF),
        WheelItem(
          id: "d-compress", title: "Compress", systemImage: "arrow.down.right.and.arrow.up.left",
          command: .compress),
        merge,
      ]
    case .actions:
      return items(for: [DroppedFile]())
    }
  }

  /// Convert segments for JSON, XML, plist, vCard and CSV files: the outputs every file has.
  func dataItems(for files: [DroppedFile]) -> [WheelItem] {
    let outputs = DataFormat.allCases.filter { output in
      files.allSatisfy { $0.kind.dataFormat?.outputs.contains(output) == true }
    }
    return outputs.map {
      WheelItem(id: "j-\($0.rawValue)", title: $0.displayName, systemImage: nil, command: .convertData($0))
    }
  }

  /// Segments for this wheel, enabled or not depending on what's being dropped.
  /// `files` may be empty while dragging, when the kinds aren't known yet.
  func items(for files: [DroppedFile]) -> [WheelItem] {
    let known = !files.isEmpty
    let allImages = known && files.allSatisfy(\.kind.isImage)
    let allPDFs = known && files.allSatisfy { $0.kind == .pdf }
    let imagesOnly: String? = known && !allImages ? "Images only" : nil
    let allVideos = known && files.allSatisfy(\.kind.isVideo)
    if allVideos { return videoItems(count: files.count) }
    if known && files.allSatisfy(\.kind.isAudio) { return audioItems(count: files.count) }
    if known && files.allSatisfy(\.kind.isDocumentLike) && (self == .convert || (self == .tools && allPDFs)) {
      return documentItems(for: files)
    }
    if known && self == .convert && files.allSatisfy({ if case .data = $0.kind { true } else { false } }) {
      return dataItems(for: files)
    }
    if known && files.allSatisfy(\.kind.isSubtitle) && self == .convert {
      return SubtitleFormat.allCases.map {
        WheelItem(
          id: "s-\($0.rawValue)", title: $0.displayName, systemImage: nil, command: .convertSubtitles($0))
      }
    }
    if known && files.allSatisfy({ $0.kind == .archive }) && self != .actions {
      return [
        WheelItem(id: "z-extract", title: "Extract", systemImage: "archivebox", command: .extractArchive)
      ]
    }
    let oneImage: String? = known && !(files.count == 1 && allImages) ? "One image at a time" : nil

    switch self {
    case .convert:
      let formats: [ImageFormat] = [
        .png, .jpeg, .heic, .avif, .tiff, .bmp, .webp, .gif, .ico, .icns, .jpeg2000, .tga, .exr,
      ]
      var items = formats.map { format in
        WheelItem(
          id: format.rawValue, title: format.shortName, systemImage: nil, command: .convert(format),
          disabledReason: !format.isWritable ? "\(format.displayName) encoder missing" : imagesOnly)
      }
      let pdfReason: String? =
        known && !(allImages || (allPDFs && files.count > 1)) ? "Images, or 2+ PDFs" : nil
      items.insert(
        WheelItem(id: "pdf", title: "PDF", systemImage: nil, command: .toPDF, disabledReason: pdfReason),
        at: 1)
      return items
    case .tools:
      let compressReason: String? =
        known && files.contains { !$0.kind.isImage && $0.kind != .pdf } ? "Images and PDFs only" : nil
      let collageReason: String? = known && !(allImages && files.count >= 2) ? "Two or more images" : nil
      return [
        WheelItem(
          id: "compress", title: "Compress", systemImage: "arrow.down.right.and.arrow.up.left",
          command: .compress, disabledReason: compressReason),
        WheelItem(
          id: "metadata", title: "Metadata", systemImage: "tag", command: .metadata,
          disabledReason: imagesOnly
            ?? (files.allSatisfy(Processor.canEditMetadata) ? nil : "Not for this format")),
        WheelItem(
          id: "annotate", title: "Annotate", systemImage: EditorTool.annotate.systemImage,
          command: .edit(.annotate), disabledReason: oneImage),
        WheelItem(
          id: "redact", title: "Redact", systemImage: EditorTool.redact.systemImage, command: .edit(.redact),
          disabledReason: oneImage),
        // Crop works on several images at once (the same crop for each).
        WheelItem(
          id: "crop", title: "Crop", systemImage: EditorTool.crop.systemImage, command: .edit(.crop),
          disabledReason: imagesOnly),
        WheelItem(
          id: "background", title: "Add BG", systemImage: "person.crop.rectangle", command: .background,
          disabledReason: imagesOnly),
        WheelItem(
          id: "frame", title: "Frame", systemImage: "photo.artframe", command: .frame,
          disabledReason: imagesOnly),
        WheelItem(
          id: "collage", title: "Collage", systemImage: "square.grid.2x2", command: .collage,
          disabledReason: collageReason),
        WheelItem(
          id: "qr", title: "QR Code", systemImage: "qrcode.viewfinder", command: .readQR,
          disabledReason: imagesOnly),
        WheelItem(
          id: "resize", title: "Resize", systemImage: "arrow.up.left.and.arrow.down.right", command: .resize,
          disabledReason: imagesOnly),
        WheelItem(
          id: "grayscale", title: "Grayscale", systemImage: "circle.lefthalf.filled", command: .grayscale,
          disabledReason: imagesOnly),
        WheelItem(
          id: "edit", title: "Adjust", systemImage: EditorTool.adjust.systemImage, command: .edit(.adjust),
          disabledReason: oneImage),
      ]
    case .actions:
      return [
        WheelItem(
          id: "airdrop", title: "AirDrop", systemImage: "dot.radiowaves.left.and.right", command: .airDrop),
        WheelItem(id: "share", title: "Share", systemImage: "square.and.arrow.up", command: .share),
        WheelItem(id: "float", title: "Float", systemImage: "paperclip", command: .float),
        WheelItem(
          id: "float-add", title: "Add to Float", systemImage: "paperclip.badge.ellipsis",
          command: .addToFloat,
          disabledReason: FloatManager.openCount > 0 ? nil : "No Float is open"),
        WheelItem(id: "copy", title: "Copy", systemImage: "doc.on.doc", command: .copy),
        WheelItem(id: "move", title: "Move", systemImage: "folder", command: .move),
        WheelItem(id: "copypath", title: "Copy Path", systemImage: "doc.text", command: .copyPath),
        WheelItem(id: "zip", title: "Zip", systemImage: "doc.zipper", command: .zip),
        WheelItem(id: "terminal", title: "Terminal", systemImage: "terminal", command: .terminal),
      ]
    }
  }
}
