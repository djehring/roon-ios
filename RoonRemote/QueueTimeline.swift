import Foundation

enum QueueTimeline {
  /// The tracks still to come, excluding the one already playing.
  ///
  /// Roon's queue payload leads with the current track, so treating the first
  /// entry as "up next" named the track you were already listening to. Neither
  /// the zone payload nor the queue entries carry a shared identifier, so the
  /// match is on content, and a queue that already omits the current track is
  /// returned untouched rather than losing its first entry.
  static func upcoming(queue: [QueueItem], current: Track?) -> [QueueItem] {
    guard let current, let first = queue.first, matches(first, current) else { return queue }
    return Array(queue.dropFirst())
  }

  static func upNext(queue: [QueueItem], current: Track?) -> QueueItem? {
    upcoming(queue: queue, current: current).first
  }

  /// Whether a live queue event has taken over from the AI/local replacement.
  ///
  /// Play-tracks is slow and the first Core events still describe the previous
  /// playlist. Accept only once the incoming list is the replacement, not the
  /// leftover room queue.
  static func hasAdoptedReplacement(
    incoming: [QueueItem],
    expected: [QueueItem],
    current: Track?
  ) -> Bool {
    let expectedTitles = expected.map { RoonVoiceMatch.normalize($0.title) }.filter { !$0.isEmpty }
    guard let firstExpected = expectedTitles.first else { return true }
    let incomingTitles = incoming.map { RoonVoiceMatch.normalize($0.title) }
    let rest = Array(expectedTitles.dropFirst())
    if incomingTitles.first == firstExpected {
      return titles(upcoming(queue: incoming, current: current), match: rest)
    }
    if let current, RoonVoiceMatch.normalize(current.title) == firstExpected {
      return titles(upcoming(queue: incoming, current: current), match: rest)
    }
    return false
  }

  private static func titles(_ items: [QueueItem], match expected: [String]) -> Bool {
    let incoming = items.map { RoonVoiceMatch.normalize($0.title) }
    return incoming == expected
      || incoming.starts(with: expected)
      || expected.starts(with: incoming)
  }

  private static func matches(_ item: QueueItem, _ track: Track) -> Bool {
    let itemTitle = RoonVoiceMatch.normalize(item.title)
    guard !itemTitle.isEmpty, itemTitle == RoonVoiceMatch.normalize(track.title) else {
      return false
    }
    // Artist only decides it when both sides name one; the queue payload leaves
    // it off often enough that requiring it would miss the match.
    let itemArtist = RoonVoiceMatch.normalize(item.artist)
    let trackArtist = RoonVoiceMatch.normalize(track.artist)
    guard !itemArtist.isEmpty, !trackArtist.isEmpty else { return true }
    return itemArtist == trackArtist
  }
}
