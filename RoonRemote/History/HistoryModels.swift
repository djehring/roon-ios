import Foundation

struct HistoryEntry: Decodable, Identifiable, Hashable {
  var id: String
  var coreId: String
  var observedAt: Date
  var qualifiedAt: Date
  var zoneId: String
  var room: String
  var title: String
  var artist: String
  var album: String
  var duration: Double
  var imageKey: String?
  var albumId: String

  func isRetained(at now: Date = Date()) -> Bool {
    observedAt >= now.addingTimeInterval(-14 * 86400)
  }
}
struct HistoryRoom: Decodable, Identifiable { var id: String; var name: String }
struct HistoryPage: Decodable {
  var items: [HistoryEntry]
  var nextCursor: String?
  var rooms: [HistoryRoom]
  var coreId: String
  var revision: Int
  var startedAt: Date
  var connected: Bool
  var status: String
  var message: String?
  var oldestRetainedAt: Date?
}
struct HistoryCapabilities: Decodable { var version: Int; var retentionDays: Int; var maxEvents: Int }
struct HistoryResolution: Decodable { var choices: [CinemaMusicItem]; var message: String }
enum HistoryKind: String, CaseIterable { case albums, tracks; var title: String { rawValue.capitalized } }
enum HistoryFailure: LocalizedError {
  case unsupported
  var errorDescription: String? { "Update your bridge to use Recently played." }
}

@MainActor protocol HistoryClient {
  func historyCapabilities() async throws -> HistoryCapabilities
  func historyPage(kind: HistoryKind, room: String?, cursor: String?) async throws -> HistoryPage
}

extension JSONDecoder {
  static func historyDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: value) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      if let date = formatter.date(from: value) { return date }
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid history date"))
    }
    return decoder
  }
}
