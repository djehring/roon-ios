import Foundation

enum ZoneTrackSelection {
  /// Whether this zone tick carried a now-playing object.
  ///
  /// Radio ticks often include one that used to fail to decode. Treating that
  /// the same as a missing object kept last night's album on screen.
  enum Presence: Equatable {
    /// No now-playing key. A brief gap during a track change, so keep showing
    /// what we already have if the zone is still playing.
    case omitted
    /// The key was there. Use the incoming track, or nothing — not yesterday.
    case available
  }

  struct Choice: Equatable {
    var track: Track?
    var clearPin: Bool
  }

  static func choose(
    incoming: Track?,
    previous: Track?,
    playback: PlaybackState,
    pinned: Track?,
    replaced: Track?,
    presence: Presence
  ) -> Choice {
    if let pinned {
      if let incoming {
        if sameSong(incoming, pinned) {
          return Choice(track: incoming, clearPin: true)
        }
        if let replaced, sameSong(incoming, replaced) {
          return Choice(track: pinned, clearPin: false)
        }
        return Choice(track: incoming, clearPin: true)
      }
      return Choice(track: pinned, clearPin: false)
    }
    if let incoming {
      return Choice(track: incoming, clearPin: false)
    }
    if playback == .stopped {
      return Choice(track: nil, clearPin: false)
    }
    if presence == .omitted {
      return Choice(track: previous, clearPin: false)
    }
    return Choice(track: nil, clearPin: false)
  }

  static func sameSong(_ a: Track, _ b: Track) -> Bool {
    a.title == b.title && a.artist == b.artist
  }
}
