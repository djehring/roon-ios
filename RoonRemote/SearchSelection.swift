import Foundation

enum SearchSelection {
  /// Keeps a visible result selected as AI results are corrected or reordered,
  /// and moves to the first result only when the current one disappears.
  static func resolved<ID: Hashable>(current: ID?, available: [ID]) -> ID? {
    if let current, available.contains(current) {
      return current
    }
    return available.first
  }
}

enum AISearchPlayback {
  /// Attach play-tracks failures to the rows they belong to.
  ///
  /// The bridge may change the album after a GPT correction, so matching
  /// on album left a found row clean and only a banner saying some
  /// tracks were missing.
  static func applyUnfound(
    _ unfound: [SuggestedTrackPayload],
    to results: inout [SuggestedTrack]
  ) -> String? {
    guard !unfound.isEmpty else { return nil }
    var marked = 0
    for index in results.indices {
      guard let match = unfound.first(where: { sameSong($0, results[index]) }) else { continue }
      results[index].error = match.error ?? "Not found in the library"
      marked += 1
    }
    if marked == 0 {
      return unfound.first?.error ?? "Some tracks were not found in the library."
    }
    if marked == 1, results.count == 1 {
      return results[0].error
    }
    return "Some tracks were not found in the library."
  }

  static func allFailed(playable: [SuggestedTrack], unfound: [SuggestedTrackPayload]) -> Bool {
    !playable.isEmpty && playable.allSatisfy { track in
      unfound.contains { sameSong($0, track) }
    }
  }

  static func sameSong(_ payload: SuggestedTrackPayload, _ result: SuggestedTrack) -> Bool {
    RoonVoiceMatch.titlesMatch(payload.track, result.title)
      && artistsAlign(payload.artist, result.artist)
  }

  /// One title hit is enough. Artist is only a tie-break — Roon often
  /// subtitles the album ("The Muppet Show…") instead of "The Muppets".
  static func preferredHit(
    title: String,
    artist: String,
    in items: [BrowseNode]
  ) -> BrowseNode? {
    let titled = items.filter {
      $0.itemKey != nil && RoonVoiceMatch.titlesMatch($0.title, title)
    }
    guard !titled.isEmpty else { return nil }
    if titled.count == 1 { return titled[0] }
    return titled.first { artistsAlign(artist, $0.subtitle) } ?? titled[0]
  }

  static func artistsAlign(_ requested: String, _ listed: String?) -> Bool {
    let artist = RoonVoiceMatch.normalize(requested)
    guard !artist.isEmpty else { return true }
    guard let listed, !listed.isEmpty else { return true }
    let other = RoonVoiceMatch.normalize(listed)
    if other.contains(artist) || artist.contains(other) { return true }
    let ignored: Set<String> = ["the", "a", "and", "of"]
    let artistTokens = Set(
      artist.split(separator: " ").map(String.init).filter { !ignored.contains($0) && $0.count > 2 }
    )
    let listedTokens = Set(
      other.split(separator: " ").map(String.init).filter { !ignored.contains($0) }
    )
    if !artistTokens.isEmpty && !artistTokens.isDisjoint(with: listedTokens) {
      return true
    }
    return artistTokens.contains { token in
      listedTokens.contains { listed in
        token.hasPrefix(listed) || listed.hasPrefix(token)
      }
    }
  }
}
