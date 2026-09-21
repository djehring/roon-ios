#if os(iOS)
import Foundation
import ActivityKit

struct RoonNowPlayingAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var zoneName: String
    var title: String
    var artist: String
    var isPlaying: Bool
    var artworkJPEG: Data? = nil
    // Unlike attributes, content changes when the user selects another room.
    // Optional so activities created by an older app still decode after update.
    var zoneID: String? = nil

    /// Recheck the entire payload, including cached art, on every track change.
    /// A longer title on the same album can otherwise exceed ActivityKit's limit.
    func fittingBudget(maxBytes: Int = 3200) -> Self {
      var result = self
      func fits(_ value: Self) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return data.count <= maxBytes
      }
      if fits(result) { return result }
      result.artworkJPEG = nil
      while !fits(result) {
        if result.title.count > 1 {
          result.title = String(result.title.prefix(result.title.count / 2))
        } else if result.artist.count > 1 {
          result.artist = String(result.artist.prefix(result.artist.count / 2))
        } else if result.zoneName.count > 1 {
          result.zoneName = String(result.zoneName.prefix(result.zoneName.count / 2))
        } else {
          break
        }
      }
      return result
    }
  }

  var zoneId: String
}
#endif
