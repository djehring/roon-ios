import Foundation

enum LibraryIndex {
  static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#")

  /// The order the index bar assumes. It lives here so the two cannot drift:
  /// `#` is the last key, so titles starting with a digit or symbol have to
  /// sort after Z, or tapping the bottom of the bar would jump to the top.
  ///
  /// Natural ordering, so "Bathtime 2a" comes before "Bathtime 10" rather than
  /// after it. Ties break on id, because a library can hold two playlists with
  /// the same name and the order should still be stable between loads.
  static func sorted(_ items: [BrowseNode]) -> [BrowseNode] {
    items.sorted { lhs, rhs in
      let leading = (group(lhs.title), group(rhs.title))
      if leading.0 != leading.1 { return leading.0 < leading.1 }
      switch lhs.title.localizedStandardCompare(rhs.title) {
      case .orderedAscending: return true
      case .orderedDescending: return false
      case .orderedSame: return lhs.id < rhs.id
      }
    }
  }

  private static func group(_ title: String) -> Int {
    guard let first = title.first else { return 1 }
    return first.isLetter ? 0 : 1
  }

  /// The core returns playlists in its own order, which reads as unsorted and
  /// leaves the A–Z index bar jumping to arbitrary rows.
  ///
  /// Only the list of playlists: tracks inside one keep the playlist's order.
  /// A search prompt stays at the top so it is not sorted into S.
  static func alphabetizedPlaylists(
    _ page: BrowsePage,
    hierarchy: String,
    itemKey: String?
  ) -> BrowsePage {
    let namedPlaylists = page.title.compare("Playlists", options: .caseInsensitive) == .orderedSame
    let playlistsRoot = hierarchy == "playlists" && itemKey == nil
    guard namedPlaylists || playlistsRoot else { return page }
    var sorted = page
    let prompts = page.items.filter(\.isPrompt)
    let rest = page.items.filter { !$0.isPrompt }
    sorted.items = prompts + Self.sorted(rest)
    return sorted
  }

  static func jumpTarget(for letter: Character, in items: [BrowseNode]) -> BrowseNode.ID? {
    if letter == "#" {
      return items.first { item in
        guard let first = item.title.uppercased().first else { return false }
        return !first.isLetter
      }?.id
    }
    return items.first {
      $0.title.uppercased().hasPrefix(String(letter))
    }?.id
  }
}
