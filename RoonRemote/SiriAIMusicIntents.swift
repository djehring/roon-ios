import AppIntents
import Foundation
import MediaIntents

/// Also available on iOS 18–26, where Siri prompts for the free-form query.
struct SearchAIMusicIntent: AppIntent {
  static var title: LocalizedStringResource = "Search music with AI"
  static var description = IntentDescription("Find music using House Remote's AI Search and review the results in the app.")
  static var openAppWhenRun = true

  @Parameter(title: "Music request", requestValueDialog: "What music would you like to find?")
  var query: String

  static var parameterSummary: some ParameterSummary {
    Summary("Search for \(\.$query)")
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    try MockStore.shared.showAISearchFromSiri(query)
    return .result()
  }
}

@available(iOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SiriAISearchIntent: ShowInAppSearchResultsIntent {
  static var title: LocalizedStringResource = "Find music"
  static var searchScopes: [StringSearchScope] = [.general]
  static var supportedModes: IntentModes { .foreground }
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  var criteria: StringSearchCriteria

  @MainActor
  func perform() async throws -> some IntentResult {
    try MockStore.shared.showAISearchFromSiri(criteria.term)
    return .result()
  }
}

/// One collection represents the complete ordered AI result list, rather than
/// returning independent songs for Siri to choose just one of them.
@available(iOS 27.0, *)
@AppEntity(schema: .audio.songCollection)
struct SiriMusicCollection: AppEntity {
  static var defaultQuery = SiriMusicCollectionQuery()
  let id: String
  var title: String?
  var roomName: String

  var displayRepresentation: DisplayRepresentation {
    let music = title ?? "AI music results"
    return DisplayRepresentation(title: "\(music)",
      subtitle: "\(roomName.isEmpty ? "Choose a room" : roomName)")
  }

  init(_ selection: SiriMusicSelection) {
    id = selection.id
    roomName = selection.roomName
    title = selection.roomName.isEmpty ? selection.context.query
      : "\(selection.context.query) in \(selection.roomName)"
  }
}

@available(iOS 27.0, *)
struct SiriMusicCollectionQuery: EntityStringQuery {
  // The paired bridge and result cache belong to the main app. Resolution must
  // use that process too, rather than relying on the system's target heuristic.
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  @MainActor
  func entities(for identifiers: [String]) async throws -> [SiriMusicCollection] {
    SiriMusicTrace.record("collection.resolve", detail: identifiers.joined(separator: ", "))
    let scope = MockStore.shared.siriMusicBridgeScope
    return identifiers.compactMap { id in
      SiriMusicSelections.shared.selection(id: id, bridgeScope: scope).map(SiriMusicCollection.init)
    }
  }

  @MainActor
  func entities(matching string: String) async throws -> [SiriMusicCollection] {
    SiriMusicTrace.record("collection.match", detail: string)
    do {
      return [SiriMusicCollection(try await MockStore.shared.searchMusicForSiri(string))]
    } catch let error as SiriMusicError {
      throw AppIntentError(wrapping: error)
    }
  }
}

// The audio schema requires a union value even when the app currently exposes
// just one kind of audio item.
@available(iOS 27.0, *)
@UnionValue
enum SiriMusicAudioItem {
  case collection(SiriMusicCollection)
}

@available(iOS 27.0, *)
struct SiriMusicAudioQuery: IntentValueQuery {
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  @MainActor
  func values(for input: AudioSearch) async throws -> [SiriMusicAudioItem] {
    SiriMusicTrace.record("audio.query", detail: String(describing: input.criteria))
    switch input.criteria {
    case .searchQuery(let query):
      // Forward the complete music description to AI Search once. Room
      // disambiguation belongs to playback, not to music search results.
      return try await SiriMusicCollectionQuery().entities(matching: query).map {
        .collection($0)
      }
    case .unspecified, .url:
      // No catalog URL mapping or personal recommendations: do not fabricate a
      // match or send an arbitrary URL to AI Search.
      return []
    @unknown default:
      return []
    }
  }
}

@available(iOS 27.0, *)
@AppEnum(schema: .audio.playbackAttributes)
enum SiriMusicPlaybackAttribute: String, AppEnum {
  case shuffle
  case `repeat`
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .shuffle: "Shuffle", .repeat: "Repeat",
  ]
}

@available(iOS 27.0, *)
@AppEnum(schema: .audio.queueInsertionLocation)
enum SiriMusicQueueLocation: String, AppEnum {
  case next, tail
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .next: "Play next", .tail: "Play last",
  ]
}

@available(iOS 27.0, *)
@AppEntity(schema: .audio.warmupAudioQueueResult)
struct SiriMusicWarmupResult: TransientAppEntity {
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Music queue") }
}

@available(iOS 27.0, *)
@AppIntent(schema: .audio.playAudio)
struct PlayAIMusicIntent: AudioPlaybackIntent, LongRunningIntent, CancellableIntent {
  static var title: LocalizedStringResource = "Play music in a Roon room"
  static var description = IntentDescription("Send the AI Search track list to the paired Roon bridge for playback in a named Roon room.")
  static var supportedModes: IntentModes { .background }
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  var audioEntity: SiriMusicAudioItem
  @Parameter(default: [])
  var playbackAttributes: Set<SiriMusicPlaybackAttribute>
  var queueLocation: SiriMusicQueueLocation?
  var warmupAudioQueueResult: SiriMusicWarmupResult?

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    SiriMusicTrace.record("audio.play.perform", detail: "attributes=\(playbackAttributes), queue=\(String(describing: queueLocation)), warmup=\(warmupAudioQueueResult != nil)")
    guard queueLocation == nil, !playbackAttributes.contains(.repeat), warmupAudioQueueResult == nil else {
      throw SiriMusicError.unsupportedPlayback
    }
    let store = MockStore.shared
    let collection: SiriMusicCollection
    switch audioEntity {
    case .collection(let value): collection = value
    }
    guard var selection = SiriMusicSelections.shared.selection(id: collection.id, bridgeScope: store.siriMusicBridgeScope) else {
      throw SiriMusicError.expiredSelection
    }
    if !selection.hasRoom {
      SiriMusicTrace.record("audio.room.requested")
      let choices = try await store.siriRoomChoices(for: selection)
      let items = choices.map { SiriMusicAudioItem.collection(SiriMusicCollection($0)) }
      let chosen: SiriMusicAudioItem
      if items.count == 1 {
        guard try await $audioEntity.requestConfirmation(for: items[0],
          dialog: "Play the music in \(choices[0].roomName)?") else { throw CancellationError() }
        chosen = items[0]
      } else {
        chosen = try await $audioEntity.requestDisambiguation(among: items,
          dialog: "Which room should I play the music in?")
      }
      let chosenID: String
      switch chosen {
      case .collection(let value): chosenID = value.id
      }
      guard let resolved = choices.first(where: { $0.id == chosenID }) else {
        throw SiriMusicError.expiredSelection
      }
      selection = resolved
    }
    SiriMusicTrace.record("audio.room.selected", detail: selection.roomName)
    let resolvedSelection = selection
    let dialog: String
    do {
      dialog = try await performBackgroundTask {
        self.progress.totalUnitCount = 1
        self.progress.completedUnitCount = 0
        self.progress.localizedDescription = "Finding and playing music in Roon"
        let startedAt = Date()
        // The bridge exposes one long request, not per-track progress. Report
        // elapsed waiting time honestly; never invent a completion percentage.
        let updates = Task { @MainActor in
          while !Task.isCancelled {
            self.progress.localizedAdditionalDescription = "Waiting for Roon: \(Int(Date().timeIntervalSince(startedAt))) seconds"
            try await Task.sleep(for: .seconds(5))
          }
        }
        defer { updates.cancel() }
        // This is a remote-control command: the store posts the captured tracks
        // and zone ID to the Roon bridge. It never renders these tracks locally.
        let spoken = try await store.playSiriMusicSelection(resolvedSelection, shuffled: self.playbackAttributes.contains(.shuffle))
        self.progress.completedUnitCount = 1
        self.progress.localizedAdditionalDescription = "Playback confirmed"
        return spoken
      } onCancel: { reason in
        SiriMusicTrace.record("audio.play.cancelled", detail: String(describing: reason))
      }
      SiriMusicTrace.record("audio.play.success", detail: dialog)
    } catch {
      SiriMusicTrace.record("audio.play.error", detail: error.localizedDescription)
      throw error
    }
    return .result(dialog: IntentDialog(stringLiteral: dialog))
  }
}
