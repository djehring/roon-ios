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
