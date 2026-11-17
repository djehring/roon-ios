import Foundation

/// Bounded local diagnostics for locked-phone verification without a debugger,
/// which would otherwise change the app's background lifetime. No credentials.
enum NowPlayingDiagnostics {
  private static let queue = DispatchQueue(label: "com.djehring.roonremote.now-playing-trace")

  static func record(_ event: String, detail: String = "") {
    #if DEBUG
    queue.async {
      let file = URL.applicationSupportDirectory.appending(path: "NowPlaying/diagnostics.json")
      var entries: [[String: String]] = (try? Data(contentsOf: file))
        .flatMap { try? JSONDecoder().decode([[String: String]].self, from: $0) } ?? []
      entries.append(["time": ISO8601DateFormatter().string(from: Date()),
        "event": event, "detail": String(detail.prefix(300))])
      try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      if let data = try? JSONEncoder().encode(Array(entries.suffix(200))) {
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      }
    }
    #endif
  }
}
