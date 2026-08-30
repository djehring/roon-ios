import Foundation

enum PlayRequest {
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
