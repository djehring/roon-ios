import Foundation
import Testing

@Suite("Sidebar")
struct SidebarTests {
  private let library: [LibraryEntry] = [
    .init(id: "browse", title: "Browse", symbol: "safari", hierarchy: "browse"),
    .init(id: "albums", title: "Albums", symbol: "opticaldisc", hierarchy: "albums"),
    .init(id: "radios", title: "Radios", symbol: "radio", hierarchy: "internet_radio"),
  ]

  private var sections: [SidebarSection] { SidebarSection.all(library: library) }

  private var rows: [SidebarRow] { sections.flatMap(\.rows) }

  @Test("sections appear in a fixed order")
  func sectionOrder() {
    #expect(sections.map(\.id) == ["listen", "library", "search", "app"])
  }

  @Test("section ids stay unique even without headers")
  func sectionIdsAreUnique() {
    // Two sections draw without a header, so they cannot derive an id from the
    // title they do not have.
    let headerless = sections.filter { $0.title == nil }
    #expect(headerless.count == 2)
    #expect(Set(sections.map(\.id)).count == sections.count)
  }

  @Test("the Library section mirrors the store's roots in order")
  func libraryRowsMirrorTheStore() throws {
    let section = try #require(sections.first { $0.id == "library" })
    let libraryRows = section.rows

    #expect(libraryRows.map(\.title) == ["Browse", "Albums", "Radios"])
    #expect(libraryRows.map(\.symbol) == ["safari", "opticaldisc", "radio"])
    #expect(libraryRows.map(\.item) == [
      .library("browse"), .library("albums"), .library("radios"),
    ])
  }

  @Test("an empty library leaves the other sections intact")
  func emptyLibrary() {
    let empty = SidebarSection.all(library: [])

    #expect(empty.map(\.id) == ["listen", "library", "search", "app"])
    #expect(empty.first { $0.id == "library" }?.rows.isEmpty == true)
    #expect(empty.flatMap(\.rows).contains { $0.item == .nowPlaying })
  }

  @Test("every search mode gets a row")
  func searchRowsCoverEverySegment() {
    // Guards against adding a SearchSegment case and leaving it unreachable on
    // iPad, where the segmented control no longer exists to expose it.
    let offered = rows.compactMap { row -> SearchSegment? in
      guard case let .search(segment) = row.item else { return nil }
      return segment
    }

    #expect(Set(offered) == Set(SearchSegment.allCases))
  }

  @Test("rows are uniquely identified so list selection cannot be ambiguous")
  func rowIdsAreUnique() {
    #expect(Set(rows.map(\.id)).count == rows.count)
  }

  @Test("every row maps onto the cross-platform tab the store speaks in")
  func tabMapping() {
    #expect(SidebarItem.nowPlaying.tab == .nowPlaying)
    #expect(SidebarItem.library("albums").tab == .library)
    #expect(SidebarItem.search(.ai).tab == .search)
    #expect(SidebarItem.search(.camera).tab == .search)
    #expect(SidebarItem.settings.tab == .settings)
  }

  @Test("Library rows differ by category rather than collapsing onto one tab row")
  func libraryItemsAreDistinct() {
    let items = rows.map(\.item).filter { $0.tab == .library }

    #expect(items.count == library.count)
    #expect(Set(items).count == library.count)
  }

  @Test("no row claims the Rooms tab yet")
  func roomsIsNotReachable() {
    // Rooms arrives with its own destination; this fails when a row is added
    // without one, which would select a tab the shell cannot render.
    #expect(!rows.contains { $0.item.tab == .rooms })
  }
}
