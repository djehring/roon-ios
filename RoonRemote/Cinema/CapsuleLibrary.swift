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
  var preparationMessage = ""
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
    showingLibrary = true
    preparing = true
    error = nil
    preparationMessage = "Researching your request…"
    generation = Task {
      defer { preparing = false }
      do {
        var job = try await client.createTimeCapsule(request)
        let deadline = Date().addingTimeInterval(900)
        while job.status != "ready" && job.status != "failed" {
          guard Date() < deadline else { throw CapsuleFailure("Preparation is taking longer than expected. Reopen Time Capsules to check saved programmes.") }
          preparationMessage = job.status == "images" ? "Finding archive photographs…" : "Researching your request…"
          try await Task.sleep(for: .seconds(3))
          job = try await client.timeCapsuleJob(job.id)
        }
        guard let capsule = job.capsule, !capsule.scenes.isEmpty else {
          throw CapsuleFailure(job.error ?? "No sourced stories were found for this request.")
        }
        capsules.removeAll { $0.id == capsule.id }
        capsules.insert(capsule, at: 0)
        preparationMessage = "Ready to watch"
      } catch is CancellationError {
      } catch { self.error = message(for: error) }
    }
  }

  func watch(_ capsule: TimeCapsule) {
    // The root presents Cinema after the library has dismissed.
    presented = capsule
    showingLibrary = false
  }

  func play(_ capsule: TimeCapsule, zoneId: String, client: RoonAPIClient) async {
    guard !playing, !zoneId.isEmpty else { return }
    playing = true
    error = nil
    defer { playing = false }
    do {
      let missing = try await client.playTracks(zoneId: zoneId, tracks: capsule.request.tracks.map {
        ["artist": $0.artist, "track": $0.track, "album": $0.album]
      })
      // Retain the original programme and identity even if Roon cannot find every track.
      try await client.setTimeCapsule(capsule.id, zoneId: zoneId)
      if !missing.isEmpty {
        error = "Roon could not find \(missing.count) track(s). Available tracks can still play. Choose Watch to join them."
      } else {
        watch(capsule)
      }
    } catch { self.error = message(for: error) }
  }

  func join(zoneId: String, client: RoonAPIClient) async {
    error = nil
    do {
      if let capsule = try await client.zoneTimeCapsule(zoneId) { watch(capsule) }
      else { error = "No Time Capsule is attached to this room yet. Play one from the saved programmes below." }
    } catch { self.error = message(for: error) }
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
