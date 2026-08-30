import Foundation
import Testing
import UniformTypeIdentifiers

@Suite("Library drag item")
struct LibraryDragItemTests {
  @Test("round-trips the data a room drop needs")
  func codableRoundTrip() throws {
    let item = LibraryDragItem(
      hierarchy: "albums",
      itemKey: "kind-of-blue",
      title: "Kind of Blue",
      hint: "album"
    )

    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(LibraryDragItem.self, from: data)

    #expect(decoded == item)
  }

  @Test("a missing hint survives the transfer")
  func optionalHint() throws {
    let item = LibraryDragItem(
      hierarchy: "playlists",
      itemKey: "late-night",
      title: "Late Night",
      hint: nil
    )

    let decoded = try JSONDecoder().decode(
      LibraryDragItem.self,
      from: JSONEncoder().encode(item)
    )

    #expect(decoded.hint == nil)
  }

  @Test("uses an app-owned exported content type")
  func contentType() {
    #expect(UTType.roonLibraryItem.identifier == "com.djehring.roonremote.library-item")
    #expect(UTType.roonLibraryItem.isDeclared)
  }
}
