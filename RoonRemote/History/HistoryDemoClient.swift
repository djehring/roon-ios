#if DEBUG
import Foundation

@MainActor struct HistoryDemoClient: HistoryClient {
  func historyCapabilities() async throws -> HistoryCapabilities {
    if ProcessInfo.processInfo.environment["ROON_HISTORY_STATE"] == "unsupported" { throw HistoryFailure.unsupported }
    return HistoryCapabilities(version: 1, retentionDays: 14, maxEvents: 10000)
  }
  func historyPage(kind: HistoryKind, room: String?, cursor: String?) async throws -> HistoryPage {
    let scenario = ProcessInfo.processInfo.environment["ROON_HISTORY_STATE"] ?? "normal"
    let entries = Self.entries.filter { room == nil || $0.zoneId == room }
    let items = scenario == "empty" ? [] : kind == .albums ? [entries.first].compactMap { $0 } : entries
    return HistoryPage(items: items, rooms: [.init(id: "office", name: "Office"), .init(id: "kitchen", name: "Kitchen")],
      coreId: "demo-core", revision: 1, startedAt: Date().addingTimeInterval(-86400),
      connected: scenario != "disconnected", status: scenario == "disconnected" ? "disconnected" : "recording")
  }
  static var entries: [HistoryEntry] {
    ["So What", "Freddie Freeloader", "Blue in Green", "So What"].enumerated().map { index, title in
      HistoryEntry(id: "demo-history-\(index)", coreId: "demo-core", observedAt: Date().addingTimeInterval(Double(-index * 3600 - 60)),
        qualifiedAt: Date().addingTimeInterval(Double(-index * 3600 - 30)), zoneId: index == 3 ? "kitchen" : "office",
        room: index == 3 ? "Kitchen" : "Office", title: title, artist: "Miles Davis", album: "Kind of Blue", duration: 540,
        imageKey: "demo-cover", albumId: "demo-album")
    }
  }
  static func resolution(entry: HistoryEntry, kind: HistoryKind) -> HistoryResolution {
    let title = kind == .albums ? entry.album : entry.title
    var choices = [CinemaMusicItem(title: title, subtitle: "Miles Davis", kind: kind == .albums ? "album" : "track",
      path: CinemaMusicPath(hierarchy: "search", query: title, steps: [.init(title: title, index: 0)]))]
    if ProcessInfo.processInfo.environment["ROON_HISTORY_STATE"] == "ambiguous" {
      choices.append(CinemaMusicItem(title: title, subtitle: "Miles Davis · Alternate edition", kind: choices[0].kind,
        path: CinemaMusicPath(hierarchy: "search", query: title, steps: [.init(title: title, index: 1)])))
    }
    return HistoryResolution(choices: choices, message: "Choose the recording or edition you want.")
  }
  static func browse(_ path: CinemaMusicPath) -> CinemaMusicPage {
    let album = path.steps.last?.title == "Kind of Blue"
    return CinemaMusicPage(title: path.steps.last?.title ?? "Music", kind: album ? "album" : "track", path: path,
      items: album ? entries.prefix(3).enumerated().map { index, entry in
        var child = path; child.steps.append(.init(title: entry.title, index: index))
        return CinemaMusicItem(title: entry.title, subtitle: entry.artist, kind: "track", path: child)
      } : [])
  }
}
#endif
