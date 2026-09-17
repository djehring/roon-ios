import Foundation
import Observation

@MainActor
@Observable
final class CapsuleLibrary {
  var capsules: [TimeCapsule] = []
  var showingLibrary = false
  var presented: TimeCapsule?
  var preparing = false
  var loading = false
  var playing = false
  var opening = false
  var libraryAfterViewer = false
  var playbackMemory = MontagePlaybackMemory()
  var playbackCapsuleId: String?
  var playbackMessage: String?
  var preparationMessage = ""
  var preparationError: String?
  var preparation: CapsulePreparation?
  var error: String?
  @ObservationIgnored private var generation: Task<Void, Never>?

  func load(client: RoonAPIClient) async {
    guard !loading else { return }
    loading = true
    defer { loading = false }
    do {
      capsules = try await client.timeCapsules()
      error = nil
    } catch { self.error = message(for: error) }
  }

  func create(context: CapsuleSearchContext, tracks: [SuggestedTrack], client: RoonAPIClient) {
    guard !preparing else { showingLibrary = true; return }
    let request = CapsuleRequest(context: context, tracks: tracks)
    guard !request.tracks.isEmpty else { return }
    prepare(request: request, client: client) { try await client.createTimeCapsule(request) }
  }

  func rebuild(_ capsule: TimeCapsule, client: RoonAPIClient) {
    guard !preparing else { return }
    prepare(request: capsule.request, client: client) { try await client.rebuildTimeCapsule(capsule.id) }
  }

  private func prepare(request: CapsuleRequest, client: RoonAPIClient, start: @escaping () async throws -> CapsuleJob) {
    showingLibrary = true
    preparing = true
    preparationError = nil
    preparation = CapsulePreparation(request: request)
    error = nil
    preparationMessage = "Finding the events behind your music…"
    generation = Task {
      defer { preparing = false }
      do {
        var job = try await start()
        let deadline = Date().addingTimeInterval(900)
        while job.status != "ready" && job.status != "failed" {
          guard Date() < deadline else { throw CapsuleFailure("Preparation is taking longer than expected. Reopen Time Capsules to check saved montages.") }
          preparationMessage = job.status == "images" ? "Gathering photographs for the montage…" : "Researching the requested period…"
          try await Task.sleep(for: .seconds(3))
          job = try await client.timeCapsuleJob(job.id)
        }
        guard let capsule = job.capsule else {
          throw CapsuleFailure(job.error ?? "No photo montage could be prepared for this request.")
        }
        capsules.removeAll { $0.id == capsule.id }
        capsules.insert(capsule, at: 0)
        preparation?.result = capsule
        preparationMessage = "Montage ready"
      } catch is CancellationError {
      } catch { self.preparationError = message(for: error) }
    }
  }

  func watch(_ capsule: TimeCapsule) {
    // The root presents Cinema after the library has dismissed.
    presented = capsule
    showingLibrary = false
  }

  func open(zoneId: String, current: Track?, queue: [QueueItem], client: RoonAPIClient) async {
    guard !opening else { return }
    guard !preparing, preparationError == nil else {
      if let pending = preparation?.placeholder { watch(pending) }
      else { showingLibrary = true }
      return
    }
    opening = true
    error = nil
    defer { opening = false }
    do {
      let associated = zoneId.isEmpty ? nil : try await client.zoneTimeCapsule(zoneId)
      capsules = try await client.timeCapsules()
      guard preparationError == nil else { showingLibrary = true; return }
      if let capsule = CapsuleNowPlaying.select(preparing: preparing, current: current, queue: queue,
        associated: associated, saved: capsules) {
        watch(capsule)
      } else {
        showingLibrary = true
      }
    } catch {
      self.error = message(for: error)
      showingLibrary = true
    }
  }

  func playPreparation(zoneId: String, current: Track?, queue: [QueueItem], isPlaying: Bool,
    client: RoonAPIClient) async {
    guard let pending = preparation?.placeholder else { return }
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

  func play(_ capsule: TimeCapsule, zoneId: String, client: RoonAPIClient, associate: Bool = true) async {
    guard !playing, !zoneId.isEmpty else { return }
    playing = true
    playbackCapsuleId = capsule.id
    playbackMessage = "Starting music..."
    error = nil
    watch(capsule)
    defer { playing = false }
    do {
      let missing = try await client.playTracks(zoneId: zoneId, tracks: capsule.request.tracks.map {
        ["artist": $0.artist, "track": $0.track, "album": $0.album]
      })
      // Retain the original programme and identity even if Roon cannot find every track.
      if associate { try await client.setTimeCapsule(capsule.id, zoneId: zoneId) }
      playbackMessage = missing.isEmpty ? nil
        : "\(missing.count) of \(capsule.request.tracks.count) tracks unavailable. Pictures will continue."
    } catch {
      playbackMessage = "Music could not start: \(message(for: error))"
    }
  }

  private func message(for error: Error) -> String {
    if case RoonAPIError.httpStatus(404, _) = error {
      return "This bridge does not support Time Capsules yet. Update the bridge to enable them."
    }
    return error.localizedDescription
  }
}

private struct CapsuleFailure: LocalizedError {
  var detail: String
  init(_ detail: String) { self.detail = detail }
  var errorDescription: String? { detail }
}
