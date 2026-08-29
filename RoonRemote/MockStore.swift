import Foundation
import SwiftUI

@MainActor
@Observable
final class MockStore {
  var session: AppSession
  var selectedTab: AppTab = .nowPlaying
  var appearance: Appearance
  var pinDigits = ""
  var pinError = false
  var selectedZoneId: String
  var isPlaying: Bool = false
  var showZonePicker = false
  var showVolume = false
  var showQueue = false
  var showTransfer = false
  var showGrouping = false
  var showSharePreview = false
  var isRecordingAction = false
  var searchSegment: SearchSegment = .ai
  var aiQuery = ""
  var aiResults: [SuggestedTrack] = []
  var aiLoading = false
  var aiError: String?
  var cameraHint = ""
  var hasPhoto = false
  var recognizedAlbums: [BrowseNode] = []
  var toolbar: [ToolbarAction]
  var customActions: [CustomAction] = []
  var groupedOutputIds: Set<String> = []
  var pendingGroupIds: Set<String> = []
  var zones: [Zone] = []
  var queue: [QueueItem] = []
  var outputs: [Output] = []
  var library: [LibraryEntry]
  var discoveredBridges: [DiscoveredBridge] = []
  var selectedBridge: DiscoveredBridge?
  var manualHost = ""
  var discoveryError: String?
  var isDiscovering = false
  var syncState: RoonSyncState = .starting
  var pairingPinDisplay = ""
  var bridgeVersion = ""
  var storyTitle = ""
  var storyBody = ""
  var storyLoading = false
  var storyError: String?
  var coverCache: [String: Data] = [:]
  var browseCache: [String: [BrowseNode]] = [:]
  var recordingPath: [String] = []
  var recordingHierarchy: String?
  var houseOutputs: [OutputDescription] = []
  var libraryLaunchHierarchy: String?

  let client = RoonAPIClient()
  private let discovery = BonjourDiscovery()
  private let zoneDefaults = UserDefaults.standard

  init() {
    library = Self.libraryRoots
    toolbar = Self.defaultToolbar
    if let stored = zoneDefaults.string(forKey: "appearance"),
       let value = Appearance(rawValue: stored)
    {
      appearance = value
    } else {
      appearance = .system
    }
    selectedZoneId = zoneDefaults.string(forKey: "selectedZoneId") ?? ""
    if let data = zoneDefaults.data(forKey: "toolbar"),
       let saved = try? JSONDecoder().decode([ToolbarAction].self, from: data)
    {
      toolbar = saved
    }
    if client.isPaired {
      session = .main
    } else {
      session = .onboarding(.localNetwork)
    }
    client.onState = { [weak self] state in
      Task { @MainActor in self?.applyState(state) }
    }
    client.onZone = { [weak self] zone in
      Task { @MainActor in self?.applyZone(zone) }
    }
    client.onQueue = { [weak self] queue in
      Task { @MainActor in self?.applyQueue(queue) }
    }
    client.onConfig = { [weak self] config in
      Task { @MainActor in self?.applyConfig(config) }
    }
    if client.isPaired {
      Task { await self.reconnect() }
    }
  }

  var selectedZone: Zone {
    zones.first { $0.id == selectedZoneId } ?? zones.first ?? Zone(
      id: "",
      name: "No zone",
      track: nil,
      state: .stopped
    )
  }

  var currentTrack: Track? { selectedZone.track }

  var colorScheme: ColorScheme? {
    switch appearance {
    case .system: nil
    case .dark: .dark
    case .light: .light
    }
  }

  func replayOnboarding() {
    Task { await client.unpair() }
    pinDigits = ""
    pinError = false
    zones = []
    queue = []
    outputs = []
    session = .onboarding(.localNetwork)
  }

  func advanceOnboarding() {
    guard case let .onboarding(step) = session else { return }
    switch step {
    case .localNetwork:
      session = .onboarding(.findingBridge)
      Task { await discoverBridges() }
    case .findingBridge:
      session = .onboarding(.pin)
    case .pin:
      session = .onboarding(.waitingForCore)
      Task { await waitForCore() }
    case .waitingForCore:
      session = .onboarding(.chooseZone)
    case .chooseZone:
      session = .main
    }
  }

  func useManualHost() {
    let trimmed = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsed = Self.parseHost(trimmed) else {
      discoveryError = "Use host:port, for example 192.168.0.14:3000"
      return
    }
    client.setBridge(host: parsed.host, port: parsed.port)
    selectedBridge = DiscoveredBridge(
      name: parsed.host,
      host: parsed.host,
      port: parsed.port,
      version: nil
    )
    session = .onboarding(.pin)
  }

  func selectBridge(_ bridge: DiscoveredBridge) {
    selectedBridge = bridge
    client.setBridge(host: bridge.host, port: bridge.port)
    session = .onboarding(.pin)
  }

  func submitPin() {
    guard pinDigits.count == 6 else {
      pinError = true
      return
    }
    Task { await pair(pin: pinDigits) }
  }

  func selectZone(_ id: String) {
    selectedZoneId = id
    zoneDefaults.set(id, forKey: "selectedZoneId")
    isPlaying = selectedZone.state == .playing
    showZonePicker = false
  }

  func finishOnboarding() {
    session = .main
  }

  func togglePlay() {
    Task {
      try? await client.command([
        "type": "PLAY_PAUSE",
        "data": ["zone_id": selectedZoneId],
      ])
    }
  }

  func skip() {
    Task {
      try? await client.command([
        "type": "NEXT",
        "data": ["zone_id": selectedZoneId],
      ])
    }
  }

  func previous() {
    Task {
      try? await client.command([
        "type": "PREVIOUS",
        "data": ["zone_id": selectedZoneId],
      ])
    }
  }

  func playFromHere(_ item: QueueItem) {
    Task {
      try? await client.command([
        "type": "PLAY_FROM_HERE",
        "data": ["zone_id": selectedZoneId, "queue_item_id": item.id],
      ])
    }
  }

  func setVolume(_ output: Output, value: Double) {
    if let index = outputs.firstIndex(where: { $0.id == output.id }) {
      outputs[index].volume = value
    }
    Task {
      try? await client.command([
        "type": "VOLUME",
        "data": [
          "zone_id": selectedZoneId,
          "output_id": output.id,
          "strategy": "ABSOLUTE",
          "value": value,
        ],
      ])
    }
  }

  func toggleMute(_ output: Output) {
    Task {
      try? await client.command([
        "type": "MUTE",
        "data": [
          "zone_id": selectedZoneId,
          "output_id": output.id,
          "type": "TOGGLE",
        ],
      ])
    }
  }

  func transfer(to zoneId: String) {
    Task {
      try? await client.command([
        "type": "TRANSFER_ZONE",
        "data": ["zone_id": selectedZoneId, "to_zone_id": zoneId],
      ])
      selectZone(zoneId)
    }
  }

  func openGrouping() {
    pendingGroupIds = Set(outputs.map(\.id))
    groupedOutputIds = pendingGroupIds
    showVolume = false
    showGrouping = true
  }

  var groupableHouseOutputs: [OutputDescription] {
    guard let first = outputs.first else { return [] }
    let inZone = Set(outputs.map(\.id))
    return houseOutputs
      .filter { first.canGroupWith.contains($0.outputId) && !inZone.contains($0.outputId) }
      .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
  }

  func saveGrouping() {
    guard let main = outputs.first else {
      showGrouping = false
      return
    }
    let currentIds = Set(outputs.map(\.id))
    let desired = pendingGroupIds.union([main.id])
    let removed = currentIds.subtracting(desired)
    Task {
      if !removed.isEmpty {
        let ungroup = ([main.id] + Array(removed)).compactMap(outputDescription(for:))
        try? await client.command([
          "type": "GROUP",
          "data": ["outputs": ungroup, "mode": "ungroup"],
        ])
      }
      if desired.count > 1 {
        let group = desired.compactMap(outputDescription(for:))
        if group.count > 1 {
          try? await client.command([
            "type": "GROUP",
            "data": ["outputs": group, "mode": "group"],
          ])
        }
      }
      groupedOutputIds = desired
      showGrouping = false
    }
  }

  func runAISearch() {
    let query = aiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return }
    aiLoading = true
    aiError = nil
    Task {
      do {
        let items = try await client.aiSearch(query: query)
        aiResults = items.map {
          SuggestedTrack(
            id: $0.id,
            title: $0.track,
            artist: $0.artist,
            album: $0.album,
            error: $0.error,
            corrected: $0.wasAutoCorrected ?? false
          )
        }
      } catch RoonAPIError.missingOpenAI {
        aiError = "OpenAI is not configured on the bridge."
      } catch {
        aiError = error.localizedDescription
      }
      aiLoading = false
    }
  }

  func playAIResults() {
    let tracks = aiResults.filter { $0.error == nil }.map {
      ["artist": $0.artist, "album": $0.album, "track": $0.title]
    }
    Task {
      _ = try? await client.playTracks(zoneId: selectedZoneId, tracks: tracks)
    }
  }

  func transcribeAI(audio: Data) {
    Task {
      do {
        aiQuery = try await client.transcribe(audio: audio)
        runAISearch()
      } catch RoonAPIError.missingOpenAI {
        aiError = "OpenAI is not configured on the bridge."
      } catch {
        aiError = error.localizedDescription
      }
    }
  }

  func recognizeAlbum(image: Data?, mimeType: String?) {
    Task {
      do {
        let result = try await client.recognizeAlbum(
          zoneId: selectedZoneId,
          image: image,
          mimeType: mimeType,
          textHint: cameraHint
        )
        hasPhoto = image != nil
        recognizedAlbums = result.libraryResults.map {
          BrowseNode(
            id: $0.itemKey,
            title: $0.title,
            subtitle: $0.subtitle,
            symbol: "opticaldisc",
            actions: ["Play Now"],
            isPrompt: false,
            children: [],
            itemKey: $0.itemKey,
            imageKey: $0.imageKey,
            hierarchy: "albums",
            hint: nil
          )
        }
      } catch RoonAPIError.missingOpenAI {
        aiError = "OpenAI is not configured on the bridge."
      } catch {
        aiError = error.localizedDescription
      }
    }
  }

  func playRecognized(_ album: BrowseNode) {
    guard let key = album.itemKey else { return }
    Task {
      try? await client.playItem(
        zoneId: selectedZoneId,
        itemKey: key,
        actionTitle: "Play Now"
      )
    }
  }

  func loadTrackStory() {
    guard let track = currentTrack else { return }
    storyLoading = true
    storyError = nil
    Task {
      do {
        let story = try await client.trackStory(artist: track.artist, track: track.title)
        storyTitle = story.title
        storyBody = story.content
      } catch RoonAPIError.missingOpenAI {
        storyError = "OpenAI is not configured on the bridge."
      } catch {
        storyError = error.localizedDescription
      }
      storyLoading = false
    }
  }

  func loadLibrary(hierarchy: String, itemKey: String? = nil, input: String? = nil) async -> BrowsePage {
    var options: [String: Any] = [
      "hierarchy": hierarchy,
      "zone_or_output_id": selectedZoneId,
    ]
    if let itemKey {
      options["item_key"] = itemKey
    } else {
      options["pop_all"] = true
      options["set_display_offset"] = true
    }
    if let input {
      options["input"] = input
    }
    do {
      let browse = try await client.browse(options)
      if browse.action == "message" {
        return BrowsePage(title: browse.message ?? "", items: [])
      }
      var loadOptions: [String: Any] = ["hierarchy": hierarchy]
      if let level = browse.list?.level {
        loadOptions["level"] = level
      }
      if let count = browse.list?.count {
        loadOptions["count"] = min(count, 500)
      }
      let loaded = try await client.load(loadOptions)
      return BrowsePage(
        title: loaded.list.title,
        items: loaded.items.map { Self.node(from: $0, hierarchy: hierarchy) }
      )
    } catch {
      return BrowsePage(title: "", items: [])
    }
  }

  func loadActions(hierarchy: String, itemKey: String) async -> [String] {
    let page = await loadLibrary(hierarchy: hierarchy, itemKey: itemKey)
    if page.items.isEmpty {
      return ["Play Now", "Queue", "Play Next"]
    }
    return page.items.map(\.title)
  }

  func runBrowseAction(hierarchy: String, itemKey: String, title: String) {
    Task {
      try? await client.playItem(
        zoneId: selectedZoneId,
        itemKey: itemKey,
        actionTitle: title
      )
    }
  }

  func runToolbar(_ action: ToolbarAction) {
    selectedTab = .library
    libraryLaunchHierarchy = action.hierarchy
  }

  func beginRecordingAction() {
    isRecordingAction = true
    recordingPath = []
    recordingHierarchy = nil
    selectedTab = .library
  }

  func recordBrowseStep(hierarchy: String, title: String) {
    if recordingHierarchy == nil {
      recordingHierarchy = hierarchy
    }
    if recordingPath.last != title {
      recordingPath.append(title)
    }
  }

  func finishRecording(actionTitle: String, actionIndex: Int) {
    let hierarchy = recordingHierarchy ?? "browse"
    let action = CustomAction(
      id: UUID().uuidString,
      label: recordingPath.last ?? actionTitle,
      symbol: "star",
      hierarchy: hierarchy,
      path: recordingPath,
      actionIndex: actionIndex
    )
    customActions.append(action)
    saveCustomActions()
    isRecordingAction = false
    recordingPath = []
    recordingHierarchy = nil
  }

  func cancelRecording() {
    isRecordingAction = false
    recordingPath = []
    recordingHierarchy = nil
  }

  func runCustomAction(_ action: CustomAction) {
    Task {
      var itemKey: String?
      for (index, title) in action.path.enumerated() {
        let page = await loadLibrary(
          hierarchy: action.hierarchy,
          itemKey: itemKey
        )
        if let match = page.items.first(where: { $0.title == title }) {
          itemKey = match.itemKey
          if index == action.path.count - 1, let itemKey {
            let actions = await loadActions(hierarchy: action.hierarchy, itemKey: itemKey)
            let actionTitle = actions.indices.contains(action.actionIndex ?? 0)
              ? actions[action.actionIndex ?? 0]
              : "Play Now"
            try? await client.playItem(
              zoneId: selectedZoneId,
              itemKey: itemKey,
              actionTitle: actionTitle
            )
          }
        }
      }
    }
  }

  func saveToolbar() {
    if let data = try? JSONEncoder().encode(toolbar) {
      zoneDefaults.set(data, forKey: "toolbar")
    }
  }

  func saveAppearance() {
    zoneDefaults.set(appearance.rawValue, forKey: "appearance")
  }

  func refreshPairingPin() {
    Task {
      pairingPinDisplay = (try? await client.pairingPin()) ?? ""
      bridgeVersion = client.version ?? ""
    }
  }

  func rotatePin() {
    Task {
      pairingPinDisplay = (try? await client.rotatePairingPin()) ?? pairingPinDisplay
    }
  }

  func saveCustomActions() {
    let payload: [[String: Any]] = customActions.map {
      var item: [String: Any] = [
        "id": $0.id,
        "label": $0.label,
        "icon": $0.symbol,
        "roonPath": ["hierarchy": $0.hierarchy, "path": $0.path],
      ]
      if let index = $0.actionIndex {
        item["actionIndex"] = index
      }
      return item
    }
    Task { try? await client.sharedConfig(payload) }
  }

  func imageData(for key: String?) -> Data? {
    guard let key else { return nil }
    if let cached = coverCache[key] { return cached }
    Task { await fetchCover(key) }
    return nil
  }

  private func fetchCover(_ key: String) async {
    guard coverCache[key] == nil else { return }
    if let data = try? await client.image(imageKey: key) {
      coverCache[key] = data
    }
  }

  func discoverBridges() async {
    isDiscovering = true
    discoveryError = nil
    let results = await discovery.discover()
    discoveredBridges = results
    isDiscovering = false
    if results.count == 1, let only = results.first {
      selectBridge(only)
    } else if results.isEmpty {
      discoveryError = "No bridge found. Enter the HTTP host and port."
    }
  }

  private func pair(pin: String) async {
    do {
      if selectedBridge == nil, let parsed = Self.parseHost(manualHost) {
        client.setBridge(host: parsed.host, port: parsed.port)
      }
      try await client.pair(pin: pin)
      pinError = false
      session = .onboarding(.waitingForCore)
      await waitForCore()
    } catch {
      pinError = true
      pinDigits = ""
    }
  }

  private func waitForCore() async {
    do {
      try await client.start()
    } catch {
      discoveryError = error.localizedDescription
    }
  }

  private func reconnect() async {
    do {
      try await client.start()
    } catch {
      session = .onboarding(.localNetwork)
    }
  }

  private func applyState(_ state: ApiStatePayload) {
    syncState = state.state
    bridgeVersion = client.version ?? bridgeVersion
    houseOutputs = state.outputs
    if zones.isEmpty {
      zones = state.zones.map {
        Zone(id: $0.zoneId, name: $0.displayName, track: nil, state: .stopped)
      }
    } else {
      for description in state.zones where !zones.contains(where: { $0.id == description.zoneId }) {
        zones.append(Zone(id: description.zoneId, name: description.displayName, track: nil, state: .stopped))
      }
    }
    if selectedZoneId.isEmpty, let first = zones.first {
      selectZone(first.id)
    }
    if state.state == .sync, case .onboarding(.waitingForCore) = session {
      session = .onboarding(.chooseZone)
    }
  }

  private func applyZone(_ payload: ZoneStatePayload) {
    let track = Self.track(from: payload.nicePlaying)
    let playback = PlaybackState(rawValue: payload.state) ?? .stopped
    let zone = Zone(id: payload.zoneId, name: payload.displayName, track: track, state: playback)
    if let index = zones.firstIndex(where: { $0.id == payload.zoneId }) {
      zones[index] = zone
    } else {
      zones.append(zone)
    }
    if payload.zoneId == selectedZoneId {
      isPlaying = playback == .playing
      outputs = payload.outputs.map(Self.output(from:))
      groupedOutputIds = Set(payload.outputs.map(\.outputId))
      pendingGroupIds = groupedOutputIds
      if let key = track?.imageKey {
        Task { await fetchCover(key) }
      }
    }
  }

  private func applyQueue(_ payload: QueueStatePayload) {
    guard payload.zoneId == selectedZoneId else { return }
    queue = payload.tracks.map {
      QueueItem(
        id: $0.id,
        title: $0.title,
        artist: $0.artist ?? "",
        album: $0.disk?.title ?? "",
        imageKey: $0.imageKey
      )
    }
  }

  private func applyConfig(_ config: SharedConfigPayload) {
    customActions = config.customActions.map {
      CustomAction(
        id: $0.id,
        label: $0.label,
        symbol: $0.icon.isEmpty ? "star" : $0.icon,
        hierarchy: $0.roonPath.hierarchy,
        path: $0.roonPath.path,
        actionIndex: $0.actionIndex
      )
    }
  }

  private func outputDescription(for id: String) -> [String: String]? {
    if let output = outputs.first(where: { $0.id == id }) {
      return [
        "output_id": output.id,
        "zone_id": output.zoneId,
        "display_name": output.name,
      ]
    }
    if let output = houseOutputs.first(where: { $0.outputId == id }) {
      return [
        "output_id": output.outputId,
        "zone_id": output.zoneId,
        "display_name": output.displayName,
      ]
    }
    return nil
  }

  private static func track(from playing: ZoneNicePlaying?) -> Track? {
    guard let playing else { return nil }
    let album = playing.track.disk?.title ?? playing.track.title
    let remaining = playing.totalQueueRemainingTime ?? playing.track.length ?? ""
    return Track(
      id: playing.track.imageKey ?? playing.track.title,
      title: playing.track.title,
      artist: playing.track.artist ?? "",
      album: album,
      position: playing.track.seekPosition ?? "0:00",
      remaining: remaining,
      progress: (playing.track.seekPercentage ?? 0) / 100,
      imageKey: playing.track.imageKey
    )
  }

  private static func output(from payload: ZoneOutput) -> Output {
    let volume = payload.volume
    let isFixed = volume?.type == "fixed" || volume == nil
    return Output(
      id: payload.outputId,
      zoneId: payload.zoneId,
      name: payload.displayName,
      volume: volume?.value ?? 0,
      min: volume?.min ?? 0,
      max: volume?.max ?? 100,
      muted: volume?.isMuted ?? false,
      isFixed: isFixed,
      canGroupWith: payload.canGroupWithOutputIds ?? []
    )
  }

  private static func node(from item: BrowseItem, hierarchy: String) -> BrowseNode {
    let prompt = item.inputPrompt != nil
    return BrowseNode(
      id: item.itemKey ?? item.title,
      title: item.title,
      subtitle: item.subtitle,
      symbol: Self.symbol(for: item.hint, title: item.title),
      actions: prompt ? [item.inputPrompt?.action ?? "Search"] : ["Play Now", "Queue", "Play Next"],
      isPrompt: prompt,
      children: [],
      itemKey: item.itemKey,
      imageKey: item.imageKey,
      hierarchy: hierarchy,
      hint: item.hint
    )
  }

  private static func symbol(for hint: String?, title: String) -> String {
    switch hint {
    case "action_list": return "ellipsis.circle"
    case "action": return "play.circle"
    default:
      if title.lowercased().contains("album") { return "opticaldisc" }
      if title.lowercased().contains("artist") { return "person.2" }
      return "music.note"
    }
  }

  private static func parseHost(_ raw: String) -> (host: String, port: Int)? {
    let value = raw
      .replacingOccurrences(of: "http://", with: "")
      .replacingOccurrences(of: "https://", with: "")
    let parts = value.split(separator: ":")
    guard let host = parts.first, !host.isEmpty else { return nil }
    let port = parts.count > 1 ? Int(parts[1]) ?? 3000 : 3000
    return (String(host), port)
  }

  private static let libraryRoots: [LibraryEntry] = [
    .init(id: "browse", title: "Browse", symbol: "safari", hierarchy: "browse"),
    .init(id: "library", title: "Library", symbol: "books.vertical", hierarchy: "browse"),
    .init(id: "albums", title: "Albums", symbol: "opticaldisc", hierarchy: "albums"),
    .init(id: "artists", title: "Artists", symbol: "person.2", hierarchy: "artists"),
    .init(id: "composers", title: "Composers", symbol: "music.note", hierarchy: "composers"),
    .init(id: "genres", title: "Genres", symbol: "theatermasks", hierarchy: "genres"),
    .init(id: "playlists", title: "Playlists", symbol: "music.note.list", hierarchy: "playlists"),
    .init(id: "radios", title: "Radios", symbol: "radio", hierarchy: "internet_radio"),
  ]

  private static let defaultToolbar: [ToolbarAction] = [
    .init(id: "playlists", label: "Playlists", symbol: "music.note.list", hierarchy: "playlists"),
    .init(id: "radios", label: "Radios", symbol: "radio", hierarchy: "internet_radio"),
  ]
}
