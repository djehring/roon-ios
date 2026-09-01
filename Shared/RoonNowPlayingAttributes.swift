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
  }

  var zoneId: String
}
#endif

