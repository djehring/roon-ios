import Foundation
import Observation
import UIKit

/// The playlist lifecycle is independent of Roon's playback transport.
protocol CinemaClient {
  var cinemaSyncScope: String { get }
  func supportsCinemaSync() async throws -> Bool
  func uploadCinemaImage(_ data: Data, file: String) async throws
  func publishPersonalCinema(_ capsule: TimeCapsule, mutationId: String) async throws -> TimeCapsule
  func cinemaImage(_ file: String) async throws -> Data
  func timeCapsules() async throws -> [TimeCapsule]
  func requireCinemaOptionsSupport() async throws
  func requireCinemaManagementSupport() async throws
  func requireCinemaMusicSupport() async throws
  func saveCinemaContent(_ id: String, request: CapsuleRequest, baseRevision: Int, mutationId: String) async throws -> CapsuleJob
  func playCinemaTracks(zoneId: String, tracks: [CapsuleTrack]) async throws -> [SuggestedTrackPayload]
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

extension CinemaClient {
  var cinemaSyncScope: String { "preview" }
  func supportsCinemaSync() async throws -> Bool { false }
  func uploadCinemaImage(_ data: Data, file: String) async throws { throw PersonalCinemaError("Update the bridge to sync personal cinemas.") }
  func publishPersonalCinema(_ capsule: TimeCapsule, mutationId: String) async throws -> TimeCapsule {
    throw PersonalCinemaError("Update the bridge to sync personal cinemas.")
  }
  func cinemaImage(_ file: String) async throws -> Data { throw URLError(.resourceUnavailable) }
  func requireCinemaMusicSupport() async throws {
    throw PersonalCinemaError("Update the bridge to edit Cinema music.")
  }
  func saveCinemaContent(_ id: String, request: CapsuleRequest, baseRevision: Int, mutationId: String) async throws -> CapsuleJob {
    throw PersonalCinemaError("Update the bridge to edit Cinema music.")
  }
  func playCinemaTracks(zoneId: String, tracks: [CapsuleTrack]) async throws -> [SuggestedTrackPayload] {
    try await playTracks(zoneId: zoneId, tracks: tracks.map { ["artist": $0.artist, "track": $0.track, "album": $0.album] })
  }
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
  var pendingJob: CapsuleJob?
  var savedMessage: String?
  var selectedId: String?
  var syncingIds: Set<String> = []
  var downloadedIds: Set<String> = []
  var syncMessages: [String: String] = [:]
  var syncErrors: [String: String] = [:]
  var syncConflicts: Set<String> = []
  @ObservationIgnored private let personalStore: PersonalCinemaStore
  @ObservationIgnored private let resourceStore: CinemaResourceStore
  @ObservationIgnored private let pollInterval: Duration
  @ObservationIgnored private let progressTimeout: TimeInterval
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private var generation: Task<Void, Never>?
  @ObservationIgnored private var revision = 0
  @ObservationIgnored private var loadedScope: String?
  private var albumCovers: [String: Data] = [:]
  @ObservationIgnored private var artworkRequests: [String: Task<Void, Never>] = [:]
  #if DEBUG
  @ObservationIgnored var previewClient: (any CinemaClient)?
  #endif

  init(personalStore: PersonalCinemaStore = .shared, pollInterval: Duration = .seconds(3),
    progressTimeout: TimeInterval = 900, now: @escaping () -> Date = Date.init,
    resourceStore: CinemaResourceStore = .shared) {
    self.personalStore = personalStore
    self.resourceStore = resourceStore
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
    if let loadedScope, loadedScope != client.cinemaSyncScope {
      capsules = []
      downloadedIds = []
      syncErrors = [:]
      syncConflicts = []
      revision += 1
    }
    loadedScope = client.cinemaSyncScope
    loading = true
    defer { loading = false }
    let snapshot = revision
    var personal: [TimeCapsule]
    #if DEBUG
    if previewClient != nil { personal = [] }
    else { personal = await personalStore.load() }
    #else
    personal = await personalStore.load()
    #endif
    personal = personal.filter { $0.syncScope == nil || $0.syncScope == client.cinemaSyncScope }
    let cached = await resourceStore.catalog(scope: client.cinemaSyncScope)
    if snapshot == revision { merge(personal + capsules + cached) }
    do {
      var shared = try await client.timeCapsules()
      let supportsSync = try await client.supportsCinemaSync()
      // An older response must not resurrect a deletion or overwrite a completed edit.
      guard snapshot == revision else { return }
      for index in shared.indices where shared[index].isPersonal {
        shared[index].syncedRevision = shared[index].revision
        shared[index].syncScope = client.cinemaSyncScope
      }
      let drafts = personal.filter { $0.needsPublication }
      // A shared deletion must also remove the cached manifest, never re-upload it.
      if supportsSync {
        for local in personal where !local.needsPublication && !shared.contains(where: { $0.id == local.id }) {
          guard snapshot == revision,
            try await personalStore.reconcile(local, expected: local, remove: true) else { return }
        }
        for remote in shared where remote.isPersonal && !drafts.contains(where: { $0.id == remote.id }) {
          guard snapshot == revision,
            try await personalStore.reconcile(remote, expected: personal.first { $0.id == remote.id }) else { return }
        }
      }
      guard snapshot == revision else { return }
      merge(drafts + shared + (supportsSync ? [] : personal))
      try await resourceStore.saveCatalog(shared, scope: client.cinemaSyncScope)
      recoverCompletedPreparation(from: shared)
      error = nil
      for draft in drafts where !syncConflicts.contains(draft.id) {
        if supportsSync { await publish(draft, client: client) }
        else { syncErrors[draft.id] = "Update the bridge to share this Cinema with your other devices." }
      }
    } catch is CancellationError {
    } catch { self.error = message(for: error) }
    await refreshDownloads()
  }

  private func available(_ image: CapsuleImage) async -> Bool {
    if let local = image.localFile, await personalStore.hasImage(local) { return true }
    return await resourceStore.contains(image.file)
  }

  private func refreshDownloads() async {
    downloadedIds.formIntersection(capsules.map(\.id))
    for capsule in capsules {
      var complete = !capsule.resourceImages.isEmpty
      for image in capsule.resourceImages where !(await available(image)) { complete = false; break }
      if complete { downloadedIds.insert(capsule.id) } else { downloadedIds.remove(capsule.id) }
    }
  }

  /// Publish the snapshot last, so other devices never see a half-uploaded montage.
  private func publish(_ capsule: TimeCapsule, client: any CinemaClient) async {
    guard !syncingIds.contains(capsule.id), deletingId != capsule.id else { return }
    syncingIds.insert(capsule.id)
    syncErrors[capsule.id] = nil
    defer { syncingIds.remove(capsule.id); syncMessages[capsule.id] = nil }
    do {
      var publication = try await personalStore.publication(capsule)
      if publication.originDeviceName == nil { publication.originDeviceName = UIDevice.current.name }
      let images = publication.resourceImages
      for (index, image) in images.enumerated() {
        try Task.checkCancellation()
        syncMessages[capsule.id] = "Sharing picture \(index + 1) of \(images.count)…"
        // Previously shared pictures are immutable and already on the bridge.
        if capsule.syncedRevision != nil { continue }
        guard let local = image.localFile else { throw URLError(.fileDoesNotExist) }
        let bytes = try await personalStore.imageData(local)
        try await client.uploadCinemaImage(bytes, file: image.file)
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      // Stable across an uncertain response/app restart; the bridge deduplicates retries.
      let mutation = CinemaSyncIdentity.mutation(try encoder.encode(publication))
      var saved = try await client.publishPersonalCinema(publication, mutationId: mutation)
      saved.syncedRevision = saved.revision
      saved.syncScope = client.cinemaSyncScope
      // An editor may have saved a newer local draft while this upload was in flight.
      if let current = try await personalStore.manifest(capsule.id), current != capsule {
        var pending = current
        pending.syncedRevision = saved.revision
        pending.revision = (saved.revision ?? 0) + 1
        pending.syncScope = saved.syncScope
        pending.originDeviceName = saved.originDeviceName
        saved = pending
      }
      try await personalStore.storeManifest(saved)
      syncConflicts.remove(capsule.id)
      revision += 1
      merge([saved] + capsules.filter { $0.id != saved.id })
      try await resourceStore.saveCatalog(capsules.filter { !$0.needsPublication }, scope: client.cinemaSyncScope)
    } catch is CancellationError {
    } catch {
      syncErrors[capsule.id] = message(for: error)
      if case RoonAPIError.httpStatus(409, _) = error { syncConflicts.insert(capsule.id) }
    }
  }

  /// Explicitly chosen after a conflict; ordinary refresh always preserves the local draft.
  func useSharedVersion(_ capsule: TimeCapsule, client: any CinemaClient) async {
    let client = service(client)
    guard !syncingIds.contains(capsule.id) else { return }
    syncingIds.insert(capsule.id)
    defer { syncingIds.remove(capsule.id) }
    do {
      let shared = try await client.timeCapsules()
      if var remote = shared.first(where: { $0.id == capsule.id }) {
        remote.syncedRevision = remote.revision
        remote.syncScope = client.cinemaSyncScope
        try await personalStore.storeManifest(remote)
        merge([remote] + capsules.filter { $0.id != capsule.id })
      } else {
        try await personalStore.remove(capsule)
        capsules.removeAll { $0.id == capsule.id }
      }
      revision += 1
      syncConflicts.remove(capsule.id)
      syncErrors[capsule.id] = nil
      try await resourceStore.saveCatalog(capsules.filter { !$0.needsPublication }, scope: client.cinemaSyncScope)
      await refreshDownloads()
    } catch { syncErrors[capsule.id] = message(for: error) }
  }

  func syncToDevice(_ capsule: TimeCapsule, client: any CinemaClient) async {
    let client = service(client)
    guard !syncingIds.contains(capsule.id), deletingId != capsule.id, !isUpdating(capsule) else { return }
    if capsule.needsPublication {
      do {
        guard try await client.supportsCinemaSync() else {
          throw PersonalCinemaError("Update the bridge to share this Cinema with your other devices.")
        }
        await publish(capsule, client: client)
      } catch { syncErrors[capsule.id] = message(for: error) }
      await refreshDownloads()
      return
    }
    syncingIds.insert(capsule.id)
    syncErrors[capsule.id] = nil
    defer { syncingIds.remove(capsule.id); syncMessages[capsule.id] = nil }
    do {
      let images = capsule.resourceImages
      for (index, image) in images.enumerated() {
        try Task.checkCancellation()
        syncMessages[capsule.id] = "Syncing picture \(index + 1) of \(images.count)…"
        if await available(image) { continue }
        let bytes = try await client.cinemaImage(image.file)
        try await resourceStore.saveImage(bytes, file: image.file)
      }
      try Task.checkCancellation()
      if !images.isEmpty { downloadedIds.insert(capsule.id) }
      try await resourceStore.saveCatalog(capsules.filter { !$0.needsPublication }, scope: client.cinemaSyncScope)
      await refreshDownloads()
    } catch is CancellationError {
    } catch { syncErrors[capsule.id] = message(for: error) }
  }

  private func recoverCompletedPreparation(from saved: [TimeCapsule]) {
    guard !preparing, preparationError != nil, let preparation, preparation.result == nil,
      let expected = preparation.expectedGeneration,
      let completed = saved.first(where: {
        $0.id == preparation.jobId && $0.generation == expected
          && $0.request.options == preparation.placeholder.request.options
      }) else { return }
    revision += 1
    self.preparation?.result = completed
    preparationError = nil
    preparationMessage = "Pictures ready"
    selectedId = completed.id
  }

  func create(context: CapsuleSearchContext, tracks: [SuggestedTrack], client: any CinemaClient) {
    guard !preparing else { openLibrary(); return }
    setup = CapsuleSetup(request: CapsuleRequest(context: context, tracks: tracks))
  }

  func save(request: CapsuleRequest, original: TimeCapsule?, mutationId: String, client: any CinemaClient) async throws {
    let client = service(client)
    try await client.requireCinemaMusicSupport()
    let unchangedPictures = original.map { saved in
      request.options == saved.request.options || request.options?.hasSamePictureContent(
        as: saved.request.options ?? CapsuleSetup(request: saved.request).initialOptions) == true
    } ?? false
    if preparing && !unchangedPictures {
      throw PersonalCinemaError("Pictures are updating. You can save music changes now, or wait before creating another montage.")
    }
    let job: CapsuleJob
    if let original {
      job = try await client.saveCinemaContent(original.id, request: request,
        baseRevision: original.revision ?? 0, mutationId: mutationId)
    } else { job = try await client.createTimeCapsule(request) }
    if job.status == "failed" { throw PersonalCinemaError(job.error ?? "Cinema could not be saved. Please retry.") }
    if let saved = job.capsule, job.status == "ready" {
      pendingPersonal = saved
      if preparation?.original?.id == saved.id {
        preparation?.placeholder.request.tracks = saved.request.tracks
        preparation?.placeholder.request.title = saved.title
        preparation?.placeholder.title = saved.title
      }
      savedMessage = original == nil ? "Cinema saved." : "Saved. Your changes will play next time."
    } else {
      pendingRequest = request
      pendingOriginal = original
      pendingJob = job
    }
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
      if personal.needsPublication {
        Task { await syncToDevice(personal, client: client) }
      }
    } else if let request = pendingRequest {
      let original = pendingOriginal
      pendingRequest = nil
      pendingOriginal = nil
      if let job = pendingJob {
        pendingJob = nil
        prepare(request: request, original: original, client: service(client)) { job }
      } else { regenerate(request: request, original: original, client: client) }
    }
  }

  private func merge(_ programmes: [TimeCapsule]) {
    for programme in programmes {
      if let old = capsules.first(where: { $0.id == programme.id }), old.resourceImages != programme.resourceImages {
        downloadedIds.remove(programme.id)
      }
    }
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
    let client = service(client)
    let request = preparation.placeholder.request
    prepare(request: request, original: preparation.original, client: client) {
      // A failed status check does not mean the paid build failed. Recover or
      // resume that generation before submitting another update.
      if let id = preparation.jobId, let expected = preparation.expectedGeneration {
        self.preparation?.jobId = id
        self.preparation?.expectedGeneration = expected
        let existing = try await client.timeCapsuleJob(id, generation: expected)
        if existing.status != "failed" { return existing }
      }
      if let original = preparation.original {
        if request.clientRequestId != nil {
          try await client.requireCinemaMusicSupport()
          let latest = self.capsules.first { $0.id == original.id } ?? original
          return try await client.saveCinemaContent(original.id, request: request,
            baseRevision: latest.revision ?? 0, mutationId: UUID().uuidString)
        }
        if let options = request.options {
          try await client.requireCinemaManagementSupport()
          return try await client.updateTimeCapsule(original.id, options: options)
        }
        return try await client.rebuildTimeCapsule(original.id)
      }
      try await client.requireCinemaOptionsSupport()
      return try await client.createTimeCapsule(request)
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
    preparationMessage = request.options?.mode == .artwork ? "Collecting album artwork…" : "Researching your chosen subjects…"
    generation = Task {
      defer { preparing = false; generation = nil }
      do {
        var job = try await start()
        let expectedGeneration = job.generation
        preparation?.jobId = job.id
        preparation?.expectedGeneration = expectedGeneration
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
        let matchingPictures = request.options.map { expected in
          capsule.request.options?.hasSamePictureContent(as: expected) == true
        } ?? (capsule.request.options == nil)
        let unchangedGeneration = original.map {
          capsule.createdAt == $0.createdAt && capsule.generation == $0.generation
        } ?? false
        if unchangedGeneration || !matchingPictures {
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
    guard deletingId == nil, !isUpdating(capsule), !syncingIds.contains(capsule.id) else { return false }
    deletingId = capsule.id
    error = nil
    defer { deletingId = nil }
    do {
      if capsule.id == preparation?.placeholder.id, preparation?.original == nil {
        // A failed, unsaved request has no shared manifest to delete.
      } else if capsule.isPersonal {
        if capsule.syncedRevision != nil {
          try await service(client).deleteTimeCapsule(capsule.id)
        }
        try await personalStore.remove(capsule)
      } else {
        let client = service(client)
        try await client.requireCinemaManagementSupport()
        try await client.deleteTimeCapsule(capsule.id)
      }
      revision += 1
      capsules.removeAll { $0.id == capsule.id }
      downloadedIds.remove(capsule.id)
      syncErrors[capsule.id] = nil
      try await resourceStore.saveCatalog(capsules.filter { !$0.needsPublication }, scope: service(client).cinemaSyncScope)
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
      let missing = try await client.playCinemaTracks(zoneId: zoneId, tracks: target.request.tracks)
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
