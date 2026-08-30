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

  static func artWidth(containerWidth: CGFloat, mode: Self) -> CGFloat {
    switch mode {
    case .stacked:
      max(0, min(440, containerWidth - 64))
    case .sideBySide:
      max(0, min(520, containerWidth * 0.46))
    }
  }
}

enum RegularShellLayout {
  static let persistentSidebarMinimumWidth: CGFloat = 1100

  static func prefersPersistentSidebar(containerWidth: CGFloat) -> Bool {
    containerWidth >= persistentSidebarMinimumWidth
  }
}
