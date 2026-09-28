import Foundation

enum PlayRequest {
  /// Only remove a room suffix when it names a real room. Prepositions in
  /// requests such as "jazz in the 1960s" and "Life on Mars" are music content.
  static func parse(_ raw: String, roomNames: [String]) -> (what: String, room: String?) {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    for room in roomNames.sorted(by: { $0.count > $1.count }) where !room.isEmpty {
      for separator in [" in the ", " in ", " on the ", " on "] {
        let suffix = separator + room
        if let range = text.range(of: suffix, options: [.anchored, .backwards, .caseInsensitive]),
           range.lowerBound != text.startIndex {
          return (String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), room)
        }
      }
    }
    return (text, nil)
  }

  static func parse(_ raw: String) -> (what: String, room: String?) {
    let separators = [" in the ", " in ", " on the ", " on "]
    for separator in separators {
      if let range = raw.range(of: separator, options: [.backwards, .caseInsensitive]) {
        let what = raw[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let room = raw[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !what.isEmpty && !room.isEmpty {
          return (what, room)
        }
      }
    }
    return (raw.trimmingCharacters(in: .whitespacesAndNewlines), nil)
  }

  static func phrase(
    mediaName: String?,
    artist: String?,
    album: String?,
    itemTitle: String?
  ) -> String {
    if let mediaName, !mediaName.isEmpty { return mediaName }
    if let itemTitle, !itemTitle.isEmpty {
      if let artist, !artist.isEmpty {
        return "\(itemTitle) \(artist)"
      }
      return itemTitle
    }
    if let album, !album.isEmpty { return album }
    if let artist, !artist.isEmpty { return artist }
    return ""
  }
}
