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
}
