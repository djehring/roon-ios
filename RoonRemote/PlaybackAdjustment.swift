import Foundation

enum PlaybackAdjustment {
  static func volume(
    current: Double,
    minimum: Double,
    maximum: Double,
    delta: Double
  ) -> Double {
    min(maximum, max(minimum, current + delta))
  }
}
