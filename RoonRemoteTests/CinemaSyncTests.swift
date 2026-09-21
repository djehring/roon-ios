import Foundation
import Testing
import UIKit

@Suite("Cinema cross-device sync")
@MainActor
struct CinemaSyncTests {
  private func photo(_ color: UIColor) -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { context in
      color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
    }.jpegData(compressionQuality: 0.9)!
  }

  private func personal(_ store: PersonalCinemaStore) async throws -> TimeCapsule {
    let first = try await store.importImage(photo(.red))
    let second = try await store.importImage(photo(.blue))
    var request = CapsuleRequest(title: "Holiday", tracks: [
      CapsuleTrack(artist: "Artist", track: "Song", album: "Album", entryId: "one"),
      CapsuleTrack(artist: "Artist", track: "Song", album: "Album", entryId: "repeat")
    ], sourceLabel: "My soundtrack")
    request.options = CapsuleOptions(mode: .photos, subject: "My photos")
    return try await store.save(request: request, images: [first, second], title: "Holiday")
  }

  @Test func anotherDeviceDiscoversSetupSyncsPicturesAndReopensOffline() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = PersonalCinemaStore(directory: root.appendingPathComponent("phone"))
    let original = try await personal(source)
    let bridge = CinemaStub(); bridge.supportsSync = true
    let phone = CapsuleLibrary(personalStore: source, resourceStore: CinemaResourceStore(directory: root.appendingPathComponent("phone-cache")))
    await phone.load(client: bridge)
    #expect(phone.syncErrors.isEmpty)
    #expect(bridge.uploads.count == 2)
    let shared = try #require(bridge.saved.first)
    #expect(shared.id == original.id)
    #expect(shared.request == original.request)
    #expect(shared.montageFrames.map(\.image.localFile) == original.montageFrames.map(\.image.localFile))

    let tvPhotos = PersonalCinemaStore(directory: root.appendingPathComponent("tv"))
    let tvCache = CinemaResourceStore(directory: root.appendingPathComponent("tv-cache"))
    let tv = CapsuleLibrary(personalStore: tvPhotos, resourceStore: tvCache)
    await tv.load(client: bridge)
    #expect(tv.items.count == 1)
    #expect(!tv.downloadedIds.contains(shared.id))
    let discovered = try #require(tv.items.first)
    await tv.syncToDevice(discovered, client: bridge)
    #expect(tv.downloadedIds.contains(shared.id))
    #expect(bridge.downloads.count == 2)
    #expect(bridge.playCount == 0 && bridge.commandCount == 0)
    for image in shared.resourceImages { #expect(await tvCache.imageData(image.file) == bridge.images[image.file]) }
    bridge.loadError = URLError(.notConnectedToInternet)
    let restarted = CapsuleLibrary(personalStore: tvPhotos, resourceStore: tvCache)
    await restarted.load(client: bridge)
    #expect(restarted.items.first?.request == original.request)
    #expect(restarted.downloadedIds.contains(shared.id))
    #expect(restarted.error != nil)
  }

  @Test func failedDownloadResumesAndRejectsInvalidPictureBytes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = PersonalCinemaStore(directory: root.appendingPathComponent("phone"))
    let original = try await personal(source)
    var shared = try await source.publication(original)
    shared.revision = 1
    let bridge = CinemaStub(); bridge.supportsSync = true; bridge.saved = [shared]
    let images = shared.resourceImages
    bridge.images[images[0].file] = photo(.red)
    let tv = CapsuleLibrary(personalStore: PersonalCinemaStore(directory: root.appendingPathComponent("tv")),
      resourceStore: CinemaResourceStore(directory: root.appendingPathComponent("cache")))
    await tv.load(client: bridge)
    let discovered = try #require(tv.items.first)
    await tv.syncToDevice(discovered, client: bridge)
    #expect(!tv.downloadedIds.contains(shared.id))
    #expect(tv.syncErrors[shared.id] != nil)
    bridge.images[images[1].file] = Data("not a picture".utf8)
    await tv.syncToDevice(discovered, client: bridge)
    #expect(!tv.downloadedIds.contains(shared.id))
    bridge.images[images[1].file] = photo(.blue)
    await tv.syncToDevice(discovered, client: bridge)
    #expect(tv.downloadedIds.contains(shared.id))
    #expect(tv.syncErrors.isEmpty)
    #expect(bridge.downloads.filter { $0 == images[0].file }.count == 1)
    #expect(bridge.downloads.filter { $0 == images[1].file }.count == 3)
  }

  @Test func sharedDeletionClearsCachedManifestWithoutReuploadingIt() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = PersonalCinemaStore(directory: root.appendingPathComponent("photos"))
    _ = try await personal(source)
    let bridge = CinemaStub(); bridge.supportsSync = true
    let cache = CinemaResourceStore(directory: root.appendingPathComponent("cache"))
    let library = CapsuleLibrary(personalStore: source, resourceStore: cache)
    await library.load(client: bridge)
    bridge.saved = []
    await library.load(client: bridge)
    #expect(library.items.isEmpty)
    #expect(await source.load().isEmpty)
    #expect(await cache.catalog(scope: bridge.cinemaSyncScope).isEmpty)
    #expect(bridge.uploads.count == 2)
  }

  @Test func publicationConflictPreservesLocalEditAndTheSharedVersion() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = PersonalCinemaStore(directory: root.appendingPathComponent("photos"))
    _ = try await personal(source)
    let bridge = CinemaStub(); bridge.supportsSync = true
    let library = CapsuleLibrary(personalStore: source, resourceStore: CinemaResourceStore(directory: root.appendingPathComponent("cache")))
    await library.load(client: bridge)
    let saved = try #require(library.items.first)
    var request = saved.request; request.title = "Local draft"
    let draft = try await source.update(saved, options: try #require(saved.request.options), request: request)
    bridge.publicationError = RoonAPIError.httpStatus(409, "Changed on another device")
    await library.load(client: bridge)
    #expect(library.items.first == draft)
    #expect(library.syncErrors[draft.id] != nil)
    #expect(bridge.saved.first?.title == "Holiday")
    #expect(bridge.uploads.count == 2)
    #expect(library.syncConflicts.contains(draft.id))
    await library.useSharedVersion(draft, client: bridge)
    #expect(library.items.first?.title == "Holiday")
    #expect(library.syncConflicts.isEmpty)
    #expect(library.syncErrors.isEmpty)
  }
}
