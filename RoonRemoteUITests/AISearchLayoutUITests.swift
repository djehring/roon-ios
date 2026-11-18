import XCTest

final class AISearchLayoutUITests: XCTestCase {
  override func setUp() { super.setUp(); continueAfterFailure = false }

  /// A detail pane may only take width from the query column when it has a
  /// result to show. An unfolded iPhone is narrow enough that an always-on
  /// pane truncated the query field to hold a placeholder.
  @MainActor func testResultsKeepTheQueryFieldWideOnARegularWidthColumn() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_SEARCH_PREVIEW_SEGMENT"] = "ai"
    app.launch()
    XCTAssertTrue(app.staticTexts["Peace Piece"].waitForExistence(timeout: 10))
    try XCTSkipIf(
      app.tabBars.buttons["Search"].exists,
      "Compact width has no detail pane to balance."
    )
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "AI Search with results"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    XCTAssertFalse(
      app.staticTexts["Ask for some music"].exists,
      "the detail pane must show the selected result, not a placeholder"
    )
    XCTAssertGreaterThan(app.textFields.firstMatch.frame.width, 300)
  }
}
