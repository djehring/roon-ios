import Foundation
import Testing

@Suite("Library A–Z index")
struct LibraryIndexTests {
  private func node(_ id: String, _ title: String) -> BrowseNode {
    BrowseNode(
      id: id,
      title: title,
      subtitle: nil,
      symbol: "music.note",
      actions: [],
      isPrompt: false,
      children: [],
      itemKey: nil,
      imageKey: nil,
      hierarchy: nil,
      hint: nil
    )
  }

  @Test("exposes A through Z followed by the numeric bucket")
  func letters() {
    #expect(LibraryIndex.letters.count == 27)
    #expect(LibraryIndex.letters.first == "A")
    #expect(LibraryIndex.letters.last == "#")
  }

  @Test("a letter selects the first matching title")
  func firstMatchingTitle() {
    let items = [
      node("b", "Blue Train"),
      node("a1", "A Love Supreme"),
      node("a2", "All Blues"),
    ]

    #expect(LibraryIndex.jumpTarget(for: "A", in: items) == "a1")
    #expect(LibraryIndex.jumpTarget(for: "B", in: items) == "b")
  }

  @Test("matching is case insensitive")
  func caseInsensitive() {
    #expect(
      LibraryIndex.jumpTarget(for: "K", in: [node("kind", "kind of blue")]) == "kind"
    )
  }

  @Test("a letter with no match does not move the list")
  func noMatch() {
    #expect(
      LibraryIndex.jumpTarget(for: "Z", in: [node("kind", "Kind of Blue")]) == nil
    )
  }

  @Test("the numeric bucket finds a title that does not begin with a letter")
  func numericBucket() {
    let items = [
      node("alpha", "A Love Supreme"),
      node("number", "1958 Miles"),
      node("symbol", "…And Justice for All"),
    ]

    #expect(LibraryIndex.jumpTarget(for: "#", in: items) == "number")
  }

  @Test("the numeric bucket ignores empty titles without crashing")
  func numericBucketWithEmptyTitle() {
    let items = [node("empty", ""), node("number", "1958 Miles")]

    #expect(LibraryIndex.jumpTarget(for: "#", in: items) == "number")
  }
}
