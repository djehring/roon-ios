import Foundation

enum CinemaPlaylistFixture {
  static var json: String {
    let items: [[String: Any]] = ["preview-a", "preview-b"].enumerated().map { index, id in
      ["id": id, "title": index == 0 ? "September ’76" : "Bowie in Berlin", "contextLabel": "Saved playlist",
        "createdAt": "2026-09-18T12:00:00Z",
        "request": ["query": "September 1976", "requestedAt": "2026-09-18T12:00:00Z", "locale": "en_GB", "timeZone": "Europe/London",
          "tracks": [["artist": "ABBA", "track": "Dancing Queen", "album": "Arrival"]],
          "options": ["mode": "period", "topics": ["headlines", "culture"], "subject": "September 1976", "region": "GB",
            "workContext": "composition", "captions": "brief", "motion": "still", "pace": "standard", "order": "curated"]],
        "scenes": (0..<3).map { n in
          ["id": "scene-\(n)", "title": "Picture \(n)", "body": "", "dateLabel": "1976", "scope": "", "sources": [], "trackIndices": [],
            "image": ["file": "test-image-\(n)", "sourceUrl": "https://example.org", "credit": "Preview", "license": "Preview",
              "licenseUrl": "", "date": "1976", "description": "Preview"]] as [String: Any]
        }] as [String: Any]
    }
    return String(data: try! JSONSerialization.data(withJSONObject: items), encoding: .utf8)!
  }

}
