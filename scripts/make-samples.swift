// Creates sample files for checking the app by hand.
// Usage: swift scripts/make-samples.swift <folder>
import CoreGraphics
import Foundation
import ImageIO

let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "samples")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func image(_ width: Int, _ height: Int, red: CGFloat) -> CGImage {
  let ctx = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.setFillColor(red: red, green: 0.5, blue: 0.2, alpha: 1)
  ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
  return ctx.makeImage()!
}

func write(_ name: String, type: String, metadata: [CFString: Any] = [:], red: CGFloat) {
  let url = folder.appendingPathComponent(name)
  let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, image(640, 400, red: red), metadata as CFDictionary)
  CGImageDestinationFinalize(dest)
}

write("beach.png", type: "public.png", red: 0.9)
write(
  "trip.jpg", type: "public.jpeg",
  metadata: [
    kCGImagePropertyGPSDictionary: [
      kCGImagePropertyGPSLatitude: 45.5, kCGImagePropertyGPSLatitudeRef: "N",
      kCGImagePropertyGPSLongitude: 73.6, kCGImagePropertyGPSLongitudeRef: "W",
    ],
    kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "SampleCam"],
  ], red: 0.3)

for (name, pages) in [("part1.pdf", 2), ("part2.pdf", 3)] {
  var box = CGRect(x: 0, y: 0, width: 300, height: 200)
  let ctx = CGContext(folder.appendingPathComponent(name) as CFURL, mediaBox: &box, nil)!
  for _ in 0..<pages {
    ctx.beginPDFPage(nil)
    ctx.endPDFPage()
  }
  ctx.closePDF()
}
try Data("hello".utf8).write(to: folder.appendingPathComponent("notes.txt"))
print("Samples written to \(folder.path)")
