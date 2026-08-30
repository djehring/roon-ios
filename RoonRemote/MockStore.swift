import Foundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class MockStore {
  var session: AppSession
  var selectedTab: AppTab = .nowPlaying
  var appearance: Appearance
  var pinDigits = ""
  var pinError = false
  var pairFailure: String?
  var selectedZoneId: String
  var isPlaying: Bool = false
  var showZonePicker = false
  var showVolume = false
  var showQueue = false
  var showStory = false
  var showZonePanel = false
  var zonePanelTab: ZonePanelTab = .switchZone
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
  private var queuesByZone: [String: [QueueItem]] = [:]
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
  var artwork = ArtworkCache(budget: 32 * 1024 * 1024)
  var browseCache: [String: [BrowseNode]] = [:]
  var recordingPath: [String] = []
  var recordingHierarchy: String?
  var houseOutputs: [OutputDescription] = []
  var libraryLaunchHierarchy: String?

  static let shared = MockStore()

  let client = RoonAPIClient()
  private let discovery = BonjourDiscovery()
  private let zoneDefaults = UserDefaults.standard
  private var pinnedTrack: Track?
  private var replacedTrack: Track?
  private var browseChain: Task<Void, Never> = Task {}
  private var coverInFlight = 0
  private var coverWaiters: [CheckedContinuation<Void, Never>] = []
  private var coverPauseCount = 0
  private var coverRequests: Set<ArtworkCache.Key> = []
  // A regular-width grid shows several times the artwork of a phone list, so the
  // throttle that suited one column would leave iPad cells blank far too long.
  private let coverLimit = 6

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
    client.onEventsFailed = { [weak self] error in
      Task { @MainActor in self?.discoveryError = error.localizedDescription }
    }
    if client.isPaired {
      Task { await self.reconnect() }
    }
    #if os(iOS)
    PhoneWatchSync.shared.activate(store: self)
    #endif
    NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.artwork.evictUnpinned() }
    }
    #if DEBUG
    if Self.wantsDemoContent { applyDemoContent() }
    #endif
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
    queuesByZone = [:]
    outputs = []
    session = .onboarding(.localNetwork)
    publishWatchSnapshot()
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
      publishWatchSnapshot()
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
    clearPinnedTrack()
    selectedZoneId = id
    zoneDefaults.set(id, forKey: "selectedZoneId")
    isPlaying = selectedZone.state == .playing
    queue = queuesByZone[id] ?? []
    showZonePicker = false
    publishWatchSnapshot()
  }

  func finishOnboarding() {
    session = .main
    publishWatchSnapshot()
  }

  func resumeSync() {
    guard client.isPaired, session == .main else { return }
    client.refreshEvents()
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
    clearPinnedTrack()
    Task {
      try? await client.command([
        "type": "NEXT",
        "data": ["zone_id": selectedZoneId],
      ])
    }
  }

  func previous() {
    clearPinnedTrack()
    Task {
      try? await client.command([
        "type": "PREVIOUS",
        "data": ["zone_id": selectedZoneId],
      ])
    }
  }

  func stop() {
    clearPinnedTrack()
    Task {
      try? await client.command([
        "type": "STOP",
        "data": ["zone_id": selectedZoneId],
      ])
    }
  }

  func playFromHere(_ item: QueueItem) {
    showNowPlaying(Self.track(from: item), playing: true)
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
    publishWatchSnapshot()
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
    if let index = outputs.firstIndex(where: { $0.id == output.id }) {
      outputs[index].muted.toggle()
    }
    publishWatchSnapshot()
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

  func openZonePanel(tab: ZonePanelTab = .switchZone) {
    prepareGrouping()
    zonePanelTab = tab
    showZonePanel = true
  }

  func prepareGrouping() {
    pendingGroupIds = Set(outputs.map(\.id))
    groupedOutputIds = pendingGroupIds
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
      showZonePanel = false
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
      showZonePanel = false
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
      await withBrowseSession {
        try? await self.client.playItem(
          zoneId: self.selectedZoneId,
          itemKey: key,
          actionTitle: "Play Now"
        )
      }
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
    await withBrowseSession {
      await self.performLoadLibrary(hierarchy: hierarchy, itemKey: itemKey, input: input)
    }
  }

  func playInRoom(query: String, roomName: String, zoneId: String?) async throws -> String {
    guard client.isPaired else { throw PlayInRoomError.unpaired }
    let zones = await waitForZones()
    let zone: Zone
    if let zoneId, let match = zones.first(where: { $0.id == zoneId }) {
      zone = match
    } else if let match = bestZone(named: roomName, in: zones) {
      zone = match
    } else if roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let current = zones.first(where: { $0.id == selectedZoneId }) ?? zones.first
    {
      zone = current
    } else {
      throw PlayInRoomError.noRoom(roomName.isEmpty ? "that room" : roomName)
    }
    selectZone(zone.id)
    let result: Result<String, Error> = await withBrowseSession {
      do {
        return .success(try await self.performPlayQuery(query, zoneId: zone.id))
      } catch {
        return .failure(error)
      }
    }
    return "Playing \(try result.get()) in \(zone.name)."
  }

  func loadActions(hierarchy: String, itemKey: String) async -> [String] {
    if hierarchy == "playlists" {
      return ["Play From Here", "Play Now", "Queue", "Play Next"]
    }
    return ["Play Now", "Queue", "Play Next"]
  }

  func runBrowseAction(
    hierarchy: String,
    itemKey: String,
    title: String,
    hint: String? = nil
  ) {
    Task {
      await withBrowseSession {
        try? await self.executeLibraryAction(
          hierarchy: hierarchy,
          itemKey: itemKey,
          actionTitle: title,
          hint: hint
        )
      }
    }
  }

  /// Plays a library item, preferring playlist "Play From Here" when present.
  func playLibraryItem(hierarchy: String, itemKey: String, hint: String? = nil) {
    let preferred: [String]
    if hierarchy == "playlists" {
      preferred = ["Play From Here", "Play Playlist", "Play Now", "Play"]
    } else {
      preferred = ["Play Now", "Play Album", "Play", "Play Playlist"]
    }
    Task {
      await withBrowseSession {
        for title in preferred {
          do {
            try await self.executeLibraryAction(
              hierarchy: hierarchy,
              itemKey: itemKey,
              actionTitle: title,
              hint: hint
            )
            return
          } catch {
            continue
          }
        }
      }
    }
  }

  private func executeLibraryAction(
    hierarchy: String,
    itemKey: String,
    actionTitle: String,
    hint: String?
  ) async throws {
    // Roon action rows are executed by browsing their item_key — not via play-item.
    if hint == "action" {
      _ = try await client.browse([
        "hierarchy": hierarchy,
        "item_key": itemKey,
        "zone_or_output_id": selectedZoneId,
      ])
      return
    }

    if hint == "action_list" {
      try await browseNamedAction(
        hierarchy: hierarchy,
        itemKey: itemKey,
        actionTitle: actionTitle
      )
      return
    }

    // Container / track: open it in the same hierarchy and run the named action.
    do {
      try await browseNamedAction(
        hierarchy: hierarchy,
        itemKey: itemKey,
        actionTitle: actionTitle
      )
    } catch {
      // Bridge play-item always uses hierarchy "browse"; fine for albums/search, not playlists.
      if hierarchy == "browse" || hierarchy == "albums" || hierarchy == "artists" {
        try await client.playItem(
          zoneId: selectedZoneId,
          itemKey: itemKey,
          actionTitle: actionTitle
        )
      } else {
        throw error
      }
    }
  }

  private func browseNamedAction(
    hierarchy: String,
    itemKey: String,
    actionTitle: String
  ) async throws {
    let page = await performLoadLibrary(
      hierarchy: hierarchy,
      itemKey: itemKey,
      input: nil
    )
    if let key = actionKey(named: actionTitle, in: page.items) {
      _ = try await client.browse([
        "hierarchy": hierarchy,
        "item_key": key,
        "zone_or_output_id": selectedZoneId,
      ])
      return
    }

    let lists = page.items.filter { $0.hint == "action_list" }
    for list in lists {
      guard let listKey = list.itemKey else { continue }
      let actions = await performLoadLibrary(
        hierarchy: hierarchy,
        itemKey: listKey,
        input: nil
      )
      if let key = actionKey(named: actionTitle, in: actions.items) {
        _ = try await client.browse([
          "hierarchy": hierarchy,
          "item_key": key,
          "zone_or_output_id": selectedZoneId,
        ])
        return
      }
    }

    // Playlist/album contents: first row is often a track — open it and look there.
    if let first = page.items.first(where: { $0.hint != "action" && $0.itemKey != nil }),
       let firstKey = first.itemKey,
       firstKey != itemKey
    {
      let nested = await performLoadLibrary(
        hierarchy: hierarchy,
        itemKey: firstKey,
        input: nil
      )
      let nestedTitle =
        actionTitle.lowercased().contains("play") && hierarchy == "playlists"
        ? "Play From Here"
        : actionTitle
      if let key = actionKey(named: nestedTitle, in: nested.items)
        ?? actionKey(named: actionTitle, in: nested.items)
      {
        _ = try await client.browse([
          "hierarchy": hierarchy,
          "item_key": key,
          "zone_or_output_id": selectedZoneId,
        ])
        return
      }
      for list in nested.items where list.hint == "action_list" {
        guard let listKey = list.itemKey else { continue }
        let actions = await performLoadLibrary(
          hierarchy: hierarchy,
          itemKey: listKey,
          input: nil
        )
        if let key = actionKey(named: nestedTitle, in: actions.items)
          ?? actionKey(named: actionTitle, in: actions.items)
        {
          _ = try await client.browse([
            "hierarchy": hierarchy,
            "item_key": key,
            "zone_or_output_id": selectedZoneId,
          ])
          return
        }
      }
    }

    throw PlayInRoomError.notFound(actionTitle)
  }

  private func actionKey(named title: String, in items: [BrowseNode]) -> String? {
    let match = items.first {
      $0.hint == "action"
        && $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
    return match?.itemKey
  }

  private func withBrowseSession<T>(_ work: @escaping () async -> T) async -> T {
    pauseCovers()
    defer { resumeCovers() }
    let previous = browseChain
    let task = Task<T, Never> {
      await previous.value
      return await work()
    }
    browseChain = Task { _ = await task.value }
    return await task.value
  }

  private func performLoadLibrary(
    hierarchy: String,
    itemKey: String?,
    input: String?,
    zoneId: String? = nil
  ) async -> BrowsePage {
    var options: [String: Any] = [
      "hierarchy": hierarchy,
      "zone_or_output_id": zoneId ?? selectedZoneId,
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
      guard let list = browse.list else {
        return BrowsePage(title: browse.message ?? "Couldn't load", items: [])
      }
      let loadOptions: [String: Any] = [
        "hierarchy": hierarchy,
        "level": list.level,
        "count": min(max(list.count, 1), 500),
      ]
      let loaded = try await client.load(loadOptions)
      return BrowsePage(
        title: loaded.list.title,
        items: loaded.items.map { Self.node(from: $0, hierarchy: hierarchy) }
      )
    } catch {
      return BrowsePage(title: "Couldn't load", items: [])
    }
  }

  private func waitForZones() async -> [Zone] {
    if !zones.isEmpty { return zones }
    if client.isPaired {
      client.refreshEvents()
    }
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline {
      if !zones.isEmpty { return zones }
      try? await Task.sleep(nanoseconds: 200_000_000)
    }
    return zones
  }

  private func bestZone(named spoken: String, in zones: [Zone]) -> Zone? {
    let ranked = zones.map { (zone: $0, score: RoonVoiceMatch.score($0.name, query: spoken)) }
    return ranked.max(by: { $0.score < $1.score }).flatMap { $0.score >= 50 ? $0.zone : nil }
  }

  private func performPlayQuery(_ query: String, zoneId: String) async throws -> String {
    if let radio = await findBest(query, hierarchy: "internet_radio", zoneId: zoneId) {
      try await playMatched(radio, hierarchy: "internet_radio", zoneId: zoneId)
      return radio.title
    }
    if let live = await findLiveRadio(query, zoneId: zoneId) {
      try await playMatched(live, hierarchy: "browse", zoneId: zoneId)
      return live.title
    }
    if let albums = try? await client.searchAlbums(zoneId: zoneId, query: query),
       let album = albums.max(by: {
         RoonVoiceMatch.score($0.title, query: query) < RoonVoiceMatch.score($1.title, query: query)
       }),
       RoonVoiceMatch.score(album.title, query: query) >= 50
    {
      try await client.playItem(zoneId: zoneId, itemKey: album.itemKey, actionTitle: "Play Now")
      return album.title
    }
    throw PlayInRoomError.notFound(query)
  }

  private func findBest(_ query: String, hierarchy: String, zoneId: String) async -> BrowseNode? {
    let root = await performLoadLibrary(hierarchy: hierarchy, itemKey: nil, input: nil, zoneId: zoneId)
    if let prompt = root.items.first(where: \.isPrompt), let key = prompt.itemKey {
      let results = await performLoadLibrary(
        hierarchy: hierarchy,
        itemKey: key,
        input: query,
        zoneId: zoneId
      )
      if let match = bestNode(query, in: results.items) { return match }
    }
    if let match = bestNode(query, in: root.items) { return match }
    return nil
  }

  private func findLiveRadio(_ query: String, zoneId: String) async -> BrowseNode? {
    let root = await performLoadLibrary(hierarchy: "browse", itemKey: nil, input: nil, zoneId: zoneId)
    let library = root.items.first { $0.title.compare("Library", options: .caseInsensitive) == .orderedSame }
      ?? root.items.first { $0.title.localizedCaseInsensitiveContains("library") }
    let libraryPage: BrowsePage
    if let library, let key = library.itemKey {
      libraryPage = await performLoadLibrary(hierarchy: "browse", itemKey: key, input: nil, zoneId: zoneId)
    } else {
      libraryPage = root
    }
    guard let live = libraryPage.items.first(where: {
      let title = $0.title.lowercased()
      return title.contains("live radio") || title.contains("internet radio")
    }), let liveKey = live.itemKey else { return nil }
    let stations = await performLoadLibrary(hierarchy: "browse", itemKey: liveKey, input: nil, zoneId: zoneId)
    return bestNode(query, in: stations.items)
  }

  private func bestNode(_ query: String, in items: [BrowseNode]) -> BrowseNode? {
    let ranked = items
      .filter { !$0.isPrompt }
      .map { (node: $0, score: RoonVoiceMatch.score($0.title, query: query)) }
    return ranked.max(by: { $0.score < $1.score }).flatMap { $0.score >= 50 ? $0.node : nil }
  }

  private func playMatched(_ node: BrowseNode, hierarchy: String, zoneId: String) async throws {
    guard let key = node.itemKey else { throw PlayInRoomError.notFound(node.title) }
    if node.hint == "action" {
      _ = try await client.browse([
        "hierarchy": hierarchy,
        "item_key": key,
        "zone_or_output_id": zoneId,
      ])
      return
    }
    let page = await performLoadLibrary(hierarchy: hierarchy, itemKey: key, input: nil, zoneId: zoneId)
    let action = page.items.first(where: { $0.hint == "action" && Self.isPlayAction($0.title) })
      ?? page.items.first(where: { $0.hint == "action" })
    if let action, let actionKey = action.itemKey {
      _ = try await client.browse([
        "hierarchy": hierarchy,
        "item_key": actionKey,
        "zone_or_output_id": zoneId,
      ])
      return
    }
    if let list = page.items.first(where: {
      $0.hint == "action_list" && $0.title.localizedCaseInsensitiveContains("play")
    }), let listKey = list.itemKey {
      let actions = await performLoadLibrary(
        hierarchy: hierarchy,
        itemKey: listKey,
        input: nil,
        zoneId: zoneId
      )
      if let playNow = actions.items.first(where: { Self.isPlayAction($0.title) }),
         let actionKey = playNow.itemKey
      {
        _ = try await client.browse([
          "hierarchy": hierarchy,
          "item_key": actionKey,
          "zone_or_output_id": zoneId,
        ])
        return
      }
    }
    try await client.playItem(zoneId: zoneId, itemKey: key, actionTitle: "Play Now")
  }

  private static func isPlayAction(_ title: String) -> Bool {
    let value = title.lowercased()
    return value == "play now"
      || value == "play"
      || value == "play playlist"
      || value == "play from here"
      || value.contains("play now")
      || value.contains("play from here")
  }

  private enum PlayInRoomError: LocalizedError {
    case unpaired
    case noRoom(String)
    case notFound(String)

    var errorDescription: String? {
      switch self {
      case .unpaired: "Pair this iPhone with your Roon core first."
      case let .noRoom(name): "I couldn't find a room called \(name)."
      case let .notFound(query): "I couldn't find \(query) in Roon."
      }
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
      await withBrowseSession {
        var itemKey: String?
        for (index, title) in action.path.enumerated() {
          let page = await self.performLoadLibrary(
            hierarchy: action.hierarchy,
            itemKey: itemKey,
            input: nil
          )
          guard let match = page.items.first(where: { $0.title == title }) else { return }
          itemKey = match.itemKey
          if index == action.path.count - 1, let itemKey {
            let actionTitle = ["Play Now", "Queue", "Play Next"].indices.contains(action.actionIndex ?? 0)
              ? ["Play Now", "Queue", "Play Next"][action.actionIndex ?? 0]
              : "Play Now"
            try? await self.client.playItem(
              zoneId: self.selectedZoneId,
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

  func imageData(for key: String?, pixels: Int = ArtworkCache.thumbnailPixels) -> Data? {
    guard let key else { return nil }
    let wanted = ArtworkCache.Key(imageKey: key, pixels: pixels)
    if let cached = artwork.data(for: wanted) { return cached }
    Task { await fetchCover(wanted) }
    // Stand in with a smaller copy if we hold one, so hero artwork appears at
    // once and sharpens when the full-size fetch lands.
    let thumbnail = ArtworkCache.Key(imageKey: key, pixels: ArtworkCache.thumbnailPixels)
    return artwork.data(for: thumbnail)
  }

  /// Pins and prefetches the playing track's artwork at both the row and hero
  /// sizes, so a long browse session cannot evict the image Now Playing is
  /// showing.
  private func loadCurrentArtwork(_ imageKey: String?) {
    var keys: Set<ArtworkCache.Key> = []
    if let imageKey {
      for pixels in [ArtworkCache.thumbnailPixels, ArtworkCache.heroPixels] {
        keys.insert(ArtworkCache.Key(imageKey: imageKey, pixels: pixels))
      }
    }
    // Zone events arrive about once a second while playing. Writing the pins
    // every time would dirty `artwork` on each tick and redraw every view that
    // reads artwork, so only write when the playing track has actually changed.
    if artwork.pinnedKeys != keys {
      artwork.setPinned(keys)
    }
    for key in keys {
      Task { await fetchCover(key) }
    }
  }

  private func fetchCover(_ key: ArtworkCache.Key) async {
    guard !artwork.contains(key), !coverRequests.contains(key) else { return }
    coverRequests.insert(key)
    defer { coverRequests.remove(key) }
    await acquireCover()
    defer { releaseCover() }
    guard !artwork.contains(key) else { return }
    let data = try? await client.image(
      imageKey: key.imageKey,
      width: key.pixels,
      height: key.pixels
    )
    if let data {
      artwork.insert(data, for: key)
      publishWatchSnapshot()
    }
  }

  private func pauseCovers() {
    coverPauseCount += 1
  }

  private func resumeCovers() {
    coverPauseCount = max(0, coverPauseCount - 1)
    flushCovers()
  }

  private func acquireCover() async {
    if coverInFlight < coverLimit && coverPauseCount == 0 {
      coverInFlight += 1
      return
    }
    await withCheckedContinuation { coverWaiters.append($0) }
  }

  private func releaseCover() {
    coverInFlight = max(0, coverInFlight - 1)
    flushCovers()
  }

  private func flushCovers() {
    while coverInFlight < coverLimit && coverPauseCount == 0 && !coverWaiters.isEmpty {
      coverInFlight += 1
      coverWaiters.removeFirst().resume()
    }
  }

  func publishWatchSnapshot() {
    #if os(iOS)
    PhoneWatchSync.shared.publish()
    #endif
  }

  func discoverBridges() async {
    isDiscovering = true
    discoveryError = nil
    let results = await discovery.discover()
    let preferred = results.filter { $0.host.hasPrefix("192.168.") }
    discoveredBridges = preferred.isEmpty ? results : preferred
    isDiscovering = false
    if discoveredBridges.count == 1,
       let only = discoveredBridges.first,
       only.host.hasPrefix("192.168.")
    {
      selectBridge(only)
    } else if discoveredBridges.isEmpty {
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
      pairFailure = nil
      session = .onboarding(.waitingForCore)
      await waitForCore()
    } catch RoonAPIError.invalidPIN {
      pinError = true
      pairFailure = "That PIN is wrong. Use the code from web Settings on this Mac."
      pinDigits = ""
    } catch {
      pinError = true
      pairFailure = error.localizedDescription
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
      publishWatchSnapshot()
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
    #if os(iOS)
    RoonSiriSupport.roomsUpdated(zones)
    #endif
    if state.state == .sync, case .onboarding(.waitingForCore) = session {
      session = .onboarding(.chooseZone)
    }
  }

  private func applyZone(_ payload: ZoneStatePayload) {
    let incoming = Self.track(from: payload.nicePlaying)
    let playback = PlaybackState(rawValue: payload.state) ?? .stopped
    let previous = zones.first { $0.id == payload.zoneId }
    let track = chooseTrack(
      incoming: incoming,
      previous: previous?.track,
      playback: playback,
      zoneId: payload.zoneId
    )
    let zone = Zone(id: payload.zoneId, name: payload.displayName, track: track, state: playback)
    if let index = zones.firstIndex(where: { $0.id == payload.zoneId }) {
      var next = zones
      next[index] = zone
      zones = next
    } else {
      zones.append(zone)
    }
    if payload.zoneId == selectedZoneId {
      isPlaying = playback == .playing || playback == .loading
      outputs = payload.outputs.map(Self.output(from:))
      groupedOutputIds = Set(payload.outputs.map(\.outputId))
      pendingGroupIds = groupedOutputIds
      loadCurrentArtwork(track?.imageKey)
    }
    publishWatchSnapshot()
  }

  private func chooseTrack(
    incoming: Track?,
    previous: Track?,
    playback: PlaybackState,
    zoneId: String
  ) -> Track? {
    if zoneId == selectedZoneId, let pinned = pinnedTrack {
      if let incoming {
        if Self.sameSong(incoming, pinned) {
          clearPinnedTrack()
          return incoming
        }
        if let replaced = replacedTrack, Self.sameSong(incoming, replaced) {
          return pinned
        }
        clearPinnedTrack()
        return incoming
      }
      return pinned
    }
    if let incoming {
      return incoming
    }
    if playback == .stopped {
      return nil
    }
    return previous
  }

  private func clearPinnedTrack() {
    pinnedTrack = nil
    replacedTrack = nil
  }

  private func applyQueue(_ payload: QueueStatePayload) {
    let items = payload.tracks.map {
      QueueItem(
        id: $0.id,
        title: $0.title,
        artist: $0.artist ?? "",
        album: $0.disk?.title ?? "",
        imageKey: $0.imageKey
      )
    }
    queuesByZone[payload.zoneId] = items
    if payload.zoneId == selectedZone.id || payload.zoneId == selectedZoneId {
      queue = items
    }
    publishWatchSnapshot()
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

  private func showNowPlaying(_ track: Track, playing: Bool) {
    replacedTrack = selectedZone.track
    pinnedTrack = track
    isPlaying = playing
    if let index = zones.firstIndex(where: { $0.id == selectedZoneId }) {
      var zone = zones[index]
      zone.track = track
      zone.state = playing ? .playing : zone.state
      var next = zones
      next[index] = zone
      zones = next
    }
    loadCurrentArtwork(track.imageKey)
    publishWatchSnapshot()
  }

  private static func track(from item: QueueItem) -> Track {
    Track(
      id: item.id,
      title: item.title,
      artist: item.artist,
      album: item.album,
      position: "0:00",
      remaining: "",
      progress: 0,
      imageKey: item.imageKey
    )
  }

  private static func track(from playing: ZoneNicePlaying?) -> Track? {
    guard let playing else { return nil }
    let album = playing.track.disk?.title ?? playing.track.title
    let remaining = playing.totalQueueRemainingTime ?? playing.track.length ?? ""
    return Track(
      id: [playing.track.title, playing.track.artist ?? "", playing.track.imageKey ?? ""].joined(separator: "|"),
      title: playing.track.title,
      artist: playing.track.artist ?? "",
      album: album,
      position: playing.track.seekPosition ?? "0:00",
      remaining: remaining,
      progress: (playing.track.seekPercentage ?? 0) / 100,
      imageKey: playing.track.imageKey
    )
  }

  private static func sameSong(_ a: Track, _ b: Track) -> Bool {
    a.title == b.title && a.artist == b.artist
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
