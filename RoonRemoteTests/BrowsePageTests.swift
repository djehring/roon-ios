import Foundation
import Testing

@Suite("Artist discography")
@MainActor
struct ArtistDiscographyTests {
  private func node(_ title: String, key: String, hint: String = "list") -> BrowseNode {
    BrowseNode(
      id: key, title: title, symbol: "person", actions: [], isPrompt: false,
      children: [], itemKey: key, hierarchy: "search", hint: hint
    )
  }

  @Test func cleansArtistCreditsAndRejectsBlankNames() {
    #expect(ArtistDiscography("  [[123|Miles Davis]]  ")?.name == "Miles Davis")
    #expect(ArtistDiscography(" \n ") == nil)
    #expect(ArtistDiscography("Miles Davis") != ArtistDiscography("Miles Davis"))
  }

  @Test(arguments: ["Discography", "Albums"])
  func opensMatchingArtistAlbums(section: String) async throws {
    let artist = try #require(ArtistDiscography("Miles Davis"))
    var requests: [String] = []
    let page = await artist.load { key, input in
      requests.append(key ?? "root")
      switch key {
      case nil:
        #expect(input == "Miles Davis")
        return BrowsePage(title: "Search", items: [node("Artists", key: "artists")])
      case "artists":
        return BrowsePage(title: "Artists", items: [
          node("Miles Davis Quintet", key: "wrong"),
          node("[[123|MILES DAVIS]]", key: "miles"),
        ])
      case "miles":
        return BrowsePage(title: "Miles Davis", items: [node(section, key: "albums")])
      case "albums":
        return BrowsePage(title: section, items: [node("Kind of Blue", key: "kind-of-blue")])
      default:
        Issue.record("Opened an unexpected browse row")
        return BrowsePage(title: "Unexpected", items: [])
      }
    }
    #expect(requests == ["root", "artists", "miles", "albums"])
    #expect(page.title == "Miles Davis")
    #expect(page.items.first?.itemKey == "kind-of-blue")
    #expect(page.errorMessage == nil)
  }

  @Test func acceptsAlbumsDirectlyOnArtistPage() async throws {
    let artist = try #require(ArtistDiscography("Björk"))
    let page = await artist.load { key, _ in
      switch key {
      case nil: BrowsePage(title: "Search", items: [node("Artists", key: "artists")])
      case "artists": BrowsePage(title: "Artists", items: [node("Bjork", key: "artist")])
      default: BrowsePage(title: "Bjork", items: [node("Debut", key: "debut")])
      }
    }
    #expect(page.title == "Björk")
    #expect(page.items.first?.title == "Debut")
  }

  @Test func opensStreamingDiscographyForAnArtistWithNoSavedAlbums() async throws {
    let artist = try #require(ArtistDiscography("Cédric Tiberghien"))
    var opened: [String] = []
    let page = await artist.load { key, input in
      opened.append(key ?? "root")
      if key == nil {
        #expect(input == "Cedric Tiberghien")
        return BrowsePage(title: "Search", items: [node("Artists", key: "artists"), node("Albums", key: "albums")])
      }
      #expect(key == "albums")
      var match = node("Beethoven: Violin Sonatas Op. 12 & Op. 24", key: "beethoven")
      match.subtitle = "[[16206970|Alina Ibragimova]], [[9095290|Cédric Tiberghien]]"
      var other = node("Another recording", key: "other")
      other.subtitle = "[[1|Another Performer]]"
      return BrowsePage(title: "Albums", items: [match, other])
    }
    #expect(opened == ["root", "albums"])
    #expect(page.title == "Cédric Tiberghien")
    #expect(page.items.map(\.itemKey) == ["beethoven"])
  }

  @Test func neverOpensAnActionOrADifferentArtist() async throws {
    let artist = try #require(ArtistDiscography("Miles Davis"))
    var requests = 0
    let page = await artist.load { key, _ in
      requests += 1
      if key == nil {
        return BrowsePage(title: "Search", items: [node("Artists", key: "artists")])
      }
      return BrowsePage(title: "Artists", items: [
        node("Miles Davis Quintet", key: "quintet"),
        node("Miles Davis", key: "play", hint: "action"),
        node("Miles Davis", key: "actions", hint: "action_list"),
      ])
    }
    #expect(requests == 2)
    #expect(page.items.isEmpty)
    #expect(page.errorMessage?.contains("Miles Davis") == true)
  }

  @Test func preservesLoadErrors() async throws {
    let artist = try #require(ArtistDiscography("Miles Davis"))
    let page = await artist.load { _, _ in
      BrowsePage(title: "Couldn't load", items: [], errorMessage: "Bridge is offline")
    }
    #expect(page.errorMessage == "Bridge is offline")
  }
}

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

@Suite("Browse search")
struct BrowseSearchTests {
  private var prompt: BrowseNode {
    BrowseNode(
      id: "search",
      title: "Search",
      subtitle: nil,
      symbol: "magnifyingglass",
      actions: ["Search"],
      isPrompt: true,
      children: [],
      itemKey: "k-search",
      imageKey: nil,
      hierarchy: "albums",
      hint: nil
    )
  }

  @Test("a typed query becomes a search that the stack can push")
  func submittedQuery() {
    let query = BrowseSearch.submitted(
      hierarchy: "albums",
      child: prompt,
      prompt: "  miles  "
    )

    #expect(query?.hierarchy == "albums")
    #expect(query?.itemKey == "k-search")
    #expect(query?.title == "Search")
    #expect(query?.input == "miles")
  }

  @Test("whitespace alone is not a search")
  func blankPrompt() {
    #expect(BrowseSearch.submitted(hierarchy: "albums", child: prompt, prompt: "   ") == nil)
    #expect(BrowseSearch.submitted(hierarchy: "albums", child: prompt, prompt: "") == nil)
  }

  @Test("the same query twice is still two stack entries")
  func uniqueEachSubmit() {
    let first = BrowseSearch.submitted(hierarchy: "albums", child: prompt, prompt: "miles")
    let second = BrowseSearch.submitted(hierarchy: "albums", child: prompt, prompt: "miles")

    #expect(first != second)
  }
}
