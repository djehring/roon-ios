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
    await store.remove(capsule)
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
}
