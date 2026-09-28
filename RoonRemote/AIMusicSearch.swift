import Foundation

/// Siri AI sometimes sends a complete utterance, including the app name, and
/// sometimes sends just a follow-up room. Neither is a new music description.
struct SiriMusicRequest {
  var query: String
  var roomName: String?
  var isFollowUp: Bool

  static func parse(_ raw: String, roomNames: [String]) -> Self {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let suffix = #"\s+(?:with|using|on|in)\s+(?:the\s+)?House\s+Remote(?:\s+app)?[.!?]?$"#
    text = text.replacingOccurrences(of: suffix, with: "", options: [.regularExpression, .caseInsensitive])
    for room in roomNames.sorted(by: { $0.count > $1.count }) {
      if [room, "in \(room)", "in the \(room)", "on \(room)", "on the \(room)"].contains(where: {
        text.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
      }) {
        return Self(query: "", roomName: room, isFollowUp: true)
      }
    }
    let parsed = PlayRequest.parse(text, roomNames: roomNames)
    let followUps: Set<String> = ["", "play", "play it", "play that", "play them", "play those",
      "play the music", "play the results", "play these results", "play those results", "it", "that", "them", "those"]
    return Self(query: parsed.what, roomName: parsed.room,
      isFollowUp: followUps.contains(parsed.what.lowercased()))
  }
}

/// The UI and Siri use the same bridge results and playback failure handling.
enum AIMusicSearch {
  static func search(
    _ query: String,
    using search: (String) async throws -> [SuggestedTrackPayload]
  ) async throws -> [SuggestedTrack] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { throw SiriMusicError.emptyQuery }
    try Task.checkCancellation()
    let results = try await search(query)
    try Task.checkCancellation()
    return results.map {
      SuggestedTrack(id: $0.id, title: RoonDisplayText.format($0.track),
        artist: RoonDisplayText.format($0.artist), album: RoonDisplayText.format($0.album),
        error: $0.error, corrected: $0.wasAutoCorrected ?? false)
    }
  }

  static func play(
    _ tracks: [SuggestedTrack], zoneId: String,
    using play: (String, [[String: String]]) async throws -> [SuggestedTrackPayload]
  ) async throws -> Playback {
    let playable = tracks.filter { $0.error == nil }
    guard !playable.isEmpty else { throw SiriMusicError.noResults }
    try Task.checkCancellation()
    let unfound = try await play(zoneId, playable.map {
      ["artist": $0.artist, "album": $0.album, "track": $0.title]
    })
    SiriMusicTrace.record("bridge.play.response", detail: "submitted=\(playable.count), unfound=\(unfound.count)")
    guard !AISearchPlayback.allFailed(playable: playable, unfound: unfound) else {
      throw SiriMusicError.unplayable
    }
    var results = tracks
    let warning = AISearchPlayback.applyUnfound(unfound, to: &results)
      ?? (tracks.contains { $0.error != nil } ? "Some tracks could not be played." : nil)
    return Playback(tracks: results, warning: warning)
  }

  struct Playback {
    var tracks: [SuggestedTrack]
    var warning: String?

    func dialog(room: String) -> String {
      let count = tracks.filter { $0.error == nil }.count
      let playing = count == 1 ? "Playing 1 track in \(room)." : "Playing \(count) tracks in \(room)."
      return warning == nil ? playing : "\(playing) Some tracks could not be played."
    }
  }
}

/// A bounded, device-local trace for development builds. It deliberately omits
/// bridge credentials and can be retrieved without collecting system logs.
enum SiriMusicTrace {
  private static let lock = NSLock()

  static func record(_ event: String, detail: String = "") {
    #if DEBUG
    lock.lock()
    defer { lock.unlock() }
    let file = URL.applicationSupportDirectory.appending(path: "Siri/diagnostics.json")
    var records: [[String: String]] = (try? Data(contentsOf: file))
      .flatMap { try? JSONDecoder().decode([[String: String]].self, from: $0) } ?? []
    records.append(["time": ISO8601DateFormatter().string(from: Date()), "event": event, "detail": String(detail.prefix(500))])
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(Array(records.suffix(100))) {
      try? data.write(to: file, options: .atomic)
    }
    #endif
  }
}

enum SiriMusicError: LocalizedError, CustomLocalizedStringResourceConvertible {
  case emptyQuery, noResults, unplayable, expiredSelection, busy, unsupportedPlayback, roomRequired
  case playbackNotConfirmed(String)
  case missingMusicContext

  var localizedStringResource: LocalizedStringResource {
    LocalizedStringResource(stringLiteral: errorDescription ?? "The music request could not be completed.")
  }

  var errorDescription: String? {
    switch self {
    case .emptyQuery: "Tell me what music you would like to find."
    case .noResults: "AI Search didn't return any playable tracks. Try a different music request."
    case .unplayable: "Roon couldn't play any of the suggested tracks."
    case .expiredSelection: "Those music results are no longer available. Please search again."
    case .busy: "An AI search is already running in House Remote. Please try again when it finishes."
    case .unsupportedPlayback: "This action supports playing now. Use House Remote for other queue or repeat options."
    case .roomRequired: "Which room should I play the music in? Include its name, for example, jazz in Office."
    case .missingMusicContext: "Tell me what music to play and the room, for example, British jazz from the 1960s in Office."
    case .playbackNotConfirmed(let room): "Roon hasn't confirmed that the requested music is playing in \(room). Check the room in House Remote."
    }
  }
}

/// Preserve the actual search results across Siri's resolution and playback
/// processes; replaying an entity must not run a different AI search.
struct SiriMusicSelection: Codable, Identifiable {
  var id = UUID().uuidString
  var context: CapsuleSearchContext
  var tracks: [SuggestedTrack]
  var zoneId: String
  var roomName: String
  var bridgeScope: String
  // Older cached results may contain a room chosen implicitly by the app.
  // Only a room explicitly supplied by the user is eligible for playback.
  var roomWasExplicit: Bool? = nil

  var hasRoom: Bool { roomWasExplicit == true && !zoneId.isEmpty && !roomName.isEmpty }

  func inRoom(_ zone: Zone) -> Self {
    var selection = self
    selection.zoneId = zone.id
    selection.roomName = zone.name
    selection.roomWasExplicit = true
    return selection
  }
}

@MainActor
final class SiriMusicSelections {
  static let shared = SiriMusicSelections(fileURL: URL.applicationSupportDirectory
    .appending(path: "Siri/music-results.json"))

  private let fileURL: URL
  private let limit = 20

  init(fileURL: URL) { self.fileURL = fileURL }

  func save(_ selection: SiriMusicSelection) throws {
    var selections = load().filter { $0.id != selection.id }
    selections.insert(selection, at: 0)
    let data = try JSONEncoder().encode(Array(selections.prefix(limit)))
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
  }

  func selection(id: String, bridgeScope: String) -> SiriMusicSelection? {
    load().first { $0.id == id && $0.bridgeScope == bridgeScope }
  }

  /// A short follow-up such as "play that in Office" must keep the music from
  /// the current conversation. Never resurrect an old search from another bridge.
  func recentMusicSelection(bridgeScope: String, roomNames: [String], now: Date = Date()) -> SiriMusicSelection? {
    load().first { selection in
      guard selection.bridgeScope == bridgeScope,
        !SiriMusicRequest.parse(selection.context.query, roomNames: roomNames).isFollowUp,
        let date = ISO8601DateFormatter().date(from: selection.context.requestedAt)
      else { return false }
      let age = now.timeIntervalSince(date)
      return age >= 0 && age <= 300
    }
  }

  /// Siri may repeat resolution several times within one interaction. Keep the
  /// same ID and tracks during that interaction instead of regenerating music.
  func recentSelection(query: String, zoneId: String, bridgeScope: String, now: Date = Date()) -> SiriMusicSelection? {
    load().first { selection in
      guard selection.zoneId == zoneId, selection.bridgeScope == bridgeScope,
            selection.context.query.compare(query, options: .caseInsensitive) == .orderedSame,
            let date = ISO8601DateFormatter().date(from: selection.context.requestedAt)
      else { return false }
      let age = now.timeIntervalSince(date)
      return age >= 0 && age <= 120
    }
  }

  private func load() -> [SiriMusicSelection] {
    guard let data = try? Data(contentsOf: fileURL),
          let selections = try? JSONDecoder().decode([SiriMusicSelection].self, from: data)
    else { return [] }
    return selections
  }
}

enum SiriPlaybackConfirmation {
  static func isPlaying(_ zone: Zone?, tracks: [SuggestedTrack], eventAt: Date?, requestedAt: Date) -> Bool {
    guard let zone, zone.state == .playing, let current = zone.track,
          let eventAt, eventAt >= requestedAt else { return false }
    return tracks.contains {
      $0.error == nil && RoonVoiceMatch.titlesMatch(current.title, $0.title)
        && AISearchPlayback.artistsAlign($0.artist, current.artist)
    }
  }
}
