import Foundation
import Testing

/// The sidebar and `store.selectedTab` track each other, and the store's side is
/// the coarser of the two: several rows share a tab, and Siri, the Now Playing
/// toolbar shortcuts, and action recording all move it from outside the sidebar.
@Suite("Sidebar selection sync")
struct SidebarSelectionTests {
  private let library: [LibraryEntry] = [
    .init(id: "browse", title: "Browse", symbol: "safari", hierarchy: "browse"),
    .init(id: "library", title: "Library", symbol: "books.vertical", hierarchy: "browse"),
    .init(id: "albums", title: "Albums", symbol: "opticaldisc", hierarchy: "albums"),
    .init(id: "radios", title: "Radios", symbol: "radio", hierarchy: "internet_radio"),
  ]

  private func selection(
    for tab: AppTab,
    current: SidebarItem?,
    searchSegment: SearchSegment = .ai,
    pending: String? = nil
  ) -> SidebarItem? {
    SidebarItem.selection(
      for: tab,
      current: current,
      library: library,
      searchSegment: searchSegment,
      pendingLibraryHierarchy: pending
    )
  }

  @Test("a tab that already matches the selection leaves it alone")
  func noChangeWhenAlreadyOnTheTab() {
    // Without this the sidebar would jump off the user's chosen Library category
    // every time a zone update round-tripped selectedTab.
    #expect(selection(for: .library, current: .library("albums")) == nil)
    #expect(selection(for: .nowPlaying, current: .nowPlaying) == nil)
    #expect(selection(for: .search, current: .search(.camera)) == nil)
    #expect(selection(for: .settings, current: .settings) == nil)
  }

  @Test("moving to Now Playing or Settings selects that row")
  func singleRowTabs() {
    #expect(selection(for: .nowPlaying, current: .settings) == .nowPlaying)
    #expect(selection(for: .settings, current: .nowPlaying) == .settings)
  }

  @Test("moving to Search selects the row for the store's current mode")
  func searchFollowsTheStoredSegment() {
    #expect(selection(for: .search, current: .nowPlaying, searchSegment: .ai) == .search(.ai))
    #expect(
      selection(for: .search, current: .nowPlaying, searchSegment: .camera) == .search(.camera)
    )
  }

  @Test("moving to Library with nothing pending lands on the first category")
  func libraryFallsBackToTheFirstCategory() {
    #expect(selection(for: .library, current: .nowPlaying) == .library("browse"))
  }

  @Test("a pending hierarchy defers the Library selection to whoever handles it")
  func pendingHierarchyWins() {
    // runToolbar sets selectedTab and libraryLaunchHierarchy together. Selecting
    // the first category here would open the wrong browse page, then jump.
    #expect(selection(for: .library, current: .nowPlaying, pending: "playlists") == nil)
  }

  @Test("moving to Rooms selects its destination")
  func roomsIsReachable() {
    #expect(selection(for: .rooms, current: .nowPlaying) == .rooms)
    #expect(selection(for: .rooms, current: .library("albums")) == .rooms)
  }

  @Test("an empty library cannot be selected into")
  func emptyLibrary() {
    let empty = SidebarItem.selection(
      for: .library,
      current: .nowPlaying,
      library: [],
      searchSegment: .ai,
      pendingLibraryHierarchy: nil
    )

    #expect(empty == nil)
  }

  @Test("no current selection still resolves")
  func noCurrentSelection() {
    #expect(selection(for: .nowPlaying, current: nil) == .nowPlaying)
    #expect(selection(for: .library, current: nil) == .library("browse"))
  }

  @Test("a launch hierarchy resolves to the row that declares it")
  func launchHierarchyFindsItsRow() {
    #expect(SidebarItem.libraryRow(forHierarchy: "albums", in: library) == .library("albums"))
    #expect(
      SidebarItem.libraryRow(forHierarchy: "internet_radio", in: library) == .library("radios")
    )
  }

  @Test("a hierarchy shared by two rows resolves to the first")
  func sharedHierarchyPicksTheFirstRow() {
    // Browse and Library are separate rows over the same "browse" hierarchy.
    #expect(SidebarItem.libraryRow(forHierarchy: "browse", in: library) == .library("browse"))
  }

  @Test("a hierarchy with no row falls back to itself")
  func unknownHierarchyStillOpens() {
    // A recorded custom action can name a hierarchy that has no sidebar row; it
    // still has to open something rather than selecting nothing.
    #expect(SidebarItem.libraryRow(forHierarchy: "tags", in: library) == .library("tags"))
  }
}
