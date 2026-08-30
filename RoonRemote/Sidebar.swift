import Foundation

/// A destination in the regular-width sidebar.
///
/// The sidebar carries more destinations than `AppTab` has cases: every Library
/// category and both Search modes get their own row, which is what lets the iPad
/// drop the Library landing grid and the Search segmented control. `tab` maps a
/// row back onto the cross-platform selection that the store, Siri, and the
/// Now Playing toolbar shortcuts all still speak in.
enum SidebarItem: Hashable {
  case nowPlaying
  case library(LibraryEntry.ID)
  case search(SearchSegment)
  case settings

  var tab: AppTab {
    switch self {
    case .nowPlaying: .nowPlaying
    case .library: .library
    case .search: .search
    case .settings: .settings
    }
  }
}

extension SidebarItem {
  /// What the sidebar should select when the store's tab changes underneath it,
  /// or `nil` to leave the current selection alone.
  ///
  /// The store's tab is the coarser of the two: Siri, the Now Playing toolbar
  /// shortcuts, and action recording all move it, and several sidebar rows share
  /// a tab, so a tab alone often does not name a row.
  static func selection(
    for tab: AppTab,
    current: SidebarItem?,
    library: [LibraryEntry],
    searchSegment: SearchSegment,
    pendingLibraryHierarchy: String?
  ) -> SidebarItem? {
    guard current?.tab != tab else { return nil }
    switch tab {
    case .nowPlaying:
      return .nowPlaying
    case .settings:
      return .settings
    case .search:
      return .search(searchSegment)
    case .library:
      // A pending hierarchy names the row to open, so defer to whoever handles
      // it rather than landing on the first category and jumping again.
      guard pendingLibraryHierarchy == nil else { return nil }
      return library.first.map { .library($0.id) }
    case .rooms:
      // No sidebar row until the Rooms destination exists.
      return nil
    }
  }

  /// The row for a hierarchy named by a toolbar shortcut or a recorded action.
  /// An unknown hierarchy falls back to itself: it has no sidebar row, but still
  /// resolves to something browsable.
  static func libraryRow(forHierarchy hierarchy: String, in library: [LibraryEntry]) -> SidebarItem {
    .library(library.first { $0.hierarchy == hierarchy }?.id ?? hierarchy)
  }
}

struct SidebarRow: Identifiable, Hashable {
  let item: SidebarItem
  let title: String
  let symbol: String

  var id: SidebarItem { item }
}

struct SidebarSection: Identifiable, Hashable {
  let id: String
  /// `nil` draws the rows without a header, for destinations that do not group.
  let title: String?
  let rows: [SidebarRow]
}

extension SidebarSection {
  static func all(library: [LibraryEntry]) -> [SidebarSection] {
    [
      SidebarSection(
        id: "listen",
        title: nil,
        rows: [SidebarRow(item: .nowPlaying, title: "Now Playing", symbol: "play.square.fill")]
      ),
      SidebarSection(
        id: "library",
        title: "Library",
        rows: library.map { entry in
          SidebarRow(item: .library(entry.id), title: entry.title, symbol: entry.symbol)
        }
      ),
      SidebarSection(
        id: "search",
        title: "Search",
        rows: [
          SidebarRow(item: .search(.ai), title: "AI Search", symbol: "sparkles"),
          SidebarRow(item: .search(.camera), title: "Cover Camera", symbol: "camera.fill"),
        ]
      ),
      SidebarSection(
        id: "app",
        title: nil,
        rows: [SidebarRow(item: .settings, title: "Settings", symbol: "gearshape")]
      ),
    ]
  }
}
