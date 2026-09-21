#if os(iOS)
import Photos
import PhotosUI
import SwiftUI

@MainActor @Observable
final class CinemaPhotoSelection {
  static let limit = 200
  var items: [PhotosPickerItem] = []
  var album: CinemaPhotoAlbum?
  private(set) var albumAssetIDs: [String] = []
  private(set) var albumCover: PHAsset?
  var albums: [CinemaPhotoAlbum] = []
  var showingAlbums = false
  var message: String?
  var loadingAlbums = false
  var progress = ""
  var count: Int { album == nil ? items.count : albumAssetIDs.count }

  func select(_ album: CinemaPhotoAlbum, assetIDs: [String]) {
    guard !assetIDs.isEmpty, assetIDs.count <= Self.limit else { return }
    items = []
    albumAssetIDs = assetIDs
    albumCover = PHAsset.fetchAssets(withLocalIdentifiers: [assetIDs[0]], options: nil).firstObject
    self.album = album
    message = nil
    showingAlbums = false
  }

  func findAlbums() async {
    loadingAlbums = true
    defer { loadingAlbums = false }
    albums = []
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard status == .authorized else {
      message = status == .limited
        ? "Album browsing needs full Photos access. You can still use Choose photos, or change access in Settings."
        : "Photos access is off. Use Choose photos to select pictures without library access."
      return
    }
    message = nil
    // Counting a large iCloud library must not block presentation or scrolling.
    let found = await Task.detached(priority: .userInitiated) { CinemaPhotoLibrary.albums() }.value
    guard !Task.isCancelled else { return }
    albums = found
    if albums.isEmpty { message = "No photo albums found. Use Choose photos to select pictures." }
  }

  func create(request: CapsuleRequest) async throws -> TimeCapsule {
    var images: [CapsuleImage] = []
    do {
      if let album {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized,
          let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil).firstObject else {
          throw PersonalCinemaError("This album is no longer available. Choose it again or select individual photos.")
        }
        let available = PHAsset.fetchAssets(in: collection, options: CinemaPhotoLibrary.imageOptions())
        let selected = Set(albumAssetIDs)
        var byID: [String: PHAsset] = [:]
        available.enumerateObjects { asset, _, _ in
          if selected.contains(asset.localIdentifier) { byID[asset.localIdentifier] = asset }
        }
        let assets = albumAssetIDs.compactMap { byID[$0] }
        guard assets.count == albumAssetIDs.count, !assets.isEmpty else {
          throw PersonalCinemaError("Some selected photos are no longer in this album. Choose the album again to update your selection.")
        }
        guard assets.count <= Self.limit else { throw PersonalCinemaError("Choose up to 200 photos for your montage.") }
        for index in 0..<assets.count {
          try Task.checkCancellation()
          progress = "Saving photo \(index + 1) of \(assets.count)…"
          let asset = assets[index]
          let image = try await CinemaAssetRequest.image(asset, size: CGSize(width: 2560, height: 2560))
          guard let data = image.jpegData(compressionQuality: 0.95) else {
            throw PersonalCinemaError("A selected photo could not be read. Choose another photo and try again.")
          }
          images.append(try await PersonalCinemaStore.shared.importImage(data, date: asset.creationDate))
        }
      } else {
        for (index, item) in items.enumerated() {
          try Task.checkCancellation()
          progress = "Saving photo \(index + 1) of \(items.count)…"
          guard let data = try await item.loadTransferable(type: Data.self) else {
            throw PersonalCinemaError("A photo could not be downloaded. Check your connection and try again.")
          }
          images.append(try await PersonalCinemaStore.shared.importImage(data))
        }
      }
      return try await PersonalCinemaStore.shared.save(request: request, images: images, title: request.title ?? album?.title ?? "My photos")
    } catch {
      await PersonalCinemaStore.shared.discard(images)
      throw error
    }
  }

}

/// PhotoKit can deliver multiple callbacks, including after cancellation.
final class CinemaAssetRequest: @unchecked Sendable {
  static func image(_ asset: PHAsset, size: CGSize) async throws -> UIImage {
    let loader = CinemaAssetRequest()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in loader.start(asset, size: size, continuation: continuation) }
    } onCancel: { loader.cancel() }
  }
  private let lock = NSLock()
  private var continuation: CheckedContinuation<UIImage, Error>?
  private var requestID: PHImageRequestID?
  private var cancelled = false

  private func start(_ asset: PHAsset, size: CGSize, continuation: CheckedContinuation<UIImage, Error>) {
    lock.lock()
    guard !cancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
    self.continuation = continuation
    lock.unlock()
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .fast
    let id = PHImageManager.default().requestImage(for: asset, targetSize: size,
      contentMode: .aspectFit, options: options) { [self] image, info in
      if info?[PHImageCancelledKey] as? Bool == true { finish(.failure(CancellationError())); return }
      if let error = info?[PHImageErrorKey] as? Error { finish(.failure(error)); return }
      if info?[PHImageResultIsDegradedKey] as? Bool == true { return }
      if let image { finish(.success(image)) }
      else { finish(.failure(PersonalCinemaError("A photo could not be downloaded from Photos. Check your connection and try again."))) }
    }
    lock.lock(); requestID = id; let shouldCancel = cancelled; lock.unlock()
    if shouldCancel { PHImageManager.default().cancelImageRequest(id) }
  }
  func cancel() {
    lock.lock(); cancelled = true; let id = requestID; lock.unlock()
    if let id { PHImageManager.default().cancelImageRequest(id) }
    finish(.failure(CancellationError()))
  }
  private func finish(_ result: Result<UIImage, Error>) {
    lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
    pending?.resume(with: result)
  }
}

struct CinemaPhotoControls: View {
  @Bindable var selection: CinemaPhotoSelection

  var body: some View {
    Section {
      PhotosPicker(selection: $selection.items, maxSelectionCount: CinemaPhotoSelection.limit, selectionBehavior: .ordered, matching: .images) {
        Label("Choose photos", systemImage: "photo.on.rectangle")
      }
      .onChange(of: selection.items) { _, items in if !items.isEmpty { selection.album = nil } }
      Button { selection.showingAlbums = true } label: {
        Label("Choose an album", systemImage: "rectangle.stack")
      }
      if selection.count > 0 {
        HStack(spacing: 12) {
          if selection.album != nil {
            CinemaPhotoThumbnail(asset: selection.albumCover).frame(width: 56, height: 56)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          LabeledContent(selection.album?.title ?? "Selected photos", value: "\(selection.count) photos")
        }.accessibilityIdentifier("cinema-photo-selection")
      }
      if let message = selection.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
    } header: { Text("Your pictures") } footer: {
      Text("Save up to 200 photos on this device. Photos are not sent to AI or shared with other screens. Albums are saved as they are today.")
    }
  }
}
#endif
