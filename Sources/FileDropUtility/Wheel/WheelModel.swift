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
  case edit(EditorTool)
  case airDrop
  case float
  case copy
  case copyPath
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
  /// Segments for this wheel, enabled or not depending on what's being dropped.
  /// `files` may be empty while dragging, when the kinds aren't known yet.
  func items(for files: [DroppedFile]) -> [WheelItem] {
    let known = !files.isEmpty
    let allImages = known && files.allSatisfy(\.kind.isImage)
    let allPDFs = known && files.allSatisfy { $0.kind == .pdf }
    let imagesOnly: String? = known && !allImages ? "Images only" : nil
    let oneImage: String? = known && !(files.count == 1 && allImages) ? "One image at a time" : nil

    switch self {
    case .convert:
      let formats: [ImageFormat] = [.png, .jpeg, .heic, .avif, .tiff, .bmp, .webp, .gif]
      var items = formats.map { format in
        WheelItem(
          id: format.rawValue, title: format.displayName, systemImage: nil, command: .convert(format),
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
        known && files.contains { $0.kind == .unsupported } ? "Images and PDFs only" : nil
      let collageReason: String? = known && !(allImages && files.count >= 2) ? "Two or more images" : nil
      return [
        WheelItem(
          id: "compress", title: "Compress", systemImage: "arrow.down.right.and.arrow.up.left",
          command: .compress, disabledReason: compressReason),
        WheelItem(
          id: "metadata", title: "Metadata", systemImage: "tag", command: .metadata,
          disabledReason: imagesOnly),
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
          id: "edit", title: "Adjust", systemImage: EditorTool.adjust.systemImage, command: .edit(.adjust),
          disabledReason: oneImage),
      ]
    case .actions:
      return [
        WheelItem(
          id: "airdrop", title: "AirDrop", systemImage: "dot.radiowaves.left.and.right", command: .airDrop),
        WheelItem(id: "float", title: "Float", systemImage: "pin", command: .float),
        WheelItem(id: "copy", title: "Copy", systemImage: "doc.on.doc", command: .copy),
        WheelItem(id: "move", title: "Move", systemImage: "folder", command: .move),
        WheelItem(id: "copypath", title: "Copy Path", systemImage: "doc.text", command: .copyPath),
        WheelItem(id: "terminal", title: "Terminal", systemImage: "terminal", command: .terminal),
      ]
    }
  }
}
