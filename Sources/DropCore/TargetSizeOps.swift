import CoreGraphics
import Foundation
import ImageIO

/// Compresses an image to fit a byte budget: the highest quality that fits, and smaller
/// dimensions only when even the lowest quality is too big.
public enum TargetSizeOps {
  public static let minimumTarget: Int64 = 1024
  static let lowestQuality = 0.05
  static let highestQuality = 0.95
  /// Quality steps tried by binary search; 7 gets within 1% of the best quality.
  static let searchSteps = 7
  static let downscaleStep = 0.8
  static let smallestSide = 32

  /// The format a target-size copy is written in: lossy sources keep their format;
  /// lossless ones become JPEG, or WebP (else HEIC) when they have transparency.
  public static func outputFormat(for source: URL) -> ImageFormat {
    let format = ImageFormat(fileExtension: source.pathExtension) ?? .png
    if format.usesQuality && format.isWritable { return format }
    let readable = (try? ImageInput.readableURL(for: source)) ?? source
    let alpha = (try? ImageOps.loadOriented(readable)).map(ImageOps.hasAlpha) ?? false
    guard alpha else { return .jpeg }
    return ImageFormat.webp.isWritable ? .webp : .heic
  }

  /// Checks a target against the source. Returns a message if it can't work.
  public static func validate(target: Int64, sourceSize: Int64, name: String) -> String? {
    if target < minimumTarget { return "Enter a target size of at least 1 KB." }
    if sourceSize <= minimumTarget { return "\(name) is already smaller than 1 KB." }
    if target >= sourceSize { return "Target size cannot exceed the original file size (\(name))." }
    return nil
  }

  /// Writes `source` to `destination` as `format`, no larger than `target` bytes.
  public static func compress(
    _ source: URL, target: Int64, format: ImageFormat, destination: URL
  ) async throws {
    let name = source.lastPathComponent
    let size = CompressOps.fileSize(source)
    if let message = validate(target: target, sourceSize: size, name: name) {
      throw DropError.wrongInput(message)
    }
    var image = try ImageOps.loadOriented(ImageInput.readableURL(for: source))
    while true {
      if let data = try await bestEncoding(of: image, format: format, target: target) {
        try data.write(to: destination)
        return
      }
      // Even the lowest quality is too big: shrink and try again.
      let w = Int(Double(image.width) * downscaleStep)
      let h = Int(Double(image.height) * downscaleStep)
      guard min(w, h) >= smallestSide else { throw DropError.targetTooSmall(name) }
      image = try scale(image, width: w, height: h)
    }
  }

  /// The highest-quality encoding that fits, or nil if none does at this size.
  static func bestEncoding(of image: CGImage, format: ImageFormat, target: Int64) async throws -> Data? {
    guard let smallest = try await encode(image, format: format, quality: lowestQuality),
      smallest.count <= target
    else { return nil }
    var best = smallest
    var low = lowestQuality
    var high = highestQuality
    for _ in 0..<searchSteps {
      let mid = (low + high) / 2
      guard let data = try await encode(image, format: format, quality: mid) else { break }
      if data.count <= target {
        best = data
        low = mid
      } else {
        high = mid
      }
    }
    return best
  }

  static func encode(_ image: CGImage, format: ImageFormat, quality: Double) async throws -> Data? {
    if format == .webp {
      let staged = FileManager.default.temporaryDirectory
        .appendingPathComponent("fdu-ts-\(UUID().uuidString)").appendingPathExtension("png")
      let out = staged.deletingPathExtension().appendingPathExtension("webp")
      defer {
        try? FileManager.default.removeItem(at: staged)
        try? FileManager.default.removeItem(at: out)
      }
      try ImageOps.write(image, as: .png, quality: 1, to: staged)
      try await ImageConvert.runCwebp(
        ["-quiet", "-q", String(Int((quality * 100).rounded()))], input: staged, output: out)
      return try Data(contentsOf: out)
    }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, format.typeIdentifier as CFString, 1, nil) else {
      return nil
    }
    let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    CGImageDestinationAddImage(dest, image, options)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
  }

  static func scale(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
    let ctx = try EditOps.context(width: width, height: height, like: image)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return try EditOps.make(ctx)
  }
}
