import SwiftUI
import Testing

@Suite("Layout")
struct LayoutTests {
  @Test("regular width gets a wider Now Playing hero than compact")
  func heroArtWidth() {
    let compact = Layout.heroArtWidth(.compact)
    let regular = Layout.heroArtWidth(.regular)

    #expect(regular > compact)
    #expect(compact == 340, "compact must keep the width the iPhone already draws")
  }

  @Test("an unknown size class is treated as compact")
  func heroArtWidthWithoutSizeClass() {
    #expect(Layout.heroArtWidth(nil) == Layout.heroArtWidth(.compact))
  }

  @Test("compact keeps a fixed two column Library grid")
  func compactLibraryColumns() {
    #expect(Layout.libraryColumns(.compact).count == Layout.compactLibraryColumnCount)
    #expect(Layout.libraryColumns(nil).count == Layout.compactLibraryColumnCount)
  }

  @Test("regular width uses a single adaptive Library column that fills the width")
  func regularLibraryColumns() {
    // One adaptive GridItem, rather than a fixed count, is what lets a 1024pt
    // iPad draw more cards instead of stretching two of them.
    #expect(Layout.libraryColumns(.regular).count == 1)
  }

  @Test("regular Library cards stay narrower than the compact hero")
  func regularCardMinimumIsSane() {
    // A minimum wider than a compact screen would collapse the grid to one
    // column on an iPad in Slide Over.
    #expect(Layout.regularLibraryCardMinimum < Layout.heroArtWidth(.compact))
    #expect(Layout.regularLibraryCardMinimum > 0)
  }

  @Test("Now Playing stacks below the wide-layout threshold")
  func nowPlayingStacksAtPortraitDetailWidth() {
    #expect(RegularNowPlayingLayout.mode(for: CGSize(width: 740, height: 1000)) == .stacked)
    #expect(
      RegularNowPlayingLayout.mode(
        for: CGSize(
          width: RegularNowPlayingLayout.sideBySideMinimumWidth - 1,
          height: 700
        )
      ) == .stacked
    )
  }

  @Test("Now Playing moves side by side only in a wide landscape")
  func nowPlayingMovesSideBySide() {
    #expect(
      RegularNowPlayingLayout.mode(
        for: CGSize(
          width: RegularNowPlayingLayout.sideBySideMinimumWidth,
          height: 700
        )
      ) == .sideBySide
    )
    #expect(
      RegularNowPlayingLayout.mode(for: CGSize(width: 1100, height: 800)) == .sideBySide
    )
  }

  @Test("a full-width portrait stays stacked even after hiding the sidebar")
  func fullWidthPortraitStaysStacked() {
    #expect(
      RegularNowPlayingLayout.mode(for: CGSize(width: 1024, height: 1366)) == .stacked
    )
  }

  @Test("AI Search keeps one column until a result can fill the detail pane")
  func aiSearchStaysSingleWithoutResults() {
    #expect(AISearchLayout.mode(containerWidth: 1366, hasResults: false) == .single)
    #expect(
      AISearchLayout.mode(
        containerWidth: AISearchLayout.splitMinimumWidth,
        hasResults: true
      ) == .split
    )
  }

  @Test("AI Search keeps one column on an unfolded iPhone detail column")
  func aiSearchStaysSingleWhenNarrow() {
    // The detail column left beside a 290pt sidebar on a 1024pt display.
    #expect(AISearchLayout.mode(containerWidth: 711, hasResults: true) == .single)
    #expect(
      AISearchLayout.mode(
        containerWidth: AISearchLayout.splitMinimumWidth - 1,
        hasResults: true
      ) == .single
    )
  }

  @Test("a single AI Search column keeps song rows to a readable measure")
  func aiSearchSingleColumnWidth() {
    #expect(
      AISearchLayout.queryWidth(containerWidth: 711, mode: .single) == 711
    )
    #expect(
      AISearchLayout.queryWidth(containerWidth: 1366, mode: .single) == Layout.readingWidth
    )
    #expect(AISearchLayout.queryWidth(containerWidth: -1, mode: .single) == 0)
  }

  @Test("a split AI Search column never squeezes the query controls")
  func aiSearchSplitColumnWidth() {
    #expect(
      AISearchLayout.queryWidth(
        containerWidth: AISearchLayout.splitMinimumWidth,
        mode: .split
      ) == AISearchLayout.queryMinimumWidth
    )
    #expect(
      AISearchLayout.queryWidth(containerWidth: 1366, mode: .split)
        == AISearchLayout.queryIdealWidth
    )
    #expect(
      AISearchLayout.queryWidth(containerWidth: 1366, mode: .split)
        <= 1366 - AISearchLayout.detailMinimumWidth
    )
  }

  @Test("the shell keeps its sidebar only when there is room for both columns")
  func persistentSidebarBreakpoint() {
    #expect(!RegularShellLayout.prefersPersistentSidebar(containerWidth: 1024))
    #expect(
      !RegularShellLayout.prefersPersistentSidebar(
        containerWidth: RegularShellLayout.persistentSidebarMinimumWidth - 1
      )
    )
    #expect(
      RegularShellLayout.prefersPersistentSidebar(
        containerWidth: RegularShellLayout.persistentSidebarMinimumWidth
      )
    )
    #expect(RegularShellLayout.prefersPersistentSidebar(containerWidth: 1366))
  }

  @Test("stacked artwork respects its cap and horizontal insets")
  func stackedArtworkWidth() {
    #expect(
      RegularNowPlayingLayout.artWidth(containerWidth: 740, mode: .stacked) == 440
    )
    #expect(
      RegularNowPlayingLayout.artWidth(containerWidth: 400, mode: .stacked) == 336
    )
  }

  @Test("side-by-side artwork is proportional until capped")
  func sideBySideArtworkWidth() {
    #expect(
      RegularNowPlayingLayout.artWidth(containerWidth: 900, mode: .sideBySide) == 414
    )
    #expect(
      RegularNowPlayingLayout.artWidth(containerWidth: 1400, mode: .sideBySide) == 520
    )
  }

  @Test("artwork width never goes negative")
  func artworkWidthNeverGoesNegative() {
    #expect(
      RegularNowPlayingLayout.artWidth(containerWidth: 20, mode: .stacked) == 0
    )
    #expect(
      RegularNowPlayingLayout.artWidth(containerWidth: -1, mode: .sideBySide) == 0
    )
  }

  @Test("a fold across the display puts artwork above the controls")
  func tabletopFold() throws {
    let layout = try #require(
      FoldedNowPlayingLayout(
        container: CGSize(width: 900, height: 700),
        fold: CGRect(x: 0, y: 340, width: 900, height: 20)
      )
    )
    #expect(layout.pose == .tabletop)
    #expect(layout.artRegion == CGSize(width: 900, height: 340))
    #expect(layout.controlsRegion == CGSize(width: 900, height: 340))
    #expect(layout.artWidth == 276, "artwork must fit inside the region above the fold")
  }

  @Test("a fold down the display puts artwork beside the controls")
  func bookFold() throws {
    let layout = try #require(
      FoldedNowPlayingLayout(
        container: CGSize(width: 700, height: 900),
        fold: CGRect(x: 340, y: 0, width: 20, height: 900)
      )
    )
    #expect(layout.pose == .book)
    #expect(layout.artRegion == CGSize(width: 340, height: 900))
    #expect(layout.controlsRegion == CGSize(width: 340, height: 900))
    #expect(layout.artWidth == 276)
  }

  @Test("a fold at the container edge leaves nothing to split")
  func foldAtEdge() {
    #expect(
      FoldedNowPlayingLayout(
        container: CGSize(width: 900, height: 700),
        fold: CGRect(x: 0, y: 0, width: 900, height: 20)
      ) == nil
    )
  }

  @Test("regular onboarding is capped to a readable card")
  func regularOnboardingWidth() {
    #expect(Layout.onboardingContentWidth(.regular) == 620)
    #expect(Layout.onboardingContentWidth(.compact) == nil)
    #expect(Layout.onboardingContentWidth(nil) == nil)
  }

  @Test("story prose is held to a readable measure narrower than an iPad")
  func storyReadingWidth() {
    // Full-screen story text must not run the width of a landscape iPad.
    #expect(Layout.readingWidth < 1024)
    #expect(Layout.readingWidth > (Layout.onboardingContentWidth(.regular) ?? 0))
  }

  @Test("regular story titles scale up without changing compact")
  func storyTitleScale() {
    #expect(Layout.storyTitleSize(.compact) == 22)
    #expect(Layout.storyTitleSize(nil) == Layout.storyTitleSize(.compact))
    #expect(Layout.storyTitleSize(.regular) > Layout.storyTitleSize(.compact))
  }

  @Test("regular onboarding scales controls and titles without changing compact")
  func onboardingScale() {
    #expect(Layout.onboardingControlHeight(.compact) == 48)
    #expect(Layout.onboardingControlHeight(.regular) > Layout.onboardingControlHeight(.compact))
    #expect(Layout.onboardingTitleSize(.compact) == 28)
    #expect(Layout.onboardingTitleSize(.regular) > Layout.onboardingTitleSize(.compact))
  }

  @Test("the closed iPhone Duo's tabs reach every destination the Navigate menu offers")
  func compactTabsCoverEveryDestination() {
    // The outer screen is compact and draws these tabs. A tab missing here is a
    // destination that folding the device takes away.
    #expect(Set(AppTab.compactOrder) == Set(AppTab.allCases))
    #expect(AppTab.compactOrder.count == AppTab.allCases.count, "no tab may appear twice")
  }

  @Test("compact tabs match the regular sidebar's titles and symbols")
  func compactTabsMatchSidebarRows() {
    let rows = SidebarSection.all(library: []).flatMap(\.rows)
    for tab in AppTab.compactOrder {
      guard let row = rows.first(where: { $0.item.tab == tab && $0.title == tab.title }) else {
        // Library and Search have no single sidebar row; each splits into
        // several, so only the destinations with one row need to agree.
        continue
      }
      #expect(row.symbol == tab.symbol, "\(tab) should look the same folded and unfolded")
    }
    for tab in [AppTab.nowPlaying, .rooms, .settings] {
      #expect(rows.contains { $0.item.tab == tab && $0.title == tab.title })
    }
  }

  @Test("a short side-by-side window uses the compact type scale")
  func nowPlayingTextScale() {
    // iPhone Duo landscape leaves roughly 535pt for the controls column.
    #expect(RegularNowPlayingLayout.textScale(contentHeight: 535) == .compact)
    #expect(
      RegularNowPlayingLayout.textScale(
        contentHeight: RegularNowPlayingLayout.compactControlsMaximumHeight
      ) == .standard
    )
    #expect(RegularNowPlayingLayout.textScale(contentHeight: 900) == .standard)
  }
}
