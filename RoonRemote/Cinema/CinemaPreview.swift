#if DEBUG
import Foundation

extension MockStore {
  /// A developer-supplied manifest exercises the real renderer without shipping
  /// any historical programme or fixed date in the app.
  func applyCinemaPreviewIfRequested() {
    if let query = ProcessInfo.processInfo.environment["ROON_CINEMA_SETUP_QUERY"] {
      aiSearchContext = CapsuleSearchContext(query: query)
      cinema.setup = CapsuleSetup(request: CapsuleRequest(context: aiSearchContext!, tracks: aiResults))
      return
    }
    guard let path = ProcessInfo.processInfo.environment["ROON_CINEMA_PREVIEW_MANIFEST"],
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let capsule = try? JSONDecoder().decode(TimeCapsule.self, from: data),
          let first = capsule.request.tracks.first, !zones.isEmpty else { return }
    zones[0].track = Track(id: "cinema-preview", title: first.track, artist: first.artist,
      album: first.album, position: "0:00", remaining: "", progress: 0)
    cinema.capsules = [capsule]
    if ProcessInfo.processInfo.environment["ROON_CINEMA_PREVIEW_PREPARING"] == "1" {
      // Keep the delayed preview deterministic even on a paired simulator.
      client.onState = nil
      client.onZone = nil
      client.onQueue = nil
      queue = []
      isPlaying = true
      cinema.preparation = CapsulePreparation(request: capsule.request)
      cinema.preparing = true
      cinema.preparationMessage = "Gathering photographs for the montage..."
      cinema.showingLibrary = true
      Task {
        try? await Task.sleep(for: .seconds(45))
        cinema.preparation?.result = capsule
        cinema.preparing = false
      }
    } else {
      cinema.presented = capsule
    }
  }
}
#endif
