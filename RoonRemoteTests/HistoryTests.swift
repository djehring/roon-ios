import Foundation
import Testing

@MainActor private final class HistoryStub: HistoryClient {
  var capabilityCalls = 0
  var result = HistoryPage(items: [], rooms: [], coreId: "core", revision: 1, startedAt: Date(), connected: true, status: "recording")
  var error: Error?
  var pending: CheckedContinuation<HistoryPage, Error>?
  var suspend = false
  func historyCapabilities() async throws -> HistoryCapabilities {
    capabilityCalls += 1
    if let error { throw error }
    return .init(version: 1, retentionDays: 14, maxEvents: 10000)
  }
  func historyPage(kind: HistoryKind, room: String?, cursor: String?) async throws -> HistoryPage {
    if let error { throw error }
    if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
    return result
  }
}
@Suite("Recently played") @MainActor struct HistoryTests {
  private func entry(_ id: String, age: TimeInterval = 60) -> HistoryEntry {
    .init(id: id, coreId: "core", observedAt: Date().addingTimeInterval(-age), qualifiedAt: Date(),
      zoneId: "room", room: "Room", title: "Song", artist: "Artist", album: "Album", duration: 180, albumId: id)
  }
  @Test func expiresWithoutNetwork() {
    let store = HistoryStore()
    store.items = [entry("fresh"), entry("old", age: 15 * 86400)]
    store.expire()
    #expect(store.items.map(\.id) == ["fresh"])
  }
  @Test func capabilityCheckIsPerConnection() async {
    let stub = HistoryStub(); let store = HistoryStore()
    await store.load(client: stub, connection: "one", kind: .albums, room: "")
    await store.load(client: stub, connection: "one", kind: .tracks, room: "")
    #expect(stub.capabilityCalls == 1)
    await store.load(client: stub, connection: "two", kind: .albums, room: "")
    #expect(stub.capabilityCalls == 2)
  }
  @Test func failedRefreshPreservesRowsButNewConnectionClearsThem() async {
    let stub = HistoryStub(); let store = HistoryStore()
    stub.result.items = [entry("one")]
    await store.load(client: stub, connection: "one", kind: .tracks, room: "")
    stub.error = URLError(.notConnectedToInternet)
    await store.load(client: stub, connection: "one", kind: .tracks, room: "")
    #expect(store.items.count == 1)
    #expect(store.failure != nil)
    await store.load(client: stub, connection: "two", kind: .tracks, room: "")
    #expect(store.items.isEmpty)
  }
  @Test func unsupportedIsDistinctFromEmpty() async {
    let stub = HistoryStub(); let store = HistoryStore()
    stub.error = HistoryFailure.unsupported
    await store.load(client: stub, connection: "one", kind: .albums, room: "")
    #expect(store.unsupported)
    #expect(store.failure != nil)
  }
  @Test func refreshPreservesLoadedOlderPages() async {
    let stub = HistoryStub(); let store = HistoryStore()
    stub.result.items = [entry("one")]; stub.result.nextCursor = "cursor"
    await store.load(client: stub, connection: "one", kind: .tracks, room: "")
    stub.result.items = [entry("two", age: 120)]; stub.result.nextCursor = nil
    await store.load(client: stub, connection: "one", kind: .tracks, room: "", more: true)
    stub.result.items = [entry("new", age: 10), entry("one")]; stub.result.nextCursor = "new-cursor"
    await store.load(client: stub, connection: "one", kind: .tracks, room: "")
    #expect(store.items.map(\.id) == ["new", "one", "two"])
    #expect(store.nextCursor == nil)
  }
  @Test func oldFilterResponseCannotReplaceNewFilter() async {
    let slow = HistoryStub(); slow.suspend = true
    let fresh = HistoryStub(); fresh.result.items = [entry("new")]
    let store = HistoryStore()
    let old = Task { await store.load(client: slow, connection: "one", kind: .tracks, room: "old") }
    while slow.pending == nil { await Task.yield() }
    await store.load(client: fresh, connection: "one", kind: .tracks, room: "new")
    slow.pending?.resume(returning: slow.result)
    await old.value
    #expect(store.items.map(\.id) == ["new"])
    #expect(!store.loading)
  }
  @Test func decodesBridgeDatesWithFractionalSeconds() throws {
    let data = Data("\"2026-09-27T10:30:12.123Z\"".utf8)
    let date = try JSONDecoder.historyDecoder().decode(Date.self, from: data)
    #expect(date.timeIntervalSince1970 > 0)
  }
}
