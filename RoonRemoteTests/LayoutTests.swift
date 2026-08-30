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
}
