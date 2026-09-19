import Foundation
import Observation

/// Shared by the phone, regular-width and TV shells. The operation owns the
/// browse session; feedback survives the switch from browsing to Now Playing.
@MainActor
@Observable
final class BrowsePlayback {
  struct Feedback: Equatable {
    let title: String
    let room: String
    let isLoading: Bool
  }

  private(set) var feedback: Feedback?
  private(set) var isRunning = false
  var error: String?

  func run(
    actionTitle: String,
    room: String,
    feedbackDuration: Duration = .milliseconds(650),
    operation: () async throws -> Void,
    showNowPlaying: () -> Void
  ) async {
    // Repeated taps must not enqueue several copies of an album or playlist.
    guard !isRunning else { return }
    isRunning = true
    error = nil
    let startsPlayback = Self.startsPlayback(actionTitle)
    feedback = Feedback(
      title: startsPlayback ? "Starting playback…" : "Updating queue…",
      room: room,
      isLoading: true
    )
    defer {
      feedback = nil
      isRunning = false
    }

    do {
      try await operation()
      feedback = Feedback(
        title: startsPlayback ? "Playback started" : "Queue updated",
        room: room,
        isLoading: false
      )
      // Make the acknowledgement visible before changing screens.
      try await Task.sleep(for: feedbackDuration)
      if startsPlayback { showNowPlaying() }
      try await Task.sleep(for: feedbackDuration)
    } catch is CancellationError {
      return
    } catch {
      self.error = error.localizedDescription
    }
  }

  static func startsPlayback(_ title: String) -> Bool {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    // Queue actions can contain "play" too (notably Play Next).
    guard !title.contains("queue"), !title.contains("next") else { return false }
    return title == "play" || title.hasPrefix("play ")
      || title == "shuffle" || title.hasPrefix("shuffle ")
  }
}
