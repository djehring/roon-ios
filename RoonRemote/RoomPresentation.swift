import Foundation

enum RoomPresentation {
  static func symbol(for name: String) -> String {
    let room = name.lowercased()
    let symbols: [(words: [String], symbol: String)] = [
      (["kitchen"], "refrigerator.fill"),
      (["dining"], "fork.knife"),
      (["bedroom", "bed room"], "bed.double.fill"),
      (["office", "study"], "desktopcomputer"),
      (["gym", "fitness"], "dumbbell.fill"),
      (["bathroom", "bath room", "shower"], "shower.fill"),
      (["conservatory", "sunroom", "sun room"], "leaf.fill"),
      (["garden", "patio", "terrace"], "tree.fill"),
      (["garage"], "car.fill"),
      (["snug"], "fireplace.fill"),
      (["living", "sitting", "lounge", "family room"], "sofa.fill"),
    ]
    return symbols.first { candidate in
      candidate.words.contains { room.contains($0) }
    }?.symbol ?? "hifispeaker.fill"
  }

  static func status(for zone: Zone) -> String {
    guard let track = zone.track else {
      switch zone.state {
      case .loading: return "Loading…"
      case .paused: return "Paused"
      case .playing: return "Playing"
      case .stopped: return "Nothing playing"
      }
    }
    switch zone.state {
    case .playing: return "Playing · \(track.title)"
    case .paused: return "Paused · \(track.title)"
    case .loading: return "Loading · \(track.title)"
    case .stopped: return track.title
    }
  }

  static func stateSymbol(for state: PlaybackState) -> String? {
    switch state {
    case .playing: "waveform"
    case .paused: "pause.fill"
    case .loading: "ellipsis"
    case .stopped: nil
    }
  }
}

enum RoomPickerLayout {
  static let width: CGFloat = 420
  static let rowHeight: CGFloat = 68
  static let maximumHeight: CGFloat = 620

  static func height(roomCount: Int) -> CGFloat {
    min(maximumHeight, 70 + CGFloat(max(1, roomCount)) * rowHeight)
  }
}
