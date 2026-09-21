import Foundation
import CryptoKit
import ImageIO

enum CinemaStorage {
  static var directory: URL {
    #if os(tvOS)
    // tvOS permits downloaded resources in purgeable storage. The bridge retains the originals.
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    #else
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    #endif
  }
}

enum CinemaSyncIdentity {
  static func mutation(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

/// A persistent cache of encoded pictures, separate from the small decoded viewer cache.
actor CinemaResourceStore {
  static let shared = CinemaResourceStore()
  private let root: URL

  init(directory: URL = CinemaStorage.directory
    .appendingPathComponent("CinemaResources", isDirectory: true)) {
    root = directory
  }

  private func key(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  func imageData(_ file: String) -> Data? {
    try? Data(contentsOf: root.appendingPathComponent(key(file) + ".image"))
  }

  func contains(_ file: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(key(file) + ".image").path)
  }

  func saveImage(_ bytes: Data, file: String) throws {
    try Task.checkCancellation()
    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
      CGImageSourceGetCount(source) > 0,
      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
      throw PersonalCinemaError("A picture could not be downloaded. Please retry syncing.")
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try bytes.write(to: root.appendingPathComponent(key(file) + ".image"), options: .atomic)
  }

  func catalog(scope: String) -> [TimeCapsule] {
    guard let bytes = try? Data(contentsOf: root.appendingPathComponent(key(scope) + ".json")) else { return [] }
    return (try? JSONDecoder().decode([TimeCapsule].self, from: bytes)) ?? []
  }

  func saveCatalog(_ capsules: [TimeCapsule], scope: String) throws {
    try Task.checkCancellation()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try JSONEncoder().encode(capsules).write(to: root.appendingPathComponent(key(scope) + ".json"), options: .atomic)
  }
}
