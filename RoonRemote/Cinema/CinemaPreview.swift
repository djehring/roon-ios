#if DEBUG
import Foundation

extension MockStore {
  /// Optional, external fixtures exercise the real screens without shipping
  /// mock photographs or calling the paired bridge during design verification.
  func applyCinemaPreviewIfRequested() {
    let environment = ProcessInfo.processInfo.environment
    if let query = environment["ROON_CINEMA_SETUP_QUERY"] {
      aiSearchContext = CapsuleSearchContext(query: query)
      cinema.setup = CapsuleSetup(request: CapsuleRequest(context: aiSearchContext!, tracks: aiResults))
      return
    }
    let bytes: Data?
    if let json = environment["ROON_CINEMA_PREVIEW_JSON"] { bytes = Data(json.utf8) }
    else if let path = environment["ROON_CINEMA_PREVIEW_MANIFEST"] {
      bytes = try? Data(contentsOf: URL(fileURLWithPath: path))
    } else { bytes = nil }
    guard let bytes else { return }
    let decoder = JSONDecoder()
    let items = (try? decoder.decode([TimeCapsule].self, from: bytes))
      ?? (try? decoder.decode(TimeCapsule.self, from: bytes)).map { [$0] } ?? []
    guard let capsule = items.first, let first = capsule.request.tracks.first, !zones.isEmpty else { return }
    client.onState = nil; client.onZone = nil; client.onQueue = nil
    zones[0].track = Track(id: "cinema-preview", title: first.track, artist: first.artist,
      album: first.album, position: "0:42", remaining: "3:09", progress: 0.18)
    let cover = environment["ROON_CINEMA_PREVIEW_COVER"].flatMap { Data(base64Encoded: $0) }
    if let cover, environment["ROON_CINEMA_PREVIEW_COVER_SOURCE"] == "current" {
      zones[0].track?.title = "An unrelated song"
      zones[0].track?.artist = "Another artist"
      zones[0].track?.imageKey = "preview-cover"
      artwork.insert(cover, for: ArtworkCache.Key(imageKey: "preview-cover", pixels: ArtworkCache.heroPixels))
    } else if cover != nil { zones[0].track = nil }
    queue = []
    isPlaying = zones[0].track != nil
    cinema.capsules = items
    cinema.selectedId = capsule.id
    cinema.previewClient = CinemaPreviewClient(items: items,
      delay: Double(environment["ROON_CINEMA_PREVIEW_DELAY"] ?? "3") ?? 3,
      fail: environment["ROON_CINEMA_PREVIEW_FAIL"] == "1",
      cover: environment["ROON_CINEMA_PREVIEW_COVER_SOURCE"] == "current" ? nil : cover)
    if environment["ROON_CINEMA_PREVIEW_NEW"] == "1" {
      cinema.preparation = CapsulePreparation(request: capsule.request, original: nil)
      cinema.preparing = true
      cinema.preparationMessage = "Researching your chosen subjects…"
      cinema.presented = cinema.preparation?.placeholder
    } else if environment["ROON_CINEMA_PREVIEW_PREPARING"] == "1" {
      cinema.preparation = CapsulePreparation(request: capsule.request, original: capsule)
      cinema.preparing = true
      cinema.preparationMessage = "Gathering pictures…"
      cinema.showingLibrary = true
      Task {
        try? await Task.sleep(for: .seconds(45))
        cinema.preparation?.result = capsule
        cinema.preparing = false
      }
    } else if environment["ROON_CINEMA_PREVIEW_LIBRARY"] == "1" {
      cinema.showingLibrary = true
    } else { cinema.presented = capsule }
  }
}

@MainActor
private final class CinemaPreviewClient: CinemaClient {
  var items: [TimeCapsule]
  let delay: TimeInterval
  let fail: Bool
  let cover: Data?
  private var replacement: TimeCapsule?
  private var readyAt = Date.distantPast

  init(items: [TimeCapsule], delay: TimeInterval, fail: Bool, cover: Data?) {
    self.items = items; self.delay = delay; self.fail = fail; self.cover = cover
  }
  func timeCapsules() async throws -> [TimeCapsule] { items }
  func requireCinemaOptionsSupport() async throws { }
  func requireCinemaManagementSupport() async throws { }
  func requireCinemaMusicSupport() async throws { }
  func saveCinemaContent(_ id: String, request: CapsuleRequest, baseRevision: Int, mutationId: String) async throws -> CapsuleJob {
    guard var item = items.first(where: { $0.id == id }) else { throw PersonalCinemaError("Missing preview") }
    let updatePictures = request.options?.hasSamePictureContent(as: item.request.options ?? CapsuleSetup(request: item.request).initialOptions) == false
    item.request = request
    item.title = request.title ?? item.title
    item.revision = (item.revision ?? 0) + 1
    if updatePictures {
      item.createdAt = ISO8601DateFormatter().string(from: Date())
      replacement = item
      readyAt = Date().addingTimeInterval(delay)
      return CapsuleJob(id: id, status: "images")
    }
    items.removeAll { $0.id == id }; items.insert(item, at: 0)
    return CapsuleJob(id: id, status: "ready", capsule: item)
  }
  func createTimeCapsule(_ request: CapsuleRequest) async throws -> CapsuleJob {
    guard let first = items.first else { throw PersonalCinemaError("Missing preview") }
    var item = first
    item.id = request.clientRequestId ?? UUID().uuidString
    item.request = request
    item.title = request.title ?? request.query
    item.createdAt = ISO8601DateFormatter().string(from: Date())
    if request.options?.mode == .artwork {
      items.insert(item, at: 0)
      return CapsuleJob(id: item.id, status: "ready", capsule: item)
    }
    replacement = item
    readyAt = Date().addingTimeInterval(delay)
    return CapsuleJob(id: item.id, status: "images")
  }
  func rebuildTimeCapsule(_ id: String) async throws -> CapsuleJob {
    guard let item = items.first(where: { $0.id == id }) else { throw PersonalCinemaError("Missing preview") }
    return try await updateTimeCapsule(id, options: CapsuleSetup(request: item.request, original: item).initialOptions)
  }
  func updateTimeCapsule(_ id: String, options: CapsuleOptions) async throws -> CapsuleJob {
    guard var capsule = items.first(where: { $0.id == id }) else { throw PersonalCinemaError("Missing preview") }
    capsule.request.options = options
    capsule.createdAt = ISO8601DateFormatter().string(from: Date())
    replacement = capsule
    readyAt = Date().addingTimeInterval(delay)
    return CapsuleJob(id: id, status: "images")
  }
  func deleteTimeCapsule(_ id: String) async throws { items.removeAll { $0.id == id } }
  func cinemaArtwork(tracks: [CapsuleTrack], zoneId: String) async throws -> Data? { cover }
  func timeCapsuleJob(_ id: String, generation: String?) async throws -> CapsuleJob {
    guard Date() >= readyAt else { return CapsuleJob(id: id, status: "images") }
    if fail { return CapsuleJob(id: id, status: "failed", error: "Preview: picture service unavailable") }
    guard let replacement else { throw PersonalCinemaError("Missing preview") }
    items.removeAll { $0.id == id }; items.insert(replacement, at: 0)
    return CapsuleJob(id: id, status: "ready", capsule: replacement)
  }
  func setTimeCapsule(_ id: String, zoneId: String) async throws { }
  func playTracks(zoneId: String, tracks: [[String: String]]) async throws -> [SuggestedTrackPayload] { [] }
  func command(_ payload: [String: Any]) async throws { }
}
#endif
