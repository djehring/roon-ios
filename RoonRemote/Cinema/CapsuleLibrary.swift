import Foundation
import Observation

/// The playlist lifecycle is independent of Roon's playback transport.
protocol CinemaClient {
  func timeCapsules() async throws -> [TimeCapsule]
  func requireCinemaOptionsSupport() async throws
  func requireCinemaManagementSupport() async throws
  func createTimeCapsule(_ request: CapsuleRequest) async throws -> CapsuleJob
  func rebuildTimeCapsule(_ id: String) async throws -> CapsuleJob
  func updateTimeCapsule(_ id: String, options: CapsuleOptions) async throws -> CapsuleJob
  func deleteTimeCapsule(_ id: String) async throws
  func timeCapsuleJob(_ id: String, generation: String?) async throws -> CapsuleJob
  func cinemaArtwork(tracks: [CapsuleTrack], zoneId: String) async throws -> Data?
  func setTimeCapsule(_ id: String, zoneId: String) async throws
  func playTracks(zoneId: String, tracks: [[String: String]]) async throws -> [SuggestedTrackPayload]
  func command(_ payload: [String: Any]) async throws
}

@MainActor
@Observable
final class CapsuleLibrary {
  var capsules: [TimeCapsule] = []
  var showingLibrary = false
  var presented: TimeCapsule?
  var preparing = false
  var loading = false
  var playing = false
  var libraryAfterViewer = false
  var playbackMemory = MontagePlaybackMemory()
  var playbackCapsuleId: String?
  var playbackMessage: String?
  var preparationMessage = ""
  var preparationError: String?
  var preparation: CapsulePreparation?
  var deletingId: String?
  var error: String?
  var setup: CapsuleSetup?
  var pendingRequest: CapsuleRequest?
  var pendingOriginal: TimeCapsule?
  var pendingPersonal: TimeCapsule?
  var selectedId: String?
  @ObservationIgnored private let personalStore: PersonalCinemaStore
  @ObservationIgnored private let pollInterval: Duration
  @ObservationIgnored private let progressTimeout: TimeInterval
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private var generation: Task<Void, Never>?
  @ObservationIgnored private var revision = 0
  private var albumCovers: [String: Data] = [:]
  @ObservationIgnored private var artworkRequests: [String: Task<Void, Never>] = [:]
  #if DEBUG
  @ObservationIgnored var previewClient: (any CinemaClient)?
  #endif

  init(personalStore: PersonalCinemaStore = .shared, pollInterval: Duration = .seconds(3),
    progressTimeout: TimeInterval = 900, now: @escaping () -> Date = Date.init) {
    self.personalStore = personalStore
    self.pollInterval = pollInterval
    self.progressTimeout = progressTimeout
    self.now = now
  }

  private func service(_ client: any CinemaClient) -> any CinemaClient {
    #if DEBUG
    if let previewClient { return previewClient }
    #endif
    return client
  }

  var items: [TimeCapsule] {
    guard let preparation, preparation.result == nil, preparation.original == nil else { return capsules }
    return [preparation.placeholder] + capsules
  }

  func isUpdating(_ capsule: TimeCapsule) -> Bool {
    preparing && preparation?.contains(capsule) == true
  }

  func failure(for capsule: TimeCapsule) -> String? {
    preparation?.contains(capsule) == true ? preparationError : nil
  }

  func openLibrary() { showingLibrary = true }

  private func artworkKey(_ tracks: [CapsuleTrack]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return (try? encoder.encode(tracks).base64EncodedString()) ?? ""
  }

  func artwork(for tracks: [CapsuleTrack]) -> Data? { albumCovers[artworkKey(tracks)] }

  /// Starts during setup, independently of AI generation and music playback.
  func warmArtwork(tracks: [CapsuleTrack], zoneId: String, client: any CinemaClient) {
    let key = artworkKey(tracks)
    guard !tracks.isEmpty, !zoneId.isEmpty, albumCovers[key] == nil, artworkRequests[key] == nil else { return }
    let client = service(client)
    artworkRequests[key] = Task {
      defer { artworkRequests[key] = nil }
      guard let bytes = try? await client.cinemaArtwork(tracks: tracks, zoneId: zoneId) else { return }
      if albumCovers.count >= 16 { albumCovers.removeAll() }
      albumCovers[key] = bytes
    }
  }

  func load(client: any CinemaClient) async {
    guard !loading else { return }
    let client = service(client)
    loading = true
    defer { loading = false }
    let snapshot = revision
    let personal = await personalStore.load()
    if snapshot == revision { merge(personal + capsules.filter { !$0.isPersonal }) }
    do {
      let shared = try await client.timeCapsules()
      // An older response must not resurrect a deletion or overwrite a completed edit.
      guard snapshot == revision else { return }
      merge(personal + shared)
      error = nil
    } catch is CancellationError {
    } catch { self.error = message(for: error) }
  }

  func create(context: CapsuleSearchContext, tracks: [SuggestedTrack], client: any CinemaClient) {
    guard !preparing else { openLibrary(); return }
    setup = CapsuleSetup(request: CapsuleRequest(context: context, tracks: tracks))
  }

  func finishSetup(client: any CinemaClient) {
    if let personal = pendingPersonal {
      pendingPersonal = nil
      pendingOriginal = nil
      preparationError = nil
      error = nil
      revision += 1
      merge([personal] + capsules.filter { $0.id != personal.id })
      selectedId = personal.id
      showingLibrary = true
    } else if let request = pendingRequest {
      let original = pendingOriginal
      pendingRequest = nil
      pendingOriginal = nil
      regenerate(request: request, original: original, client: client)
    }
  }

  private func merge(_ programmes: [TimeCapsule]) {
    var seen = Set<String>()
    capsules = programmes.filter { seen.insert($0.id).inserted }
      .sorted { $0.createdAt > $1.createdAt }
  }

  func regenerate(request: CapsuleRequest, original: TimeCapsule?, client: any CinemaClient) {
    guard !preparing, deletingId != original?.id || original == nil, !request.tracks.isEmpty else { return }
    let client = service(client)
    prepare(request: request, original: original, client: client) {
      if let original, let options = request.options {
        try await client.requireCinemaManagementSupport()
        return try await client.updateTimeCapsule(original.id, options: options)
      }
      try await client.requireCinemaOptionsSupport()
      return try await client.createTimeCapsule(request)
    }
  }

  func rebuild(_ capsule: TimeCapsule, client: any CinemaClient) {
    guard !preparing, deletingId != capsule.id else { return }
    let client = service(client)
    prepare(request: capsule.request, original: capsule, client: client) {
      try await client.rebuildTimeCapsule(capsule.id)
    }
  }

  func retry(client: any CinemaClient) {
    guard let preparation, !preparing else { return }
    if let original = preparation.original, preparation.placeholder.request.options == nil {
      rebuild(original, client: client)
    } else {
      regenerate(request: preparation.placeholder.request, original: preparation.original, client: client)
    }
  }

  private func prepare(request: CapsuleRequest, original: TimeCapsule?, client: any CinemaClient,
    start: @escaping () async throws -> CapsuleJob) {
    showingLibrary = true
    preparing = true
    preparationError = nil
    preparation = CapsulePreparation(request: request, original: original)
    selectedId = original?.id ?? preparation?.placeholder.id
    error = nil
    preparationMessage = "Researching your chosen subjects…"
    generation = Task {
      defer { preparing = false; generation = nil }
      do {
        var job = try await start()
        let expectedGeneration = job.generation
        var deadline = now().addingTimeInterval(progressTimeout)
        var progress = job.status + (job.message ?? "")
        while job.status != "ready" && job.status != "failed" {
          guard now() < deadline else {
            throw PersonalCinemaError("The bridge has not reported progress for 15 minutes. Refresh Cinema to check for the saved result.")
          }
          preparationMessage = job.message ?? (job.status == "images" ? "Gathering pictures…" : "Researching your chosen subjects…")
          try await Task.sleep(for: pollInterval)
          job = try await poll(job.id, generation: expectedGeneration, client: client, deadline: deadline)
          let nextProgress = job.status + (job.message ?? "")
          if nextProgress != progress {
            deadline = now().addingTimeInterval(progressTimeout)
            progress = nextProgress
          }
        }
        guard job.status == "ready", let capsule = job.capsule else {
          throw PersonalCinemaError(job.error ?? "No picture montage could be prepared. Your saved playlist is unchanged.")
        }
        if let expectedGeneration, capsule.generation != expectedGeneration {
          throw PersonalCinemaError("The bridge returned a different preparation. Please retry; your saved montage is unchanged.")
        }
        if let original, (capsule.createdAt == original.createdAt && capsule.generation == original.generation)
          || capsule.request.options != request.options {
          throw PersonalCinemaError("The rebuild did not finish. Please retry; your saved montage is unchanged.")
        }
        revision += 1
        merge([capsule] + capsules.filter { $0.id != capsule.id })
        preparation?.result = capsule
        selectedId = capsule.id
        preparationMessage = "Pictures ready"
      } catch is CancellationError {
      } catch { self.preparationError = message(for: error) }
    }
  }

  /// A dropped status request does not cancel the bridge's generation job.
  private func poll(_ id: String, generation: String?, client: any CinemaClient, deadline: Date) async throws -> CapsuleJob {
    while true {
      do { return try await client.timeCapsuleJob(id, generation: generation) }
      catch {
        guard retryableConnection(error) else { throw error }
        guard now() < deadline else {
          throw PersonalCinemaError("Cannot reconnect to check progress. The bridge may still finish; refresh Cinema when the connection returns.")
        }
        preparationMessage = "Reconnecting to check progress… Your montage is still being prepared."
        try await Task.sleep(for: pollInterval)
      }
    }
  }

  private func retryableConnection(_ error: Error) -> Bool {
    if let error = error as? URLError {
      return [.timedOut, .networkConnectionLost, .notConnectedToInternet,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
    }
    if case RoonAPIError.httpStatus(let status, _) = error { return [408, 502, 503, 504].contains(status) }
    return false
  }

  func remove(_ capsule: TimeCapsule, client: any CinemaClient) async -> Bool {
    guard deletingId == nil, !isUpdating(capsule) else { return false }
    deletingId = capsule.id
    error = nil
    defer { deletingId = nil }
    do {
      if capsule.id == preparation?.placeholder.id, preparation?.original == nil {
        // A failed, unsaved request has no shared manifest to delete.
      } else if capsule.isPersonal {
        try await personalStore.remove(capsule)
      } else {
        let client = service(client)
        try await client.requireCinemaManagementSupport()
        try await client.deleteTimeCapsule(capsule.id)
      }
      revision += 1
      capsules.removeAll { $0.id == capsule.id }
      if preparation?.contains(capsule) == true || preparation?.result?.id == capsule.id {
        preparation = nil
        preparationError = nil
      }
      if selectedId == capsule.id { selectedId = items.first?.id }
      return true
    } catch { self.error = message(for: error); return false }
  }

  /// Opening the visual companion is deliberately free of playback commands.
  func watch(_ capsule: TimeCapsule) {
    presented = isUpdating(capsule) ? preparation?.placeholder ?? capsule : capsule
    showingLibrary = false
  }

  func playPreparation(zoneId: String, current: Track?, queue: [QueueItem], isPlaying: Bool,
    client: any CinemaClient) async {
    guard let pending = preparation?.placeholder else { return }
    let client = service(client)
    if CapsuleNowPlaying.select(preparing: false, current: current, queue: queue,
      associated: nil, saved: [pending]) != nil {
      watch(pending)
      if !isPlaying {
        do { try await client.command(["type": "PLAY_PAUSE", "data": ["zone_id": zoneId]]) }
        catch { playbackCapsuleId = pending.id; playbackMessage = message(for: error) }
      }
    } else {
      await play(pending, zoneId: zoneId, client: client, associate: false)
    }
  }

  func play(_ capsule: TimeCapsule, zoneId: String, client: any CinemaClient, associate: Bool = true) async {
    guard !playing, !zoneId.isEmpty else { return }
    let client = service(client)
    let waiting = isUpdating(capsule) || capsule.id == preparation?.placeholder.id
    let target = waiting ? preparation?.placeholder ?? capsule : capsule
    playing = true
    playbackCapsuleId = target.id
    playbackMessage = "Starting music…"
    error = nil
    watch(target)
    defer { playing = false }
    do {
      let missing = try await client.playTracks(zoneId: zoneId, tracks: target.request.tracks.map {
        ["artist": $0.artist, "track": $0.track, "album": $0.album]
      })
      if associate && !capsule.isPersonal && !waiting {
        try await client.setTimeCapsule(capsule.id, zoneId: zoneId)
      }
      playbackMessage = missing.isEmpty ? nil
        : "\(missing.count) of \(target.request.tracks.count) tracks unavailable. Pictures will continue."
    } catch { playbackMessage = "Music could not start: \(message(for: error))" }
  }

  private func message(for error: Error) -> String {
    if case RoonAPIError.httpStatus(404, _) = error {
      return "This Cinema item or feature is unavailable. Refresh the library, or update the bridge."
    }
    return error.localizedDescription
  }
}
