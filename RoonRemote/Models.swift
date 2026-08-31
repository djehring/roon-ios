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

  /// The key for the row named `title`, for a sidebar entry that has to step
  /// one level into a hierarchy to reach what it is named after.
  ///
  /// Matching on the title is the only option: Roon mints item keys per browse
  /// session, so there is nothing stable to hardcode.
  func itemKey(forChildTitled title: String) -> String? {
    items.first { $0.title == title }?.itemKey
  }
}

struct BrowseNode: Identifiable, Hashable {
  let id: String
  var title: String
  var subtitle: String?
  var symbol: String
  var actions: [String]
  var isPrompt: Bool
  var children: [BrowseNode]
  var itemKey: String?
  var imageKey: String?
  var hierarchy: String?
  var hint: String?
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
}

struct SuggestedTrack: Identifiable, Hashable {
  let id: String
  var title: String
  var artist: String
  var album: String
  var error: String?
  var corrected: Bool
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

enum RoonVoiceMatch {
  static func normalize(_ value: String) -> String {
    value
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
