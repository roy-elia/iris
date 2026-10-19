#if DEBUG
  import Foundation

  /// Debug-only sample files that macOS can read but not write, for the unit tests and the
  /// feature self-test.
  public enum SampleFiles {
    /// A camera-RAW DNG: an uncompressed 16-bit RGGB Bayer mosaic, red on the left half and
    /// blue on the right. ImageIO's RAW decoder ignores DNGs much smaller than this.
    public static func writeDNG(to url: URL, width: Int = 512, height: Int = 384) throws {
      struct Entry {
        let tag: UInt16
        let type: UInt16
        let count: UInt32
        let data: [UInt8]
      }
      func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
      func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) } }
      func shorts(_ tag: UInt16, _ v: [UInt16]) -> Entry {
        Entry(tag: tag, type: 3, count: UInt32(v.count), data: v.flatMap(le16))
      }
      func longs(_ tag: UInt16, _ v: [UInt32]) -> Entry {
        Entry(tag: tag, type: 4, count: UInt32(v.count), data: v.flatMap(le32))
      }
      func bytes(_ tag: UInt16, _ v: [UInt8]) -> Entry {
        Entry(tag: tag, type: 1, count: UInt32(v.count), data: v)
      }
      func ascii(_ tag: UInt16, _ s: String) -> Entry {
        let b = Array(s.utf8) + [0]
        return Entry(tag: tag, type: 2, count: UInt32(b.count), data: b)
      }
      /// RATIONAL (5) or SRATIONAL (10) values with a denominator of 10,000.
      func rationals(_ tag: UInt16, _ v: [Double], signed: Bool) -> Entry {
        let data = v.flatMap { le32(UInt32(bitPattern: Int32(($0 * 10000).rounded()))) + le32(10000) }
        return Entry(tag: tag, type: signed ? 10 : 5, count: UInt32(v.count), data: data)
      }

      var pixels: [UInt8] = []
      pixels.reserveCapacity(width * height * 2)
      for y in 0..<height {
        for x in 0..<width {
          let rgb: [UInt16] = x < width / 2 ? [40000, 8000, 4000] : [4000, 8000, 40000]
          // RGGB: even rows are R G, odd rows G B.
          pixels += le16(rgb[y % 2 == 0 ? x % 2 : 1 + x % 2])
        }
      }
      let stripOffsetIndex = 8
      var entries = [
        longs(254, [0]), longs(256, [UInt32(width)]), longs(257, [UInt32(height)]), shorts(258, [16]),
        shorts(259, [1]), shorts(262, [32803]), ascii(271, "File Drop Utility"), ascii(272, "Sample"),
        longs(273, [0]), shorts(274, [1]), shorts(277, [1]), longs(278, [UInt32(height)]),
        longs(279, [UInt32(pixels.count)]), shorts(284, [1]),
        shorts(33421, [2, 2]), bytes(33422, [0, 1, 1, 2]),
        bytes(50706, [1, 4, 0, 0]), bytes(50707, [1, 1, 0, 0]), ascii(50708, "File Drop Utility Sample"),
        longs(50717, [65535]),
        // XYZ → camera: the camera here is linear sRGB.
        rationals(
          50721, [3.2406, -1.5372, -0.4986, -0.9689, 1.8758, 0.0415, 0.0557, -0.2040, 1.0570], signed: true),
        rationals(50728, [1, 1, 1], signed: false), shorts(50778, [21]),
      ]
      // Values over 4 bytes go after the IFD, word-aligned; the pixels come last.
      let ifdEnd = 8 + 2 + entries.count * 12 + 4
      var extra: [UInt8] = []
      var offsets: [Int?] = []
      for e in entries {
        guard e.data.count > 4 else {
          offsets.append(nil)
          continue
        }
        offsets.append(ifdEnd + extra.count)
        extra += e.data
        if extra.count % 2 == 1 { extra.append(0) }
      }
      entries[stripOffsetIndex] = longs(273, [UInt32(ifdEnd + extra.count)])
      var out: [UInt8] = [0x49, 0x49, 42, 0] + le32(8) + le16(UInt16(entries.count))
      for (e, offset) in zip(entries, offsets) {
        out += le16(e.tag) + le16(e.type) + le32(e.count)
        out += offset.map { le32(UInt32($0)) } ?? (e.data + [UInt8](repeating: 0, count: 4 - e.data.count))
      }
      out += le32(0) + extra + pixels
      try Data(out).write(to: url)
    }
  }
#endif
