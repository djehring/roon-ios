import SwiftUI

@Observable
final class MockStore {
  var session: AppSession = .main
  var selectedTab: AppTab = .nowPlaying
  var appearance: Appearance = .system
  var pinDigits = ""
  var pinError = false
  var selectedZoneId: String
  var isPlaying: Bool
  var showZonePicker = false
  var showVolume = false
  var showQueue = false
  var showTransfer = false
  var showGrouping = false
  var showSharePreview = false
  var isRecordingAction = false
  var searchSegment: SearchSegment = .ai
  var aiQuery = "late night piano trio"
  var aiResults: [SuggestedTrack]
  var aiLoading = false
  var cameraHint = ""
  var hasPhoto = false
  var recognizedAlbums: [BrowseNode]
  var toolbar: [ToolbarAction]
  var customActions: [CustomAction]
  var groupedOutputIds: Set<String>
  var pendingGroupIds: Set<String>

  var zones: [Zone]
  var queue: [QueueItem]
  var outputs: [Output]
  var library: [LibraryEntry]

  init() {
    let living = Zone(
      id: "living",
      name: "Living Room",
      track: Track(
        id: "t1",
        title: "So What",
        artist: "Miles Davis",
        album: "Kind of Blue",
        position: "3:12",
        remaining: "5:48",
        progress: 0.35
      ),
      state: .playing
    )
    self.zones = [
      living,
      Zone(
        id: "kitchen",
        name: "Kitchen",
        track: Track(
          id: "t2",
          title: "Blue in Green",
          artist: "Miles Davis",
          album: "Kind of Blue",
          position: "1:04",
          remaining: "4:21",
          progress: 0.2
        ),
        state: .paused
      ),
      Zone(id: "office", name: "Office", track: nil, state: .stopped),
    ]
    self.selectedZoneId = living.id
    self.isPlaying = true
    self.queue = MockCatalog.queue
    self.outputs = MockCatalog.outputs
    self.library = MockCatalog.library
    self.aiResults = MockCatalog.aiResults
    self.recognizedAlbums = MockCatalog.recognized
    self.toolbar = MockCatalog.toolbar
    self.customActions = MockCatalog.customActions
    self.groupedOutputIds = ["living-main"]
    self.pendingGroupIds = ["living-main"]
  }

  var selectedZone: Zone {
    zones.first { $0.id == selectedZoneId } ?? zones[0]
  }

  var currentTrack: Track? {
    selectedZone.track
  }

  var colorScheme: ColorScheme? {
    switch appearance {
    case .system: nil
    case .dark: .dark
    case .light: .light
    }
  }

  func replayOnboarding() {
    pinDigits = ""
    pinError = false
    session = .onboarding(.localNetwork)
  }

  func advanceOnboarding() {
    guard case let .onboarding(step) = session else { return }
    switch step {
    case .localNetwork:
      session = .onboarding(.findingBridge)
    case .findingBridge:
      session = .onboarding(.pin)
    case .pin:
      session = .onboarding(.waitingForCore)
    case .waitingForCore:
      session = .onboarding(.chooseZone)
    case .chooseZone:
      session = .main
    }
  }

  func submitPin() {
    if pinDigits == "000000" || pinDigits.count != 6 {
      pinError = true
      pinDigits = ""
      return
    }
    pinError = false
    advanceOnboarding()
  }

  func togglePlay() {
    isPlaying.toggle()
    let state: PlaybackState = isPlaying ? .playing : .paused
    if let index = zones.firstIndex(where: { $0.id == selectedZoneId }) {
      zones[index].state = state
    }
  }

  func skip() {
    guard !queue.isEmpty else { return }
    let next = queue.removeFirst()
    if let index = zones.firstIndex(where: { $0.id == selectedZoneId }) {
      zones[index].track = Track(
        id: next.id,
        title: next.title,
        artist: next.artist,
        album: next.album,
        position: "0:00",
        remaining: "4:12",
        progress: 0
      )
      zones[index].state = .playing
      isPlaying = true
    }
  }

  func playFromHere(_ item: QueueItem) {
    if let cut = queue.firstIndex(where: { $0.id == item.id }) {
      queue.removeFirst(cut)
    }
    skip()
  }

  func selectZone(_ id: String) {
    selectedZoneId = id
    isPlaying = selectedZone.state == .playing
    showZonePicker = false
  }

  func runAISearch() {
    aiLoading = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      self.aiResults = MockCatalog.aiResults
      self.aiLoading = false
    }
  }
}

enum MockCatalog {
  static let queue: [QueueItem] = [
    .init(id: "q1", title: "Freddie Freeloader", artist: "Miles Davis",
          album: "Kind of Blue"),
    .init(id: "q2", title: "Blue in Green", artist: "Miles Davis",
          album: "Kind of Blue"),
    .init(id: "q3", title: "All Blues", artist: "Miles Davis",
          album: "Kind of Blue"),
    .init(id: "q4", title: "Flamenco Sketches", artist: "Miles Davis",
          album: "Kind of Blue"),
    .init(id: "q5", title: "Peace Piece", artist: "Bill Evans",
          album: "Everybody Digs Bill Evans"),
  ]

  static let outputs: [Output] = [
    .init(id: "living-main", name: "Living Room", volume: 62,
          min: 0, max: 100, muted: false, isFixed: false),
    .init(id: "living-sub", name: "Subwoofer", volume: 40,
          min: 0, max: 100, muted: false, isFixed: false),
  ]

  static let toolbar: [ToolbarAction] = [
    .init(id: "playlists", label: "Playlists", symbol: "music.note.list"),
    .init(id: "radios", label: "Radios", symbol: "radio"),
  ]

  static let customActions: [CustomAction] = [
    .init(id: "jazz-radio", label: "Jazz Radio", symbol: "dot.radiowaves.left.and.right"),
  ]

  static let aiResults: [SuggestedTrack] = [
    .init(id: "a1", title: "Peace Piece", artist: "Bill Evans",
          album: "Everybody Digs Bill Evans", error: nil, corrected: false),
    .init(id: "a2", title: "Blue in Green", artist: "Miles Davis",
          album: "Kind of Blue", error: nil, corrected: true),
    .init(id: "a3", title: "Crystal Silence", artist: "Gary Burton",
          album: "Crystal Silence", error: "Not in library", corrected: false),
  ]

  static let recognized: [BrowseNode] = [
    .init(id: "r1", title: "Kind of Blue", subtitle: "Miles Davis",
          symbol: "opticaldisc", actions: ["Play Now"], isPrompt: false,
          children: []),
  ]

  static let library: [LibraryEntry] = {
    let playNow = ["Play Now", "Queue", "Play Next", "Start Radio"]
    let albums = BrowseNode(
      id: "albums", title: "Albums", subtitle: nil, symbol: "opticaldisc",
      actions: [], isPrompt: false,
      children: [
        .init(id: "kob", title: "Kind of Blue", subtitle: "Miles Davis",
              symbol: "opticaldisc", actions: playNow, isPrompt: false,
              children: []),
        .init(id: "digs", title: "Everybody Digs Bill Evans",
              subtitle: "Bill Evans", symbol: "opticaldisc",
              actions: playNow, isPrompt: false, children: []),
        .init(id: "search-albums", title: "Search", subtitle: nil,
              symbol: "magnifyingglass", actions: ["Search"],
              isPrompt: true, children: []),
      ]
    )
    return [
      .init(id: "browse", title: "Browse", symbol: "safari",
            root: branch("Browse", "safari", [
              leaf("My Live Radio", "radio.fill"),
              leaf("Playlists", "music.note.list"),
              leaf("Library", "books.vertical"),
            ])),
      .init(id: "library", title: "Library", symbol: "books.vertical",
            root: branch("Library", "books.vertical", [
              leaf("Search", "magnifyingglass", prompt: true),
              albums,
            ])),
      .init(id: "albums", title: "Albums", symbol: "opticaldisc", root: albums),
      .init(id: "artists", title: "Artists", symbol: "person.2",
            root: branch("Artists", "person.2", [
              leaf("Miles Davis", "person"),
              leaf("Bill Evans", "person"),
            ])),
      .init(id: "composers", title: "Composers", symbol: "music.note",
            root: branch("Composers", "music.note", [
              leaf("Gershwin, George", "music.note"),
            ])),
      .init(id: "genres", title: "Genres", symbol: "theatermasks",
            root: branch("Genres", "theatermasks", [
              leaf("Jazz", "theatermasks"),
            ])),
      .init(id: "playlists", title: "Playlists", symbol: "music.note.list",
            root: branch("Playlists", "music.note.list", [
              leaf("Evening", "music.note.list"),
            ])),
      .init(id: "radios", title: "Radios", symbol: "radio",
            root: branch("Radios", "radio", [
              leaf("Jazz 24", "radio.fill"),
            ])),
    ]
  }()

  private static func leaf(
    _ title: String,
    _ symbol: String,
    prompt: Bool = false
  ) -> BrowseNode {
    BrowseNode(
      id: title, title: title, subtitle: nil, symbol: symbol,
      actions: prompt ? ["Search"] : ["Play Now", "Queue", "Play Next"],
      isPrompt: prompt, children: []
    )
  }

  private static func branch(
    _ title: String,
    _ symbol: String,
    _ children: [BrowseNode]
  ) -> BrowseNode {
    BrowseNode(
      id: title, title: title, subtitle: nil, symbol: symbol,
      actions: [], isPrompt: false, children: children
    )
  }
}
