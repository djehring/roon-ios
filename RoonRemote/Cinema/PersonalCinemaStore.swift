import Foundation
import ImageIO
import UIKit
import CryptoKit

/// Imported originals and personal manifests survive app restarts and failed syncs.
actor PersonalCinemaStore {
  static let shared = PersonalCinemaStore()
  private let root: URL
  init(directory: URL = PersonalCinemaStore.directory) { root = directory }
  nonisolated static var directory: URL {
    CinemaStorage.directory
      .appendingPathComponent("PersonalCinema", isDirectory: true)
  }
  nonisolated static func imageURL(_ name: String, directory: URL = PersonalCinemaStore.directory) -> URL? {
    guard name.hasSuffix(".jpg"), UUID(uuidString: String(name.dropLast(4))) != nil else { return nil }
    return directory.appendingPathComponent(name)
  }

  func importImage(_ data: Data, date: Date? = nil) throws -> CapsuleImage {
    try Task.checkCancellation()
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 2560,
      ] as CFDictionary), let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.9) else {
      throw PersonalCinemaError("A selected photo could not be read. Choose another photo and try again.")
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let name = UUID().uuidString + ".jpg"
    try jpeg.write(to: root.appendingPathComponent(name), options: .atomic)
    let captured = date ?? Self.captureDate(source)
    return CapsuleImage(file: name, sourceUrl: URL(string: "roon-photo://personal")!,
      credit: "Your photo", license: "Personal photo", licenseUrl: "",
      date: captured.map { ISO8601DateFormatter().string(from: $0) } ?? "",
      description: "Personal photo", localFile: name)
  }

  func save(request: CapsuleRequest, images: [CapsuleImage], title: String) throws -> TimeCapsule {
    guard !images.isEmpty else { throw PersonalCinemaError("Choose at least one photo.") }
    try Task.checkCancellation()
    var ordered = images
    if request.options?.order == .chronological {
      ordered = images.enumerated().sorted {
        if $0.element.date == $1.element.date { return $0.offset < $1.offset }
        if $0.element.date.isEmpty { return false }
        if $1.element.date.isEmpty { return true }
        return $0.element.date < $1.element.date
      }.map(\.element)
    } else if request.options?.order == .shuffled { ordered.shuffle() }
    let capsule = TimeCapsule(id: "personal-" + UUID().uuidString,
      title: title.isEmpty ? "My photos" : title, contextLabel: "Personal montage",
      request: request, createdAt: ISO8601DateFormatter().string(from: Date()),
      scenes: ordered.enumerated().map { index, image in
        CapsuleScene(id: image.file, title: ISO8601DateFormatter().date(from: image.date)?.formatted(date: .abbreviated, time: .omitted) ?? "Photo \(index + 1)", body: "", dateLabel: "",
          scope: "", sources: [], trackIndices: [], image: image)
      })
    let manifest = root.appendingPathComponent(capsule.id + ".json")
    try JSONEncoder().encode(capsule).write(to: manifest, options: .atomic)
    if Task.isCancelled {
      try? FileManager.default.removeItem(at: manifest)
      throw CancellationError()
    }
    return capsule
  }

  func hasImage(_ name: String) -> Bool {
    guard let url = Self.imageURL(name, directory: root) else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  func storeManifest(_ capsule: TimeCapsule) throws {
    guard capsule.isPersonal, capsule.id.hasPrefix("personal-"),
      UUID(uuidString: String(capsule.id.dropFirst(9))) != nil else { throw URLError(.badURL) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try JSONEncoder().encode(capsule).write(to: root.appendingPathComponent(capsule.id + ".json"), options: .atomic)
  }

  func manifest(_ id: String) throws -> TimeCapsule? {
    guard id.hasPrefix("personal-"), UUID(uuidString: String(id.dropFirst(9))) != nil else { throw URLError(.badURL) }
    let url = root.appendingPathComponent(id + ".json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(TimeCapsule.self, from: Data(contentsOf: url))
  }

  /// Refresh must not overwrite a draft or restore a manifest deleted during its network request.
  func reconcile(_ capsule: TimeCapsule, expected: TimeCapsule?, remove: Bool = false) throws -> Bool {
    let current = try manifest(capsule.id)
    guard current == expected else { return false }
    if remove { try self.remove(capsule) } else { try storeManifest(capsule) }
    return true
  }

  /// Content addresses let uploads resume without changing the saved picture order.
  func publication(_ capsule: TimeCapsule) throws -> TimeCapsule {
    var result = capsule
    func address(_ image: CapsuleImage) throws -> CapsuleImage {
      var image = image
      if image.file.count == 64, image.file.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) { return image }
      guard let name = image.localFile else { throw URLError(.fileDoesNotExist) }
      image.file = SHA256.hash(data: try imageData(name)).map { String(format: "%02x", $0) }.joined()
      return image
    }
    for index in result.scenes.indices {
      result.scenes[index].image = try result.scenes[index].image.map(address)
      result.scenes[index].images = try result.scenes[index].images?.map(address)
    }
    result.contextImage = try result.contextImage.map(address)
    result.contextLabel = "Personal montage"
    return result
  }

  private static func captureDate(_ source: CGImageSource) -> Date? {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
      let value = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter.date(from: value)
  }

  func load() -> [TimeCapsule] {
    let files = (try? FileManager.default.contentsOfDirectory(at: root,
      includingPropertiesForKeys: nil)) ?? []
    return files.filter { $0.pathExtension == "json" }.compactMap { url in
      guard let data = try? Data(contentsOf: url),
        let capsule = try? JSONDecoder().decode(TimeCapsule.self, from: data), capsule.isPersonal else { return nil }
      return capsule
    }
  }

  func imageData(_ name: String) throws -> Data {
    guard let url = Self.imageURL(name, directory: root) else { throw URLError(.badURL) }
    return try Data(contentsOf: url)
  }

  /// Reuses the imported copies and identity; editing never reimports Photos.
  func update(_ capsule: TimeCapsule, options: CapsuleOptions, request: CapsuleRequest? = nil) throws -> TimeCapsule {
    guard capsule.isPersonal, options.mode == .photos,
      capsule.id.hasPrefix("personal-"), UUID(uuidString: String(capsule.id.dropFirst(9))) != nil else {
      throw PersonalCinemaError("This personal montage could not be updated.")
    }
    var updated = capsule
    if let request {
      guard !request.tracks.isEmpty else { throw PersonalCinemaError("Add at least one track.") }
      updated.request = request
      updated.title = request.title ?? capsule.title
    }
    updated.request.options = options
    updated.revision = (capsule.revision ?? 0) + 1
    if options.order != capsule.request.options?.order {
      updated.createdAt = ISO8601DateFormatter().string(from: Date())
      if options.order == .chronological {
        updated.scenes = updated.scenes.enumerated().sorted { left, right in
          let a = left.element.image?.date ?? "", b = right.element.image?.date ?? ""
          if a == b { return left.offset < right.offset }
          if a.isEmpty { return false }
          if b.isEmpty { return true }
          return a < b
        }.map(\.element)
      } else if options.order == .shuffled { updated.scenes.shuffle() }
    }
    try Task.checkCancellation()
    try JSONEncoder().encode(updated).write(to: root.appendingPathComponent(capsule.id + ".json"), options: .atomic)
    return updated
  }

  func discard(_ images: [CapsuleImage]) {
    for image in images {
      if let name = image.localFile, let url = Self.imageURL(name, directory: root) { try? FileManager.default.removeItem(at: url) }
    }
  }

  func remove(_ capsule: TimeCapsule) throws {
    guard capsule.isPersonal, capsule.id.hasPrefix("personal-"),
      UUID(uuidString: String(capsule.id.dropFirst(9))) != nil else { return }
    let manifest = root.appendingPathComponent(capsule.id + ".json")
    if FileManager.default.fileExists(atPath: manifest.path) {
      try FileManager.default.removeItem(at: manifest)
    }
    discard(capsule.montageFrames.map(\.image))
  }
}

struct PersonalCinemaError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
