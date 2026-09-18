import Foundation
import Testing
import UIKit

@Suite("Personal Cinema storage")
struct PersonalCinemaTests {
  @Test func importedPhotosSurviveReloadAndRespectChronologicalOrder() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PersonalCinemaStore(directory: directory)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let data = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
      UIColor.blue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
    }.pngData()!
    let later = try await store.importImage(data, date: Date(timeIntervalSince1970: 200000))
    let earlier = try await store.importImage(data, date: Date(timeIntervalSince1970: 100000))
    var request = CapsuleRequest(context: CapsuleSearchContext(query: "My soundtrack"), tracks: [])
    request.options = CapsuleOptions(mode: .photos, subject: "My photos")
    request.options?.order = .chronological
    let capsule = try await store.save(request: request, images: [later, earlier], title: "Holiday")
    #expect(capsule.isPersonal)
    #expect(capsule.canWatch)
    #expect(capsule.montageFrames.map(\.image.file) == [earlier.file, later.file])
    let restored = await PersonalCinemaStore(directory: directory).load()
    #expect(restored == [capsule])
    let bytes = try await store.imageData(earlier.localFile!)
    #expect(UIImage(data: bytes)?.size == CGSize(width: 40, height: 30))
    try await store.remove(capsule)
    #expect(await store.load().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }
  @Test func badImagesAndPathTraversalCannotBeImportedOrRead() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PersonalCinemaStore(directory: directory)
    await #expect(throws: PersonalCinemaError.self) { try await store.importImage(Data("bad image".utf8)) }
    #expect(PersonalCinemaStore.imageURL("../photo.jpg") == nil)
    #expect(PersonalCinemaStore.imageURL("/private/photo.jpg") == nil)
    #expect(await store.load().isEmpty)
  }

  @Test func editingPreservesIdentityPhotosAndTracksAcrossReload() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PersonalCinemaStore(directory: directory)
    let data = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { context in
      UIColor.green.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
    }.pngData()!
    let later = try await store.importImage(data, date: Date(timeIntervalSince1970: 200000))
    let earlier = try await store.importImage(data, date: Date(timeIntervalSince1970: 100000))
    var request = CapsuleRequest(context: CapsuleSearchContext(query: "Holiday soundtrack"), tracks: [
      SuggestedTrack(id: "song", title: "Holiday", artist: "Madonna", album: "Madonna", corrected: false)
    ])
    request.options = CapsuleOptions(mode: .photos, subject: "My photos")
    let original = try await store.save(request: request, images: [later, earlier], title: "Holiday")
    let importedBytes = try await store.imageData(earlier.localFile!)
    var options = try #require(request.options)
    options.order = .chronological
    options.motion = .still
    options.pace = .relaxed
    let updated = try await store.update(original, options: options)
    let reloaded = await PersonalCinemaStore(directory: directory).load()
    #expect(reloaded == [updated])
    #expect(updated.id == original.id)
    #expect(updated.request.tracks == original.request.tracks)
    #expect(updated.request.options == options)
    #expect(updated.montageFrames.map(\.image.file) == [earlier.file, later.file])
    #expect(try await store.imageData(earlier.localFile!) == importedBytes)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 3)
  }
}
