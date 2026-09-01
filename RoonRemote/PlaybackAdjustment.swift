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

enum TimeCode {
  /// Parses "M:SS", "MM:SS", or "H:MM:SS" into seconds.
  static func seconds(from value: String?) -> Double? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let parts = trimmed.split(separator: ":").compactMap { Double($0) }
    guard !parts.isEmpty, parts.count <= 3 else { return nil }
    return parts.reduce(0) { $0 * 60 + $1 }
  }

  static func string(from seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }

  static func durationSeconds(length: String?, seekPosition: String?, seekPercentage: Double?) -> Double? {
    if let lengthSeconds = seconds(from: length), lengthSeconds > 0 {
      return lengthSeconds
    }
    guard let position = seconds(from: seekPosition),
          let percentage = seekPercentage,
          percentage > 0
    else { return nil }
    return position / (percentage / 100)
  }

  /// Time left on the current track. Prefer seek position over percentage.
  static func remaining(
    duration: Double?,
    seekPosition: String?,
    seekPercentage: Double?
  ) -> String? {
    guard let duration, duration > 0 else { return nil }
    if let position = seconds(from: seekPosition) {
      return string(from: max(0, duration - position))
    }
    if let percentage = seekPercentage {
      return string(from: max(0, duration * (1 - percentage / 100)))
    }
    return string(from: duration)
  }
}
