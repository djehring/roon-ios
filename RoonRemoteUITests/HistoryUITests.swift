import XCTest

final class HistoryUITests: XCTestCase {
  override func setUp() { super.setUp(); continueAfterFailure = false }
  @MainActor private func openHistory(state: String = "normal") -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_HISTORY_STATE"] = state
    app.launch()
    if app.tabBars.buttons["Library"].waitForExistence(timeout: 5) { app.tabBars.buttons["Library"].tap() }
    if app.buttons["Show Sidebar"].exists { app.buttons["Show Sidebar"].tap() }
    let destination = app.buttons["open-history"]
    if destination.waitForExistence(timeout: 3) { destination.tap() }
    else if app.buttons["Recently played"].firstMatch.exists { app.buttons["Recently played"].firstMatch.tap() }
    else { app.staticTexts["Recently played"].firstMatch.tap() }
    XCTAssertTrue(app.navigationBars["Recently played"].waitForExistence(timeout: 8))
    return app
  }
  @MainActor func testAlbumsTracksAndExplicitReplay() {
    let app = openHistory()
    XCTAssertTrue(app.staticTexts["Kind of Blue"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["Tracks"].tap()
    XCTAssertTrue(app.staticTexts["Freddie Freeloader"].firstMatch.waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Recently played tracks"; screenshot.lifetime = .keepAlways; add(screenshot)
    app.buttons["history-track-demo-history-0"].tap()
    XCTAssertTrue(app.buttons["history-Queue"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["history-choice-0"].exists)
    app.buttons["history-Queue"].tap()
    XCTAssertTrue(app.staticTexts["Queue updated"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["So What"].exists)
  }
  @MainActor func testSingleAlbumOpensDirectlyAndBackReturnsToHistory() {
    let app = openHistory()
    app.buttons["history-album-demo-history-0"].tap()
    XCTAssertTrue(app.buttons["history-Play Now"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Freddie Freeloader"].firstMatch.exists)
    XCTAssertFalse(app.buttons["history-choice-0"].exists)
    XCTAssertFalse(app.staticTexts["Queue updated"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "One tap to album playback"; screenshot.lifetime = .keepAlways; add(screenshot)
    app.navigationBars["Kind of Blue"].buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["history-album-demo-history-0"].waitForExistence(timeout: 5))
  }
  @MainActor func testMultipleEditionsStillRequireAChoice() {
    let app = openHistory(state: "ambiguous")
    app.buttons["history-album-demo-history-0"].tap()
    XCTAssertTrue(app.buttons["history-choice-1"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["history-Play Now"].exists)
    app.buttons["history-choice-1"].tap()
    XCTAssertTrue(app.buttons["history-Play Now"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Queue updated"].exists)
  }
  @MainActor func testEmptyAndUnsupportedBridge() {
    var app = openHistory(state: "empty")
    XCTAssertTrue(app.staticTexts["No recent listening yet"].waitForExistence(timeout: 5))
    app.terminate()
    app = openHistory(state: "unsupported")
    XCTAssertTrue(app.staticTexts["Bridge update required"].waitForExistence(timeout: 5))
  }
}
