import Foundation

/// Maps a pointer position to a segment of the radial wheel.
public enum WheelHitTest {
  /// The segment index under a point given relative to the wheel's centre in y-down
  /// coordinates, or nil over the centre hole or outside the wheel. Segment 0 is centred
  /// at the top and the rest follow clockwise. A little slack past the rim still counts.
  public static func segment(
    dx: Double, dy: Double, outerRadius: Double, count: Int, innerRatio: Double = 0.42,
    rimSlack: Double = 1.12
  ) -> Int? {
    guard count > 0, outerRadius > 0 else { return nil }
    let distance = hypot(dx, dy)
    guard distance >= outerRadius * innerRatio, distance <= outerRadius * rimSlack else { return nil }
    let step = 360.0 / Double(count)
    let degrees = atan2(dy, dx) * 180 / .pi
    var fromFirst = (degrees + 90 + step / 2).truncatingRemainder(dividingBy: 360)
    if fromFirst < 0 { fromFirst += 360 }
    return min(Int(fromFirst / step), count - 1)
  }
}
