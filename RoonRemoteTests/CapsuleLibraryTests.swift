import Foundation
import Testing

@Suite("Cinema playlist lifecycle")
@MainActor
struct CapsuleLibraryTests {
  @Test func openingCinemaAlwaysShowsLibraryAndWatchNeverChangesMusic() {
    let library = CapsuleLibrary()
    let capsule = sample()
    library.capsules = [capsule]
    library.openLibrary()
    #expect(library.showingLibrary)
    #expect(library.presented == nil)
    library.watch(capsule)
    #expect(library.presented == capsule)
    #expect(!library.showingLibrary)
    #expect(!library.playing)
    #expect(library.playbackCapsuleId == nil)
  }

  @Test func editKeepsTheOldMontageUntilSuccessAndResolvesOnlyItsOwnViewer() async throws {
    let library = CapsuleLibrary(pollInterval: .milliseconds(1))
    let client = CinemaStub()
    let old = sample()
    library.capsules = [old]
    var request = old.request
    request.options?.pace = .relaxed
    library.regenerate(request: request, original: old, client: client)
    #expect(library.items.count == 1)
    #expect(library.items[0] == old)
    #expect(library.isUpdating(old))
    library.watch(old)
    let placeholder = try #require(library.presented)
    #expect(placeholder.contextImage == old.montageFrames.first?.image)
    #expect(placeholder.request.tracks == old.request.tracks)
    try await wait { client.updatedId != nil }
    #expect(client.updatedId == old.id)
    #expect(client.updatedOptions?.pace == .relaxed)
    #expect(client.playCount == 0)
    var ready = old
    ready.request = request
    ready.createdAt = "2026-09-19T00:00:00Z"
    client.job = CapsuleJob(id: old.id, status: "ready", capsule: ready)
    try await wait { !library.preparing }
    #expect(library.capsules == [ready])
    #expect(library.preparation?.resolve(placeholder) == ready)
    #expect(library.preparation?.resolve(sample(id: "other")).id == "other")
  }

  @Test func failedRegenerationKeepsOriginalAndDeleteFailureDoesNotHideIt() async throws {
    let library = CapsuleLibrary(pollInterval: .milliseconds(1))
    let client = CinemaStub()
    let old = sample()
    library.capsules = [old]
    client.job = CapsuleJob(id: old.id, status: "failed", error: "No pictures")
    library.regenerate(request: old.request, original: old, client: client)
    try await wait { !library.preparing }
    #expect(library.capsules == [old])
    #expect(library.failure(for: old) == "No pictures")
    library.watch(old)
    #expect(library.presented == old)
    client.deletionError = PersonalCinemaError("Bridge offline")
    #expect(await library.remove(old, client: client) == false)
    #expect(library.capsules == [old])
    #expect(library.error == "Bridge offline")
    client.deletionError = nil
    #expect(await library.remove(old, client: client))
    #expect(library.capsules.isEmpty)
    #expect(library.preparation == nil)
  }

  @Test func deleteIsDisabledDuringRegenerationAndPlaybackDoesNotWaitForPictures() async throws {
    let library = CapsuleLibrary(pollInterval: .milliseconds(1))
    let client = CinemaStub()
    let old = sample()
    library.capsules = [old]
    library.regenerate(request: old.request, original: old, client: client)
    #expect(await library.remove(old, client: client) == false)
    #expect(client.deletedIds.isEmpty)
    await library.play(old, zoneId: "living", client: client)
    #expect(client.playCount == 1)
    #expect(client.playedTracks?.first?["track"] == "Dancing Queen")
    #expect(client.associatedIds.isEmpty)
    #expect(library.presented?.id == library.preparation?.placeholder.id)
    client.job = CapsuleJob(id: old.id, status: "ready", capsule: old)
    try await wait { !library.preparing }
  }

  @Test func alreadyPlayingSoundtrackIsNotRestartedWhilePreparing() async throws {
    let library = CapsuleLibrary(pollInterval: .milliseconds(1))
    let client = CinemaStub()
    let old = sample()
    library.regenerate(request: old.request, original: old, client: client)
    await library.playPreparation(zoneId: "living", current: Track(id: "song", title: "Dancing Queen", artist: "ABBA",
      album: "Arrival", position: "1:00", remaining: "2:00", progress: 0.3), queue: [], isPlaying: true, client: client)
    #expect(client.playCount == 0)
    #expect(client.commandCount == 0)
    client.job = CapsuleJob(id: old.id, status: "failed", error: "Test complete")
    try await wait { !library.preparing }
  }

  @Test func lateRefreshCannotResurrectADeletedPlaylist() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = CapsuleLibrary(personalStore: PersonalCinemaStore(directory: directory))
    let client = CinemaStub()
    let old = sample()
    library.capsules = [old]
    client.delayLoad = true
    let load = Task { await library.load(client: client) }
    try await wait { client.loadContinuation != nil }
    #expect(await library.remove(old, client: client))
    client.loadContinuation?.resume(returning: [old])
    await load.value
    #expect(library.items.isEmpty)
    // Another device can later recreate an identical request (and therefore ID).
    client.delayLoad = false
    client.saved = [old]
    await library.load(client: client)
    #expect(library.items == [old])
  }

  @Test func editorRestoresSavedOptionsInsteadOfGlobalDefaults() {
    var old = sample()
    old.request.options?.periodStart = "1976-09-01"
    old.request.options?.periodEnd = "1976-09-30"
    old.request.options?.topics = [.culture]
    old.request.options?.motion = .still
    let setup = CapsuleSetup(request: old.request, original: old)
    #expect(setup.isEditing)
    #expect(setup.initialOptions == old.request.options)
  }

  @Test func albumCoverLoadsBeforeGenerationWithoutStartingMusicAndSurvivesSetup() async throws {
    let library = CapsuleLibrary(pollInterval: .milliseconds(1))
    let client = CinemaStub()
    let request = sample().request
    library.warmArtwork(tracks: request.tracks, zoneId: "living", client: client)
    library.warmArtwork(tracks: request.tracks, zoneId: "living", client: client)
    try await wait { client.artworkContinuation != nil }
    #expect(client.artworkCalls == 1)
    let cover = Data([1, 2, 3])
    client.artworkContinuation?.resume(returning: cover)
    try await wait { library.artwork(for: request.tracks) != nil }
    library.regenerate(request: request, original: nil, client: client)
    #expect(library.artwork(for: request.tracks) == cover)
    #expect(client.playCount == 0)
    #expect(client.commandCount == 0)
    client.job = CapsuleJob(id: "new", status: "failed", error: "Test complete")
    try await wait { !library.preparing }
  }

  @Test func oldBridgeCannotMistakeTheSavedMontageForAFinishedRebuild() async throws {
    let library = CapsuleLibrary(pollInterval: .milliseconds(1))
    let client = CinemaStub()
    let old = sample()
    library.capsules = [old]
    client.job = CapsuleJob(id: old.id, status: "ready", capsule: old)
    library.rebuild(old, client: client)
    try await wait { !library.preparing }
    #expect(library.preparationError?.contains("did not finish") == true)
    #expect(library.preparation?.result == nil)
    #expect(library.capsules == [old])
  }

  @Test func pollingFollowsThisGenerationAndRejectsAResultFromAnotherBuild() async throws {
    let library = CapsuleLibrary(pollInterval: .milliseconds(1))
    let client = CinemaStub()
    let old = sample()
    library.capsules = [old]
    client.job = CapsuleJob(id: old.id, status: "images", generation: "this-build")
    library.rebuild(old, client: client)
    try await wait { client.requestedGeneration != nil }
    #expect(client.requestedGeneration == "this-build")
    var wrong = old
    wrong.createdAt = "2026-09-19T00:00:00Z"
    wrong.generation = "another-build"
    client.job = CapsuleJob(id: old.id, status: "ready", capsule: wrong, generation: "another-build")
    try await wait { !library.preparing }
    #expect(library.preparation?.result == nil)
    #expect(library.capsules == [old])
    #expect(library.preparationError?.contains("different preparation") == true)
  }

  private func wait(until ready: () -> Bool) async throws {
    for _ in 0..<200 {
      if ready() { return }
      try await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("Cinema operation did not complete")
  }

  @Test func timeoutWhilePollingReconnectsToTheSameBuildWithoutStartingOver() async throws {
    let library = CapsuleLibrary(pollInterval: .milliseconds(1))
    let client = CinemaStub()
    let old = sample()
    library.capsules = [old]
    client.job = CapsuleJob(id: old.id, status: "images", generation: "bowie-build")
    client.pollFailure = URLError(.timedOut)
    library.rebuild(old, client: client)
    try await wait { library.preparationMessage.contains("Reconnecting") }
    #expect(library.preparing)
    #expect(library.preparationError == nil)
    var result = old
    result.generation = "bowie-build"
    result.createdAt = "2026-09-19T00:00:00Z"
    client.job = CapsuleJob(id: old.id, status: "ready", capsule: result, generation: "bowie-build")
    client.pollFailure = nil
    try await wait { !library.preparing }
    #expect(library.preparation?.result == result)
    #expect(client.rebuildCount == 1)
    #expect(client.requestedGeneration == "bowie-build")
  }

  @Test func serverResearchProgressIsShownAndPermanentPollingErrorsStop() async throws {
    let library = CapsuleLibrary(pollInterval: .milliseconds(1))
    let client = CinemaStub()
    client.job = CapsuleJob(id: "new", status: "researching", message: "Researching artist pictures…")
    library.regenerate(request: sample().request, original: nil, client: client)
    try await wait { library.preparationMessage == "Researching artist pictures…" }
    client.pollFailure = RoonAPIError.httpStatus(404, nil)
    try await wait { !library.preparing }
    #expect(library.preparationError != nil)
    #expect(library.preparation?.result == nil)
  }

  @Test func aLongBuildKeepsPollingWhileTheBridgeReportsProgress() async throws {
    var clock = Date(timeIntervalSince1970: 0)
    let library = CapsuleLibrary(pollInterval: .milliseconds(1), progressTimeout: 10, now: { clock })
    let client = CinemaStub()
    let old = sample()
    client.job = CapsuleJob(id: old.id, status: "researching", message: "Portraits")
    library.rebuild(old, client: client)
    try await wait { library.preparationMessage == "Portraits" }
    clock = clock.addingTimeInterval(9)
    client.job.message = "Career"
    try await wait { library.preparationMessage == "Career" }
    clock = clock.addingTimeInterval(9)
    client.job.message = "Checking pictures"
    try await wait { library.preparationMessage == "Checking pictures" }
    #expect(library.preparing)
    #expect(library.preparationError == nil)
    var ready = old
    ready.createdAt = "2026-09-19T00:00:00Z"
    client.job = CapsuleJob(id: old.id, status: "ready", capsule: ready)
    try await wait { !library.preparing }
    #expect(library.preparation?.result == ready)
    #expect(client.rebuildCount == 1)
  }

  private func sample(id: String = "saved") -> TimeCapsule {
    var request = CapsuleRequest(context: CapsuleSearchContext(query: "September 1976"), tracks: [
      SuggestedTrack(id: "song", title: "Dancing Queen", artist: "ABBA", album: "Arrival", corrected: false)
    ])
    request.options = CapsuleOptions(mode: .period, subject: "September 1976")
    return TimeCapsule(id: id, title: "September ’76", contextLabel: "UK", request: request,
      createdAt: "2026-09-18T00:00:00Z", scenes: (0..<3).map { index in
        CapsuleScene(id: "\(index)", title: "Picture", body: "", dateLabel: "", scope: "", sources: [], trackIndices: [],
          image: CapsuleImage(file: "image-\(index)", sourceUrl: URL(string: "https://example.org")!,
            credit: "Archive", license: "Public domain", licenseUrl: "", date: "1976", description: ""))
      })
  }
}

@MainActor
private final class CinemaStub: CinemaClient {
  var job = CapsuleJob(id: "saved", status: "researching")
  var updatedId: String?
  var updatedOptions: CapsuleOptions?
  var deletedIds: [String] = []
  var deletionError: Error?
  var playedTracks: [[String: String]]?
  var playCount = 0
  var commandCount = 0
  var associatedIds: [String] = []
  var delayLoad = false
  var saved: [TimeCapsule] = []
  var loadContinuation: CheckedContinuation<[TimeCapsule], Never>?
  var artworkContinuation: CheckedContinuation<Data?, Never>?
  var artworkCalls = 0
  var requestedGeneration: String?
  var pollFailure: Error?
  var rebuildCount = 0
  func timeCapsules() async throws -> [TimeCapsule] {
    if delayLoad { return await withCheckedContinuation { loadContinuation = $0 } }
    return saved
  }
  func requireCinemaOptionsSupport() async throws { }
  func requireCinemaManagementSupport() async throws { }
  func createTimeCapsule(_ request: CapsuleRequest) async throws -> CapsuleJob { job }
  func rebuildTimeCapsule(_ id: String) async throws -> CapsuleJob { rebuildCount += 1; return job }
  func updateTimeCapsule(_ id: String, options: CapsuleOptions) async throws -> CapsuleJob {
    updatedId = id; updatedOptions = options; return job
  }
  func deleteTimeCapsule(_ id: String) async throws {
    if let deletionError { throw deletionError }
    deletedIds.append(id)
  }
  func cinemaArtwork(tracks: [CapsuleTrack], zoneId: String) async throws -> Data? {
    artworkCalls += 1
    return await withCheckedContinuation { artworkContinuation = $0 }
  }
  func timeCapsuleJob(_ id: String, generation: String?) async throws -> CapsuleJob {
    requestedGeneration = generation
    if let pollFailure { throw pollFailure }
    return job
  }
  func setTimeCapsule(_ id: String, zoneId: String) async throws { associatedIds.append(id) }
  func playTracks(zoneId: String, tracks: [[String: String]]) async throws -> [SuggestedTrackPayload] {
    playCount += 1; playedTracks = tracks; return []
  }
  func command(_ payload: [String: Any]) async throws { commandCount += 1 }
}
