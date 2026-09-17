#if DEBUG
import Foundation

extension MockStore {
  /// A developer-supplied manifest exercises the real renderer without shipping
  /// any historical programme or fixed date in the app.
  func applyCinemaPreviewIfRequested() {
    guard let path = ProcessInfo.processInfo.environment["ROON_CINEMA_PREVIEW_MANIFEST"],
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let capsule = try? JSONDecoder().decode(TimeCapsule.self, from: data),
          let first = capsule.request.tracks.first, !zones.isEmpty else { return }
    zones[0].track = Track(id: "cinema-preview", title: first.track, artist: first.artist,
      album: first.album, position: "0:00", remaining: "", progress: 0)
    cinema.capsules = [capsule]
    cinema.presented = capsule
  }
}
#endif
