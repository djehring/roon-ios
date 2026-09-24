import Foundation

enum ArtistCredits {
  /// Keep each Roon-linked credit intact, including band names containing
  /// commas, ampersands or slashes. Only separators outside links divide artists.
  static func names(in credits: String) -> [String] {
    var names: [String] = []
    var remainder = credits
    func appendPlain(_ text: String) {
      let separators = CharacterSet(charactersIn: ",/&; ")
      let text = text.trimmingCharacters(in: separators.union(.whitespacesAndNewlines))
      names += text.components(separatedBy: " / ")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
    while let start = remainder.range(of: "[["),
          let end = remainder.range(of: "]]", range: start.upperBound..<remainder.endIndex) {
      appendPlain(String(remainder[..<start.lowerBound]))
      let name = RoonDisplayText.format(String(remainder[start.lowerBound..<end.upperBound]))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !name.isEmpty { names.append(name) }
      remainder = String(remainder[end.upperBound...])
    }
    appendPlain(remainder)
    var seen: Set<String> = []
    return names.filter { seen.insert($0).inserted }
  }

  static func searchQuery(_ name: String) -> String {
    RoonDisplayText.format(name)
      .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
  }
}

struct NowPlayingAlbum: Hashable {
  var title: String
  var imageKey: String?

  init(track: Track) {
    title = track.album
    imageKey = track.imageKey
  }

  /// The transport credit can be a composer. Resolve the performers from the
  /// matching album's linked credits, requiring its cover to avoid substituting
  /// another performance of the same classical work.
  @MainActor
  func artistNames(using browse: (CinemaMusicPath) async throws -> CinemaMusicPage) async throws -> [String]? {
    guard let imageKey, !imageKey.isEmpty, !title.isEmpty else { return nil }
    let fullQuery = ArtistCredits.searchQuery(title)
    // Roon can omit the exact album for a long title with catalogue numbers.
    // Retry a shorter query, still requiring the same album title and artwork.
    let shortQuery = fullQuery.components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }.prefix(3).joined(separator: " ")
    let queries = fullQuery == shortQuery ? [fullQuery] : [fullQuery, shortQuery]
    for query in queries {
      try Task.checkCancellation()
      let root = try await browse(CinemaMusicPath(hierarchy: "search", query: query))
      var items = root.items
      if let albums = items.first(where: { $0.title == "Albums" && $0.kind == "list" }) {
        let page = try await browse(albums.path)
        items += page.items
      }
      if let album = items.first(where: {
        $0.imageKey == imageKey && RoonDisplayText.format($0.title)
          .compare(RoonDisplayText.format(title), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
      }), let credits = album.subtitle {
        let names = ArtistCredits.names(in: credits)
        if !names.isEmpty, !names.contains(where: { $0.localizedCaseInsensitiveCompare("Various Artists") == .orderedSame }) {
          return names
        }
      }
    }
    return nil
  }
}
