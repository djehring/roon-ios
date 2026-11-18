import Foundation
#if os(iOS) && canImport(FoundationModels)
import FoundationModels
#endif

/// What a spoken request asks Roon to play, and in which room.
struct MusicPlayRequest: Equatable {
  enum Kind: String, CaseIterable, Sendable {
    case radio, album, artist, playlist, genre
    /// Moods, eras, songs and anything else that needs AI Search.
    case described
  }

  var query: String
  var room: String?
  var kind: Kind?

  /// Roon lookups to try before AI Search. An unknown kind keeps the original
  /// station-then-album order, followed by the other library lookups.
  var lookups: [Kind] {
    switch kind {
    case nil: [.radio, .album, .playlist, .artist, .genre]
    case .described: []
    case let kind?: [kind]
    }
  }
}

enum MusicRequestInterpreter {
  typealias Bridge = @Sendable (String, [String]) async throws -> MusicPlayRequest

  /// Asks the bridge's AI first, then the on-device model when Apple
  /// Intelligence is available. The word-based rules apply when neither
  /// answers in time, or their answer can't be trusted.
  static func interpret(_ raw: String, roomNames: [String], bridge: Bridge? = nil) async -> MusicPlayRequest {
    let raw = SiriMusicRequest.removingAppName(raw)
    let heuristic = MusicRequestHeuristics.interpret(raw, roomNames: roomNames)
    if let bridge {
      do {
        let generated = try await withTimeout(.seconds(6)) { try await bridge(raw, roomNames) }
        SiriMusicTrace.record("interpret.bridge",
          detail: "kind=\(generated.kind?.rawValue ?? "nil"), music=\(generated.query), room=\(generated.room ?? "")")
        if generated.kind != nil {
          return reconcile(generated, heuristic: heuristic, utterance: raw, roomNames: roomNames)
        }
      } catch {
        SiriMusicTrace.record("interpret.bridge.failed", detail: error.localizedDescription)
      }
    }
    #if os(iOS) && canImport(FoundationModels)
    if #available(iOS 26.0, *),
       let generated = await OnDeviceMusicInterpreter.interpret(raw, roomNames: roomNames) {
      return reconcile(generated, heuristic: heuristic, utterance: raw, roomNames: roomNames)
    }
    #endif
    return heuristic
  }

  /// The model may classify the request, but it must not invent music or a
  /// room: both have to come from the words that were actually spoken.
  static func reconcile(
    _ generated: MusicPlayRequest,
    heuristic: MusicPlayRequest,
    utterance: String,
    roomNames: [String]
  ) -> MusicPlayRequest {
    let spoken = tokens(utterance)
    let query = generated.query.trimmingCharacters(in: .whitespacesAndNewlines)
    let queryTokens = tokens(query)
    guard !queryTokens.isEmpty, queryTokens.isSubset(of: spoken) else { return heuristic }

    var room = heuristic.room
    if room == nil, let named = generated.room, !named.isEmpty {
      room = roomNames.first { RoonVoiceMatch.normalize($0) == RoonVoiceMatch.normalize(named) }
        .flatMap { tokens($0).subtracting(["the"]).isDisjoint(with: spoken) ? nil : $0 }
    }
    // The model calls descriptions such as "British jazz from the 1960s" a genre.
    // Roon genre names are one or two words.
    let kind = generated.kind == .genre && queryTokens.count > 2 ? .described : generated.kind
    // AI Search needs the whole description, not the model's shortened version,
    // unless the room is still inside it because only the model recognised it.
    let roomFromModel = heuristic.room == nil && room != nil
    let keepsDescription = kind == .described && !roomFromModel
    return MusicPlayRequest(query: keepsDescription ? heuristic.query : query, room: room, kind: kind)
  }

  private static func tokens(_ text: String) -> Set<String> {
    Set(RoonVoiceMatch.normalize(text).split(separator: " ").map(String.init))
  }
}

enum MusicRequestHeuristics {
  static func interpret(_ raw: String, roomNames: [String]) -> MusicPlayRequest {
    let split = splitRoom(raw, roomNames: roomNames)
    let classified = classify(split.what)
    return MusicPlayRequest(query: classified.query, room: split.room, kind: classified.kind)
  }

  /// Exact room names keep the existing parser. Otherwise "in the kitchen"
  /// names "Kitchen Speakers" when it is the only room with those words, and a
  /// bare trailing room name ("Radio 3 kitchen") must match a room exactly.
  static func splitRoom(_ raw: String, roomNames: [String]) -> (what: String, room: String?) {
    let exact = PlayRequest.parse(raw, roomNames: roomNames)
    if exact.room != nil { return exact }
    let words = exact.what.split(whereSeparator: \.isWhitespace).map(String.init)
    guard words.count >= 2 else { return (exact.what, nil) }
    for length in stride(from: min(3, words.count - 1), through: 1, by: -1) {
      let spoken = words.suffix(length).joined(separator: " ")
      var before = Array(words.dropLast(length))
      if before.last?.lowercased() == "the" { before.removeLast() }
      let hasPreposition = ["in", "on"].contains(before.last?.lowercased() ?? "")
      if hasPreposition { before.removeLast() }
      guard !before.isEmpty else { continue }
      let spokenText = RoonVoiceMatch.normalize(spoken)
      let spokenTokens = Set(spokenText.split(separator: " "))
      let matches = roomNames.filter { room in
        let name = RoonVoiceMatch.normalize(room)
        return hasPreposition ? spokenTokens.isSubset(of: Set(name.split(separator: " "))) : name == spokenText
      }
      if matches.count == 1 { return (before.joined(separator: " "), matches[0]) }
    }
    return (exact.what, nil)
  }

  /// "Play Radio 3" typed or spoken in the Search tab is a command, not a search.
  static func command(_ text: String) -> String? {
    strip(text.trimmingCharacters(in: .whitespacesAndNewlines),
      prefixes: ["play ", "put on ", "listen to "])
  }

  static func classify(_ what: String) -> (kind: MusicPlayRequest.Kind?, query: String) {
    let text = what.trimmingCharacters(in: .whitespacesAndNewlines)
    if let name = strip(text, prefixes: ["the album ", "album "], suffixes: [" album"]) {
      return (.album, name)
    }
    if let name = strip(text, prefixes: ["my playlist ", "the playlist ", "playlist "], suffixes: [" playlist"]) {
      return (.playlist, name)
    }
    if let name = strip(text, prefixes: ["music by ", "songs by ", "tracks by ", "something by ", "the artist ", "artist "]) {
      return (.artist, name)
    }
    if let name = strip(text, prefixes: ["the genre ", "genre "]) {
      return (.genre, name)
    }
    let words = Set(RoonVoiceMatch.normalize(text).split(separator: " "))
    if !words.isDisjoint(with: ["radio", "fm", "bbc"]) || text.lowercased().hasSuffix(" station") {
      return (.radio, strip(text, prefixes: [], suffixes: [" station"]) ?? text)
    }
    return (nil, text)
  }

  private static func strip(_ text: String, prefixes: [String], suffixes: [String] = []) -> String? {
    for prefix in prefixes where text.lowercased().hasPrefix(prefix) && text.count > prefix.count {
      return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
    for suffix in suffixes where text.lowercased().hasSuffix(suffix) && text.count > suffix.count {
      return String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
    }
    return nil
  }
}

#if os(iOS) && canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedMusicRequest {
  @Guide(description: "radio for a broadcast or internet radio station; album; artist; playlist for one of the listener's saved playlists; genre for a single broad genre such as jazz or classical; other for songs, moods, eras and any other description.")
  var kind: GeneratedMusicKind
  @Guide(description: "The station, album, artist, playlist or genre name, or the description of the music, using the listener's words. Leave out the room, the app name, and filler such as play, put on, some or please.")
  var music: String
  @Guide(description: "The room exactly as written in the room list, or an empty string when no room is mentioned.")
  var room: String
}

@available(iOS 26.0, *)
@Generable
enum GeneratedMusicKind {
  case radio, album, artist, playlist, genre, other
}

@available(iOS 26.0, *)
enum OnDeviceMusicInterpreter {
  static func interpret(_ raw: String, roomNames: [String]) async -> MusicPlayRequest? {
    guard SystemLanguageModel.default.isAvailable else { return nil }
    let rooms = roomNames.isEmpty ? "none" : roomNames.joined(separator: ", ")
    let session = LanguageModelSession {
      "You read requests for a Roon home music system and identify what to play and in which room."
      "The rooms are: \(rooms)."
    }
    do {
      let generated = try await withTimeout(.seconds(4)) {
        try await session.respond(to: raw, generating: GeneratedMusicRequest.self).content
      }
      SiriMusicTrace.record("interpret.model", detail: "kind=\(generated.kind), music=\(generated.music), room=\(generated.room)")
      return MusicPlayRequest(query: generated.music, room: generated.room, kind: kind(generated.kind))
    } catch {
      SiriMusicTrace.record("interpret.model.failed", detail: error.localizedDescription)
      return nil
    }
  }

  private static func kind(_ kind: GeneratedMusicKind) -> MusicPlayRequest.Kind {
    switch kind {
    case .radio: .radio
    case .album: .album
    case .artist: .artist
    case .playlist: .playlist
    case .genre: .genre
    case .other: .described
    }
  }
}
#endif

func withTimeout<T: Sendable>(
  _ limit: Duration,
  _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(for: limit)
      throw CancellationError()
    }
    defer { group.cancelAll() }
    guard let result = try await group.next() else { throw CancellationError() }
    return result
  }
}
