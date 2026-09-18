#if os(iOS)
import Photos
import PhotosUI
import SwiftUI

struct CinemaPhotoAlbum: Identifiable {
  let id: String
  let title: String
  let count: Int
}

@MainActor @Observable
final class CinemaPhotoSelection {
  var items: [PhotosPickerItem] = []
  var album: CinemaPhotoAlbum?
  var albums: [CinemaPhotoAlbum] = []
  var message: String?
  var loadingAlbums = false
  var progress = ""
  var count: Int { album?.count ?? items.count }

  func findAlbums() async {
    loadingAlbums = true
    defer { loadingAlbums = false }
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard status == .authorized else {
      message = status == .limited
        ? "Album browsing needs full Photos access. You can still use Choose photos, or change access in Settings."
        : "Photos access is off. Use Choose photos to select pictures without library access."
      return
    }
    message = nil
    var found: [CinemaPhotoAlbum] = []
    let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
    collections.enumerateObjects { collection, _, _ in
      let options = PHFetchOptions()
      options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
      let count = PHAsset.fetchAssets(in: collection, options: options).count
      if count > 0 {
        found.append(CinemaPhotoAlbum(id: collection.localIdentifier,
          title: collection.localizedTitle ?? "Album", count: count))
      }
    }
    albums = found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        guard assets.count <= 200 else { throw PersonalCinemaError("Choose an album with up to 200 photos, or use Choose photos to make a selection.") }
        for index in 0..<assets.count {
          try Task.checkCancellation()
          progress = "Saving photo \(index + 1) of \(assets.count)…"
          let asset = assets.object(at: index)
          let data = try await Self.imageData(asset)
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
      return try await PersonalCinemaStore.shared.save(request: request, images: images, title: album?.title ?? "My photos")
    } catch {
      await PersonalCinemaStore.shared.discard(images)
      throw error
    }
  }

  private static func imageData(_ asset: PHAsset) async throws -> Data {
    let loader = CinemaAssetRequest()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in loader.start(asset, continuation: continuation) }
    } onCancel: { loader.cancel() }
  }
}

/// PhotoKit can deliver multiple callbacks, including after cancellation.
private final class CinemaAssetRequest: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data, Error>?
  private var requestID: PHImageRequestID?
  private var cancelled = false

  func start(_ asset: PHAsset, continuation: CheckedContinuation<Data, Error>) {
    lock.lock()
    guard !cancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
    self.continuation = continuation
    lock.unlock()
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat
    let id = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 2560, height: 2560),
      contentMode: .aspectFit, options: options) { [self] image, info in
      if info?[PHImageResultIsDegradedKey] as? Bool == true { return }
      if let data = image?.jpegData(compressionQuality: 0.95) { finish(.success(data)) }
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
  private func finish(_ result: Result<Data, Error>) {
    lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
    pending?.resume(with: result)
  }
}

struct CinemaPhotoControls: View {
  @Bindable var selection: CinemaPhotoSelection
  @State private var showingAlbums = false

  var body: some View {
    Section {
      PhotosPicker(selection: $selection.items, maxSelectionCount: 200, selectionBehavior: .ordered, matching: .images) {
        Label("Choose photos", systemImage: "photo.on.rectangle")
      }
      .onChange(of: selection.items) { _, items in if !items.isEmpty { selection.album = nil } }
      Button {
        Task { await selection.findAlbums(); showingAlbums = !selection.albums.isEmpty }
      } label: {
        Label(selection.loadingAlbums ? "Loading albums…" : "Choose an album", systemImage: "rectangle.stack")
      }
      .disabled(selection.loadingAlbums)
      if selection.count > 0 {
        LabeledContent(selection.album?.title ?? "Selected photos", value: "\(selection.count) photos")
      }
      if let message = selection.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
    } header: { Text("Your pictures") } footer: {
      Text("Save up to 200 photos on this device. Photos are not sent to AI or shared with other screens. Albums are saved as they are today.")
    }
    .sheet(isPresented: $showingAlbums) {
      NavigationStack {
        List(selection.albums) { album in
          Button {
            selection.items = []; selection.album = album; showingAlbums = false
          } label: { LabeledContent(album.title, value: "\(album.count) photos") }
          .disabled(album.count > 200)
        }
        .navigationTitle("Choose an album")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAlbums = false } } }
        .safeAreaInset(edge: .bottom) {
          Text("Albums over 200 photos are unavailable. Use Choose photos for a smaller selection.")
            .font(.footnote).foregroundStyle(.secondary).padding().background(.bar)
        }
      }
    }
  }
}
#endif
