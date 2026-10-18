import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// Removes or replaces an image's background with Vision's subject lifting.
public enum BackgroundOps {
  private static let ciContext = CIContext()

  /// Writes the subject of `source` over `fill`. Transparent output is always PNG.
  public static func replaceBackground(_ source: URL, fill: BackgroundFill, destination: URL) throws {
    let image = try ImageOps.loadOriented(source)
    let subject = try liftSubject(image, name: source.lastPathComponent)
    let result = try composite(subject: subject, over: fill)
    try ImageOps.write(result, as: outputFormat(for: source, fill: fill), quality: 0.95, to: destination)
  }

  public static func outputFormat(for source: URL, fill: BackgroundFill) -> ImageFormat {
    if case .transparent = fill { return .png }
    return EditOps.outputFormat(for: source)
  }

  /// The subject on a transparent background, full size.
  static func liftSubject(_ image: CGImage, name: String) throws -> CGImage {
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    do {
      try handler.perform([request])
    } catch {
      throw DropError.noSubject(name)
    }
    guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
      throw DropError.noSubject(name)
    }
    let buffer: CVPixelBuffer
    do {
      buffer = try observation.generateMaskedImage(
        ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
    } catch {
      throw DropError.noSubject(name)
    }
    let ci = CIImage(cvPixelBuffer: buffer)
    guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { throw DropError.noSubject(name) }
    return cg
  }

  /// Draws `subject` (with transparency) over a solid colour, or leaves it transparent.
  static func composite(subject: CGImage, over fill: BackgroundFill) throws -> CGImage {
    let ctx = try EditOps.context(width: subject.width, height: subject.height, like: subject)
    let rect = CGRect(x: 0, y: 0, width: subject.width, height: subject.height)
    if case .color(let c) = fill {
      ctx.setFillColor(c.cgColor)
      ctx.fill(rect)
    }
    ctx.draw(subject, in: rect)
    return try EditOps.make(ctx)
  }
}
