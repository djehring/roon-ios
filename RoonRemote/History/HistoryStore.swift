import Foundation
import Observation

@MainActor @Observable
final class HistoryStore {
  var items: [HistoryEntry] = []
  var rooms: [HistoryRoom] = []
  var loading = false
  var failure: String?
  var unsupported = false
  var status: String?
  var nextCursor: String?
  var coreId: String?
  private var context = ""
  private var requestID = UUID()
  private var supportedConnection: String?
  private var hasPaged = false
  private var connectionKey = ""

  func expire(now: Date = Date()) { items.removeAll { !$0.isRetained(at: now) } }

  func load(client: any HistoryClient, connection: String, kind: HistoryKind, room: String, more: Bool = false) async {
    let key = "\(connection)|\(kind.rawValue)|\(room)"
    if more && (loading || nextCursor == nil || context != key) { return }
    expire()
    if connectionKey != connection { rooms = []; connectionKey = connection }
    let changed = key != context
    if changed {
      context = key
      items = []; nextCursor = nil; coreId = nil; status = nil; hasPaged = false
    }
    let request = UUID()
    requestID = request
    loading = true; failure = nil; unsupported = false
    let cursor = more ? nextCursor : nil
    defer { if requestID == request { loading = false } }
    do {
      if supportedConnection != connection {
        let capabilities = try await client.historyCapabilities()
        guard capabilities.version == 1 else { throw HistoryFailure.unsupported }
        guard requestID == request, !Task.isCancelled else { return }
        supportedConnection = connection
      }
      let page = try await client.historyPage(kind: kind, room: room.isEmpty ? nil : room, cursor: cursor)
      guard requestID == request, !Task.isCancelled else { return }
      if more && coreId != page.coreId {
        items = []; nextCursor = nil; coreId = page.coreId
        failure = "The Roon server changed. Refresh Recently played."
        return
      }
      let incoming = page.items.filter { $0.isRetained() }
      let identity: (HistoryEntry) -> String = { kind == .albums ? $0.albumId : $0.id }
      let incomingIDs = Set(incoming.map(identity))
      let overlaps = items.contains { incomingIDs.contains(identity($0)) }
      if more {
        let ids = Set(items.map(identity))
        items.append(contentsOf: incoming.filter { !ids.contains(identity($0)) })
        hasPaged = true
        nextCursor = page.nextCursor
      } else if hasPaged && coreId == page.coreId && overlaps {
        // A refresh keeps the older pages and their cursor when the ranges overlap.
        // New album plays replace the older instance of that album.
        items = incoming + items.filter { !incomingIDs.contains(identity($0)) }
      } else {
        items = incoming
        nextCursor = page.nextCursor
        hasPaged = false
      }
      coreId = page.coreId
      rooms = page.rooms
      status = page.message ?? (page.connected ? nil : "The bridge is disconnected from Roon. New plays are not being recorded.")
      if let oldest = page.oldestRetainedAt { items.removeAll { $0.observedAt < oldest } }
      items = Array(items.prefix(10000))
      expire()
    } catch is CancellationError { }
    catch {
      guard requestID == request, !Task.isCancelled else { return }
      unsupported = error is HistoryFailure
      failure = error.localizedDescription
      expire()
    }
  }
}
