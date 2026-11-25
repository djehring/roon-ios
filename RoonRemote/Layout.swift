import SwiftUI

/// Geometry shared by the compact and regular presentations of the iOS app.
///
/// Every value is keyed on horizontal size class rather than device idiom. An
/// iPad is compact in Slide Over and in a narrow Stage Manager window, so an
/// idiom check would leave sidebar-width geometry in a 320pt window.
enum Layout {
  static let gridSpacing: CGFloat = 12

  /// Widest the Now Playing cover art may draw. Compact keeps the 340pt the
  /// iPhone has always used.
  static func heroArtWidth(_ width: UserInterfaceSizeClass?) -> CGFloat {
    width == .regular ? 520 : 340
  }

  /// Smallest Library card on a regular-width layout, which fills the extra
  /// width with more columns rather than wider cards.
  static let regularLibraryCardMinimum: CGFloat = 200

  static let compactLibraryColumnCount = 2

  static func libraryColumns(_ width: UserInterfaceSizeClass?) -> [GridItem] {
    guard width == .regular else {
      return Array(
        repeating: GridItem(.flexible(), spacing: gridSpacing),
        count: compactLibraryColumnCount
      )
    }
    return [GridItem(.adaptive(minimum: regularLibraryCardMinimum), spacing: gridSpacing)]
  }

  static func onboardingContentWidth(_ width: UserInterfaceSizeClass?) -> CGFloat? {
    width == .regular ? 620 : nil
  }

  static func onboardingControlHeight(_ width: UserInterfaceSizeClass?) -> CGFloat {
    width == .regular ? 58 : 48
  }

  static func onboardingTitleSize(_ width: UserInterfaceSizeClass?) -> CGFloat {
    width == .regular ? 36 : 28
  }

  /// Comfortable measure for long-form prose. Full-screen story text would
  /// otherwise run the whole width of a landscape iPad, which is unreadable.
  static let readingWidth: CGFloat = 720

  static func storyTitleSize(_ width: UserInterfaceSizeClass?) -> CGFloat {
    width == .regular ? 34 : 22
  }
}

enum RegularNowPlayingLayout: Equatable {
  case stacked
  case sideBySide

  static let sideBySideMinimumWidth: CGFloat = 860

  static func mode(for size: CGSize) -> Self {
    size.width >= sideBySideMinimumWidth && size.width > size.height
      ? .sideBySide
      : .stacked
  }

  enum TextScale: Equatable {
    case standard
    case compact
  }

  /// Below this height the side-by-side controls column cannot hold the full
  /// type scale. An iPhone Duo in landscape, or an iPad mini, would otherwise
  /// open with the transport scrolled out of view under a long title.
  static let compactControlsMaximumHeight: CGFloat = 700

  static func textScale(contentHeight: CGFloat) -> TextScale {
    contentHeight < compactControlsMaximumHeight ? .compact : .standard
  }

  static func artWidth(containerWidth: CGFloat, mode: Self) -> CGFloat {
    switch mode {
    case .stacked:
      max(0, min(440, containerWidth - 64))
    case .sideBySide:
      max(0, min(520, containerWidth * 0.46))
    }
  }
}

/// Now Playing split around the fold of a half-closed iPhone Duo. Artwork takes
/// the region away from the hand, top on a table or leading like a book, and
/// every control moves to the other region, clear of the crease.
struct FoldedNowPlayingLayout: Equatable {
  enum Pose: Equatable {
    case tabletop
    case book
  }

  let pose: Pose
  let artRegion: CGSize
  let controlsRegion: CGSize
  let foldThickness: CGFloat

  init?(container: CGSize, fold: CGRect) {
    if fold.width >= fold.height {
      pose = .tabletop
      artRegion = CGSize(width: container.width, height: fold.minY)
      controlsRegion = CGSize(width: container.width, height: container.height - fold.maxY)
      foldThickness = fold.height
    } else {
      pose = .book
      artRegion = CGSize(width: fold.minX, height: container.height)
      controlsRegion = CGSize(width: container.width - fold.maxX, height: container.height)
      foldThickness = fold.width
    }
    guard artRegion.width > 0, artRegion.height > 0,
          controlsRegion.width > 0, controlsRegion.height > 0
    else { return nil }
  }

  var artWidth: CGFloat {
    max(0, min(520, artRegion.width - 64, artRegion.height - 64))
  }
}

/// How AI Search divides a regular-width column.
///
/// The detail pane only earns its space once a result exists to fill it and
/// the query column can still hold its field, mic, and Go button side by side.
/// An unfolded iPhone is barely wider than those two minimums, so an
/// always-on detail pane spent half that width on a placeholder and squeezed
/// the query field until its text truncated.
enum AISearchLayout: Equatable {
  case single
  case split

  static let queryMinimumWidth: CGFloat = 380
  static let queryIdealWidth: CGFloat = 620
  static let detailMinimumWidth: CGFloat = 420

  static var splitMinimumWidth: CGFloat { queryMinimumWidth + detailMinimumWidth }

  static func mode(containerWidth: CGFloat, hasResults: Bool) -> Self {
    hasResults && containerWidth >= splitMinimumWidth ? .split : .single
  }

  /// Width for the query column. A single column keeps song rows to a
  /// readable measure rather than running the width of a landscape iPad.
  static func queryWidth(containerWidth: CGFloat, mode: Self) -> CGFloat {
    let available = max(0, containerWidth)
    switch mode {
    case .single:
      return min(available, Layout.readingWidth)
    case .split:
      return max(queryMinimumWidth, min(queryIdealWidth, available - detailMinimumWidth))
    }
  }
}

enum RegularShellLayout {
  static let persistentSidebarMinimumWidth: CGFloat = 1100

  static func prefersPersistentSidebar(containerWidth: CGFloat) -> Bool {
    containerWidth >= persistentSidebarMinimumWidth
  }
}
