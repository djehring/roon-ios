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
      || title == "start radio"
  }
}

/// Executes one collection suffix in the store's serialized browse session.
enum BrowseTrackPlayback {
  @MainActor
  static func play(
    _ tracks: [BrowseNode],
    actions: (BrowseNode) async throws -> [BrowseNode],
    execute: (BrowseNode) async throws -> Void
  ) async throws {
    for (index, track) in tracks.enumerated() {
      try Task.checkCancellation()
      let available = try await actions(track)
      func action(named title: String) -> BrowseNode? {
        available.first {
          $0.hint == "action" && $0.itemKey != nil
            && $0.title.compare(title, options: .caseInsensitive) == .orderedSame
        }
      }
      if index == 0, let native = action(named: "Play From Here") {
        try await execute(native)
        return
      }
      let title = index == 0 ? "Play Now" : "Queue"
      guard let selected = action(named: title) else {
        throw RoonAPIError.browseAction("“\(title)” is unavailable for “\(track.listedTitle)”.")
      }
      try await execute(selected)
    }
  }

  /// Read every page before starting playback; never silently truncate a playlist.
  static func loadCollection(
    first: LoadResponse,
    load: (Int, Int) async throws -> LoadResponse
  ) async throws -> [BrowseItem] {
    var items = first.items
    guard first.offset == 0 else { throw changedCollection }
    while items.count < first.list.count {
      let next = try await load(items.count, min(500, first.list.count - items.count))
      guard next.offset == items.count, next.list.count == first.list.count,
            next.list.level == first.list.level, next.list.title == first.list.title,
            !next.items.isEmpty else { throw changedCollection }
      items += next.items
    }
    guard items.count == first.list.count else { throw changedCollection }
    return items
  }

  private static var changedCollection: RoonAPIError {
    .browseAction("The collection changed while loading. Please reopen it and try again.")
  }
}
