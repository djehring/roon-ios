#if os(iOS)
import Foundation

enum LiveActivityPushHTTP {
  private static let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 20
    return URLSession(configuration: config)
  }()

  static func register(_ target: LiveActivityPushTarget) async throws {
    var request = URLRequest(url: target.url)
    request.httpMethod = "PUT"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode([
      "pushToken": target.pushToken, "zoneID": target.zoneID, "environment": target.environment,
    ])
    try await send(request, expected: 200)
  }
  static func remove(_ target: LiveActivityPushTarget) async throws {
    var request = URLRequest(url: target.url)
    request.httpMethod = "DELETE"
    try await send(request, expected: 204)
  }
  private static func send(_ request: URLRequest, expected: Int) async throws {
    let (_, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == expected else {
      throw URLError(.badServerResponse)
    }
  }
}
#endif
