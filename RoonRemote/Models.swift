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

enum SearchSegment: String, CaseIterable {
  case ai
  case camera
  case story
}

enum MockCatalog {
  static let recognized: [BrowseNode] = []
}
