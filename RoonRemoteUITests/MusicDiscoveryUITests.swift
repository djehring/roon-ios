import XCTest

final class MusicDiscoveryUITests: XCTestCase {
  override func setUp() { super.setUp(); continueAfterFailure = false }

  @MainActor func testAlbumResultsAndCompleteWorkDetails() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_DISCOVERY_PREVIEW"] = "albums"
    app.launch()
    XCTAssertTrue(app.buttons["Play album"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["Play Enigma Variations only"].exists)
    XCTAssertTrue(app.staticTexts["19 tracks"].exists)
    XCTAssertTrue(app.staticTexts["Release date unverified"].exists)
    XCTAssertTrue(app.segmentedControls["discovery-mode"].buttons["Auto"].isSelected)
    XCTAssertFalse(app.buttons["Play selected tracks"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Verified album search on iPhone"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["Details"].tap()
    XCTAssertTrue(app.staticTexts["Tracks in album order"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["1. Companion work 1"].exists)
    XCTAssertTrue(app.staticTexts["5. Enigma: Theme"].exists)
    app.buttons["Done"].tap()
    app.segmentedControls["discovery-mode"].buttons["Tracks"].tap()
    XCTAssertFalse(app.buttons["Play album"].exists)
    XCTAssertTrue(app.staticTexts["Ask for some music"].exists)
  }

  @MainActor func testSearchingShowsQueryAndCanBeCancelled() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_DISCOVERY_PREVIEW"] = "searching"
    app.launch()
    let searching = app.staticTexts["discovery-loading"]
    XCTAssertTrue(searching.waitForExistence(timeout: 15))
    XCTAssertEqual(searching.label, "Searching for “UK top ten from this week in 1985”")
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "AI search in progress"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["discovery-cancel"].tap()
    XCTAssertTrue(app.staticTexts["Ask for some music"].waitForExistence(timeout: 5))
    XCTAssertFalse(searching.exists)
    XCTAssertEqual(app.textFields["discovery-query"].value as? String, "UK top ten from this week in 1985")
    XCTAssertTrue(app.buttons["Go"].isEnabled)
  }
}
