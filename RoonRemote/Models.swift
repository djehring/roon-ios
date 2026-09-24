import Foundation

enum PlaybackState: String {
  case playing
  case paused
  case stopped
  case loading
}

struct Track: Identifiable, Hashable {
  let id: String
  var title: String
  var artist: String
  var album: String
  var position: String
  var remaining: String
  var progress: Double
  var imageKey: String?
  /// Total track length in seconds when known (needed for absolute seek).
  var durationSeconds: Double? = nil

  var isSeekable: Bool {
    (durationSeconds ?? 0) > 0
  }
}

struct Zone: Identifiable, Hashable {
  let id: String
  var name: String
  var track: Track?
  var state: PlaybackState
}

struct QueueItem: Identifiable, Hashable {
  let id: String
  var title: String
  var artist: String
  var album: String
  var imageKey: String?
}

struct Output: Identifiable, Hashable {
  let id: String
  var zoneId: String
  var name: String
  var volume: Double
  var min: Double
  var max: Double
  var muted: Bool
  var isFixed: Bool
  var canGroupWith: [String]
}

struct BrowsePage: Hashable {
  var title: String
  var items: [BrowseNode]
  var musicSource: CinemaMusicPath? = nil
  var errorMessage: String? = nil

  /// The key for the row named `title`, for a sidebar entry that has to step
  /// one level into a hierarchy to reach what it is named after.
  ///
  /// Matching on the title is the only option: Roon mints item keys per browse
  /// session, so there is nothing stable to hardcode.
  func itemKey(forChildTitled title: String) -> String? {
    items.first { $0.title == title }?.itemKey
  }
}

/// Resolve fresh browse keys when opened; Roon's item keys belong to a session.
struct ArtistDiscography: Hashable {
  let token = UUID()
  let name: String

  init?(_ artist: String) {
    let name = RoonDisplayText.format(artist).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    self.name = name
  }

  @MainActor
  func load(using browse: (String?, String?) async -> BrowsePage) async -> BrowsePage {
    let query = ArtistCredits.searchQuery(name)
    var results = await browse(nil, query)
    if results.errorMessage != nil { return results }
    // The artist page may contain only Play Artist when none of their albums
    // are saved. Search's Albums section also includes the streaming catalog.
    if let albums = navigableRow(named: "Albums", in: results) {
      let page = await browse(albums.itemKey, nil)
      if page.errorMessage != nil { return page }
      let credited = creditedAlbums(in: page)
      if !credited.isEmpty { return BrowsePage(title: name, items: credited) }
      results = await browse(nil, query)
      if results.errorMessage != nil { return results }
    } else {
      let credited = creditedAlbums(in: results)
      if !credited.isEmpty { return BrowsePage(title: name, items: credited) }
    }
    guard let artists = navigableRow(named: "Artists", in: results) else {
      return unavailable
    }
    let matches = await browse(artists.itemKey, nil)
    if matches.errorMessage != nil { return matches }
    guard let artist = navigableRow(named: name, in: matches) else {
      return unavailable
    }
    var page = await browse(artist.itemKey, nil)
    if page.errorMessage != nil { return page }
    // Open the album section when offered; otherwise keep the artist's page.
    if let albums = navigableRow(named: "Discography", in: page)
      ?? navigableRow(named: "Albums", in: page) {
      page = await browse(albums.itemKey, nil)
    }
    if page.errorMessage == nil { page.title = name }
    return page
  }

  private var unavailable: BrowsePage {
    BrowsePage(
      title: name,
      items: [],
      errorMessage: "Couldn't find \(name) in Roon. Try browsing Artists in Library."
    )
  }

  private func creditedAlbums(in page: BrowsePage) -> [BrowseNode] {
    page.items.filter { item in
      item.itemKey != nil && !item.isPrompt && item.hint != "action" && item.hint != "action_list"
        && ArtistCredits.names(in: item.subtitle ?? "").contains {
          $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
  }

  private func navigableRow(named title: String, in page: BrowsePage) -> BrowseNode? {
    page.items.first {
      $0.itemKey != nil && !$0.isPrompt && $0.hint != "action" && $0.hint != "action_list"
        && $0.listedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
          .compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
  }
}

/// A library search submission. It is a stack value so iPad's path-based
/// NavigationStack can push the results page the same way it pushes an album.
/// A fresh token each time, so searching the same string twice still pushes.
struct BrowseSearch: Hashable, Identifiable {
  let token = UUID()
  var id: UUID { token }
  var hierarchy: String
  var itemKey: String?
  var title: String
  var input: String

  static func submitted(
    hierarchy: String,
    child: BrowseNode,
    prompt: String
  ) -> BrowseSearch? {
    let input = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return nil }
    return BrowseSearch(
      hierarchy: hierarchy,
      itemKey: child.itemKey,
      title: child.title,
      input: input
    )
  }
}

struct BrowseNode: Identifiable, Hashable {
  let id: String
  var title: String
  var subtitle: String?
  var listedTitle: String { RoonDisplayText.format(title) }
  var listedSubtitle: String { RoonDisplayText.format(subtitle ?? "") }
  var symbol: String
  var actions: [String]
  var isPrompt: Bool
  var children: [BrowseNode]
  var itemKey: String?
  var imageKey: String?
  var hierarchy: String?
  var hint: String?
  var musicPath: CinemaMusicPath? = nil
}

struct LibraryEntry: Identifiable, Hashable {
  let id: String
  var title: String
  var symbol: String
  var hierarchy: String
  /// Row inside the hierarchy's root to open instead of the root itself. Roon
  /// has no "library" hierarchy — Library is a row in the browse root — so the
  /// entry named after it has to walk one level in.
  var openChild: String?

  var root: BrowseNode {
    BrowseNode(
      id: id,
      title: title,
      subtitle: nil,
      symbol: symbol,
      actions: [],
      isPrompt: false,
      children: [],
      itemKey: nil,
      imageKey: nil,
      hierarchy: hierarchy,
      hint: nil
    )
  }

  /// Entry for a Now Playing toolbar shortcut or recorded action.
  ///
  /// Prefer id so "browse" opens Browse rather than Library (both use the
  /// browse hierarchy). An unknown name still opens something browsable.
  static func forLaunchHierarchy(_ hierarchy: String, in library: [LibraryEntry]) -> LibraryEntry {
    library.first { $0.id == hierarchy }
      ?? library.first { $0.hierarchy == hierarchy }
      ?? LibraryEntry(id: hierarchy, title: hierarchy, symbol: "music.note", hierarchy: hierarchy)
  }
}

struct SuggestedTrack: Identifiable, Hashable {
  let id: String
  var title: String
  var artist: String
  var album: String
  var error: String?
  var corrected: Bool

  var listedTitle: String { RoonDisplayText.format(title) }
  var listedArtist: String { RoonDisplayText.format(artist) }
  var listedAlbum: String { RoonDisplayText.format(album) }
}

struct CustomAction: Identifiable, Hashable {
  let id: String
  var label: String
  var symbol: String
  var hierarchy: String
  var path: [String]
  var actionIndex: Int?
}

struct ToolbarAction: Identifiable, Hashable, Codable {
  let id: String
  var label: String
  var symbol: String
  var hierarchy: String
}

enum AppTab: String, CaseIterable {
  case nowPlaying
  case library
  case search
  case rooms
  case settings
}

enum OnboardingStep: Int {
  case localNetwork
  case findingBridge
  case pin
  case waitingForCore
  case chooseZone
}

enum AppSession: Equatable {
  case onboarding(OnboardingStep)
  case main
}

enum Appearance: String, CaseIterable {
  case system
  case dark
  case light
}

struct VolumeHUD: Equatable {
  var value: Double
  var muted: Bool
  var minimum: Double
  var maximum: Double

  var displayValue: Int { Int(value.rounded()) }

  var symbolName: String {
    if muted || value <= minimum { return "speaker.slash.fill" }
    let span = max(maximum - minimum, 1)
    let fraction = (value - minimum) / span
    if fraction < 0.34 { return "speaker.wave.1.fill" }
    if fraction < 0.67 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
  }
}

enum SearchSegment: String, CaseIterable {
  case ai
  case camera
}

enum RoonDisplayText {
  /// Roon credits arrive as `[[25460090|Peter Fisher]] / Chamber Orchestra of London`.
  static func format(_ value: String) -> String {
    var output = ""
    var remainder = value
    while let start = remainder.range(of: "[[") {
      output += remainder[..<start.lowerBound]
      remainder = String(remainder[start.upperBound...])
      guard let end = remainder.range(of: "]]") else {
        output += "[["
        output += remainder
        return output
      }
      let inner = remainder[..<end.lowerBound]
      if let pipe = inner.lastIndex(of: "|") {
        output += inner[inner.index(after: pipe)...]
      } else {
        output += inner
      }
      remainder = String(remainder[end.upperBound...])
    }
    output += remainder
    return output
  }
}

enum RoonVoiceMatch {
  static func normalize(_ value: String) -> String {
    RoonDisplayText.format(value)
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  static func room(_ name: String, spoken: String) -> Bool {
    score(name, query: spoken) >= 50
  }

  static func score(_ title: String, query: String) -> Int {
    let titleText = normalize(title)
    let queryText = normalize(query)
    if titleText.isEmpty || queryText.isEmpty { return 0 }
    if titleText == queryText { return 100 }
    if titleText.hasPrefix(queryText) || queryText.hasPrefix(titleText) { return 90 }
    if titleText.contains(queryText) { return 80 }
    let ignored: Set<String> = ["the", "bbc", "a", "fm", "uk"]
    let queryTokens = Set(
      queryText.split(separator: " ").map(String.init).filter { !ignored.contains($0) }
    )
    let titleTokens = Set(titleText.split(separator: " ").map(String.init))
    if !queryTokens.isEmpty && queryTokens.isSubset(of: titleTokens) { return 70 }
    return 0
  }

  /// "Mah Na Mah Na" and "Mahna Mahna" are the same song.
  static func titlesMatch(_ a: String, _ b: String) -> Bool {
    let left = normalize(a)
    let right = normalize(b)
    if left.isEmpty || right.isEmpty { return false }
    if left == right { return true }
    return compact(left) == compact(right)
  }

  static func compact(_ value: String) -> String {
    normalize(value).replacingOccurrences(of: " ", with: "")
  }
}

enum ZonePanelTab: String, CaseIterable, Identifiable {
  case switchZone
  case group

  var id: String { rawValue }

  var title: String {
    switch self {
    case .switchZone: "Switch zone"
    case .group: "Group"
    }
  }
}

enum MockCatalog {
  static let recognized: [BrowseNode] = []
}
