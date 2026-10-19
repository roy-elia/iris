import CoreGraphics
import Foundation
import PDFKit

/// Makes files smaller. Keeps the result only if it is actually smaller.
public enum CompressOps {
  public static let defaultQuality = 0.6

  /// Output format for compressing an image: lossy formats stay as they are; lossless ones
  /// become JPEG, or HEIC when the image has transparency.
  public static func targetFormat(for source: ImageFormat, hasAlpha: Bool) -> ImageFormat {
    if source.usesQuality { return source }
    return hasAlpha ? .heic : .jpeg
  }

  /// Compresses an image or PDF to `destination` (whose extension the caller picks with
  /// `outputExtension`). Throws `notSmaller` and leaves nothing behind if it didn't help.
  public static func compress(_ source: URL, kind: FileKind, quality: Double, destination: URL) throws {
    switch kind {
    case .image:
      let image = try ImageOps.loadOriented(source)
      let format = targetFormat(
        for: ImageFormat(fileExtension: source.pathExtension) ?? .png, hasAlpha: ImageOps.hasAlpha(image))
      try ImageOps.write(image, as: format, quality: quality, to: destination)
    case .pdf:
      guard let doc = PDFDocument(url: source) else { throw DropError.readFailed(source.lastPathComponent) }
      if doc.isLocked { throw DropError.wrongInput("\(source.lastPathComponent) is password-protected.") }
      let options: [PDFDocumentWriteOption: Any] = [
        .saveImagesAsJPEGOption: true,
        .optimizeImagesForScreenOption: true,
      ]
      guard doc.write(to: destination, withOptions: options) else {
        throw DropError.writeFailed(destination.lastPathComponent)
      }
    case .video, .audio, .document, .office, .subtitle, .archive, .unsupported:
      throw DropError.unsupportedFile(source.lastPathComponent)
    }

    if fileSize(destination) >= fileSize(source) {
      try? FileManager.default.removeItem(at: destination)
      throw DropError.notSmaller(source.lastPathComponent)
    }
  }

  /// The extension a compressed copy of `source` will have.
  public static func outputExtension(for source: URL, kind: FileKind) -> String {
    switch kind {
    case .pdf: return "pdf"
    case .image(let format):
      // Alpha is only known after decoding; HEIC is chosen for lossless sources with alpha.
      if format.usesQuality { return format.fileExtension }
      let alpha = (try? ImageOps.loadOriented(source)).map(ImageOps.hasAlpha) ?? false
      return targetFormat(for: format, hasAlpha: alpha).fileExtension
    case .video, .audio, .document, .office, .subtitle, .archive, .unsupported: return source.pathExtension
    }
  }

  static func fileSize(_ url: URL) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
  }
}
