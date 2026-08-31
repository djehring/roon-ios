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

  @Test("sorting puts titles in alphabetical order")
  func sortsAlphabetically() {
    let items = [
      node("c", "Cara Dillon"),
      node("a", "An Introduction to Qobuz"),
      node("s", "Stephane Wrembel"),
    ]

    #expect(LibraryIndex.sorted(items).map(\.id) == ["a", "c", "s"])
  }

  @Test("sorting ignores case")
  func sortIgnoresCase() {
    let items = [node("b", "bathtime"), node("a", "Andrea Motis")]

    #expect(LibraryIndex.sorted(items).map(\.id) == ["a", "b"])
  }

  @Test("numbers inside a title sort by value, not by digit")
  func naturalNumberOrder() {
    let items = [
      node("10", "Bathtime 10"),
      node("2", "Bathtime 2a"),
      node("9", "Bathtime 9"),
      node("bare", "Bathtime"),
    ]

    #expect(LibraryIndex.sorted(items).map(\.id) == ["bare", "2", "9", "10"])
  }

  @Test("titles outside A–Z sort last, where the index bar puts the # key")
  func nonLettersSortLast() {
    let items = [
      node("number", "1958 Miles"),
      node("letter", "Kind of Blue"),
      node("symbol", "…And Justice for All"),
    ]
    let sorted = LibraryIndex.sorted(items)

    #expect(sorted.first?.id == "letter")
    #expect(Set(sorted.dropFirst().map(\.id)) == ["number", "symbol"])
  }

  @Test("the sorted order is what the index bar then jumps against")
  func sortedOrderAgreesWithJumping() {
    let items = LibraryIndex.sorted([
      node("number", "1958 Miles"),
      node("s", "Stephane Wrembel"),
      node("a", "An Introduction to Qobuz"),
    ])

    #expect(LibraryIndex.jumpTarget(for: "A", in: items) == "a")
    #expect(LibraryIndex.jumpTarget(for: "S", in: items) == "s")
    // The # key sits after Z in the bar, so its target must be after the
    // letters in the list too.
    #expect(items.last?.id == "number")
  }

  @Test("two playlists with the same name keep a stable order")
  func stableForDuplicateTitles() {
    let items = [node("second", "Bathtime 9"), node("first", "Bathtime 9")]

    #expect(LibraryIndex.sorted(items).map(\.id) == ["first", "second"])
  }

  @Test("an empty title sorts with the non-letters rather than crashing")
  func emptyTitle() {
    let items = [node("empty", ""), node("letter", "Blue Train")]

    #expect(LibraryIndex.sorted(items).map(\.id) == ["letter", "empty"])
  }

  @Test("the playlists hierarchy root is alphabetized")
  func alphabetizesPlaylistsHierarchy() {
    let page = BrowsePage(
      title: "Recently Played",
      items: [node("c", "Cara Dillon"), node("a", "An Introduction to Qobuz")]
    )
    let sorted = LibraryIndex.alphabetizedPlaylists(page, hierarchy: "playlists", itemKey: nil)

    #expect(sorted.items.map(\.id) == ["a", "c"])
  }

  @Test("a page titled Playlists is alphabetized even under browse")
  func alphabetizesPlaylistsReachedFromBrowse() {
    let page = BrowsePage(
      title: "Playlists",
      items: [node("c", "Cara Dillon"), node("a", "An Introduction to Qobuz")]
    )
    let sorted = LibraryIndex.alphabetizedPlaylists(page, hierarchy: "browse", itemKey: "k-playlists")

    #expect(sorted.items.map(\.id) == ["a", "c"])
  }

  @Test("tracks inside a playlist keep their order")
  func leavesPlaylistContentsAlone() {
    let page = BrowsePage(
      title: "Bathtime 9",
      items: [node("2", "Second"), node("1", "First")]
    )
    let same = LibraryIndex.alphabetizedPlaylists(page, hierarchy: "playlists", itemKey: "k-bathtime")

    #expect(same.items.map(\.id) == ["2", "1"])
  }

  @Test("albums and other lists are left in the core's order")
  func leavesOtherListsAlone() {
    let page = BrowsePage(
      title: "Albums",
      items: [node("c", "Cara Dillon"), node("a", "An Introduction to Qobuz")]
    )
    let same = LibraryIndex.alphabetizedPlaylists(page, hierarchy: "albums", itemKey: nil)

    #expect(same.items.map(\.id) == ["c", "a"])
  }

  @Test("a search prompt stays at the top of the playlist list")
  func keepsPromptFirst() {
    var prompt = node("search", "Search")
    prompt.isPrompt = true
    let page = BrowsePage(
      title: "Playlists",
      items: [prompt, node("c", "Cara Dillon"), node("a", "An Introduction to Qobuz")]
    )
    let sorted = LibraryIndex.alphabetizedPlaylists(page, hierarchy: "playlists", itemKey: nil)

    #expect(sorted.items.map(\.id) == ["search", "a", "c"])
  }
}
