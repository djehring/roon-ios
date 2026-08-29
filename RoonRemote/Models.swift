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
}

struct Output: Identifiable, Hashable {
  let id: String
  var name: String
  var volume: Double
  var min: Double
  var max: Double
  var muted: Bool
  var isFixed: Bool
}

struct BrowseNode: Identifiable, Hashable {
  let id: String
  var title: String
  var subtitle: String?
  var symbol: String
  var actions: [String]
  var isPrompt: Bool
  var children: [BrowseNode]
}

struct LibraryEntry: Identifiable, Hashable {
  let id: String
  var title: String
  var symbol: String
  var root: BrowseNode
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
}

struct ToolbarAction: Identifiable, Hashable {
  let id: String
  var label: String
  var symbol: String
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

enum AppSession {
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
