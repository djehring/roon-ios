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
