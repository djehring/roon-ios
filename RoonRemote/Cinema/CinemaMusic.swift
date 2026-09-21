import Foundation
import Observation

struct CinemaMusicStep: Codable, Hashable {
  var title: String
  var subtitle: String?
  var imageKey: String?
  var index: Int
  var input: String?
}

struct CinemaMusicPath: Codable, Hashable {
  var hierarchy: String
  var query: String?
  var steps: [CinemaMusicStep] = []

  func appending(_ item: BrowseItem, index: Int) -> Self {
    var path = self
    path.steps.append(CinemaMusicStep(title: item.title, subtitle: item.subtitle,
      imageKey: item.imageKey, index: index))
    return path
  }
}

struct CinemaMusicItem: Decodable, Identifiable {
  var title: String
  var subtitle: String?
  var imageKey: String?
  var kind: String
  var path: CinemaMusicPath
  var id: CinemaMusicPath { path }
}

struct CinemaMusicPage: Decodable {
  var title: String
  var subtitle: String?
  var kind: String
  var path: CinemaMusicPath
  var items: [CinemaMusicItem]
  var canImport: Bool { ["album", "playlist", "track"].contains(kind) }
}

struct CinemaQueueSnapshot: Decodable {
  var title: String
  var sourceLabel: String
  var tracks: [CapsuleTrack]
  var includesCurrent: Bool
}

/// The editor owns a frozen value, independent of the live queue and AI search results.
@MainActor @Observable
final class CinemaMusicDraft {
  static let trackLimit = 1000
  var tracks: [CapsuleTrack]
  private var undoStack: [[CapsuleTrack]] = []
  var canUndo: Bool { !undoStack.isEmpty }

  init(tracks: [CapsuleTrack]) { self.tracks = Self.identify(tracks) }

  static func identify(_ tracks: [CapsuleTrack]) -> [CapsuleTrack] {
    var ids = Set<String>()
    return tracks.map { track in
      var track = track
      if track.entryId == nil || !ids.insert(track.entryId!).inserted {
        track.entryId = UUID().uuidString
        ids.insert(track.entryId!)
      }
      return track
    }
  }

  var summary: String {
    let count = "\(tracks.count) track\(tracks.count == 1 ? "" : "s")"
    guard !tracks.isEmpty, tracks.allSatisfy({ ($0.durationSeconds ?? 0) > 0 }) else { return count }
    return "\(count) · \(Int(tracks.reduce(0) { $0 + ($1.durationSeconds ?? 0) } / 60)) min"
  }

  func append(_ additions: [CapsuleTrack]) throws {
    guard tracks.count + additions.count <= Self.trackLimit else {
      throw PersonalCinemaError("Cinema supports up to \(Self.trackLimit) tracks. Remove some tracks before adding more.")
    }
    remember()
    tracks += additions.map { item in var copy = item; copy.entryId = UUID().uuidString; return copy }
  }

  func remove(_ id: String) {
    guard tracks.contains(where: { $0.entryId == id }) else { return }
    remember(); tracks.removeAll { $0.entryId == id }
  }

  func restoreCurrent(_ track: CapsuleTrack) {
    guard tracks.count < Self.trackLimit, !tracks.contains(where: { $0.entryId == track.entryId }) else { return }
    remember(); tracks.insert(track, at: 0)
  }

  func move(_ id: String, to position: Int) {
    guard let index = tracks.firstIndex(where: { $0.entryId == id }), tracks.indices.contains(position), index != position else { return }
    remember()
    let track = tracks.remove(at: index)
    tracks.insert(track, at: position)
  }

  func move(from offsets: IndexSet, to destination: Int) {
    guard !offsets.isEmpty else { return }
    remember()
    let moving = offsets.sorted().map { tracks[$0] }
    for index in offsets.sorted().reversed() { tracks.remove(at: index) }
    tracks.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
  }

  func undo() { if let previous = undoStack.popLast() { tracks = previous } }
  private func remember() {
    if undoStack.count == 30 { undoStack.removeFirst() }
    undoStack.append(tracks)
  }
}

extension CapsuleRequest {
  init(title: String, tracks: [CapsuleTrack], sourceLabel: String) {
    self.init(context: CapsuleSearchContext(query: title), tracks: [])
    self.tracks = tracks
    self.title = title
    self.sourceLabel = sourceLabel
    clientRequestId = UUID().uuidString
    options = CapsuleOptions(mode: .artwork, subject: title)
  }
}
