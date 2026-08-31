import Foundation
import Testing

@Suite("Browse page")
struct BrowsePageTests {
  private func node(_ title: String, itemKey: String?) -> BrowseNode {
    BrowseNode(
      id: title,
      title: title,
      subtitle: nil,
      symbol: "folder",
      actions: [],
      isPrompt: false,
      children: [],
      itemKey: itemKey,
      imageKey: nil,
      hierarchy: "browse",
      hint: nil
    )
  }

  private var root: BrowsePage {
    BrowsePage(
      title: "Browse",
      items: [
        node("Library", itemKey: "k-library"),
        node("Playlists", itemKey: "k-playlists"),
        node("Settings", itemKey: "k-settings"),
      ]
    )
  }

  @Test("finds the key for a named row")
  func findsNamedChild() {
    #expect(root.itemKey(forChildTitled: "Library") == "k-library")
    #expect(root.itemKey(forChildTitled: "Settings") == "k-settings")
  }

  @Test("a row the core does not offer resolves to nothing")
  func missingChild() {
    // The caller falls back to showing the root, which is the old behaviour
    // rather than an empty page.
    #expect(root.itemKey(forChildTitled: "Tidal") == nil)
  }

  @Test("matching is exact, so a partial name does not open the wrong row")
  func exactMatch() {
    #expect(root.itemKey(forChildTitled: "Lib") == nil)
    #expect(root.itemKey(forChildTitled: "library") == nil)
  }

  @Test("a row carrying no key resolves to nothing")
  func childWithoutKey() {
    let page = BrowsePage(title: "Browse", items: [node("Library", itemKey: nil)])

    #expect(page.itemKey(forChildTitled: "Library") == nil)
  }
}
