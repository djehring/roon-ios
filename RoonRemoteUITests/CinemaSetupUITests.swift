import XCTest

final class CinemaSetupUITests: XCTestCase {
  @MainActor func testAdaptiveModesAndPersonalPhotos() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_CINEMA_SETUP_QUERY"] = "UK top ten this week in 1978"
    app.launch()
    XCTAssertTrue(app.navigationBars["Set up Cinema"].waitForExistence(timeout: 10))
    capture("Chart week")
    reveal(app.switches["Headlines"], in: app)
    XCTAssertTrue(app.switches["Sports highlights"].exists)
    reveal(app.buttons["More topics"], in: app)
    app.buttons["More topics"].tap()
    reveal(app.switches["Artist photographs"], in: app)
    let artistPhotos = app.switches["Artist photographs"]
    artistPhotos.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: artistPhotos)
    XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 2), .completed)
    capture("Mixed topics")
    scrollToTop(app)
    app.buttons["cinema-mode"].tap()
    app.buttons["About the artist"].tap()
    reveal(app.switches["Artist photographs"], in: app)
    XCTAssertTrue(app.switches["Career stories"].exists)
    capture("Artist topics")
    scrollToTop(app)
    app.buttons["cinema-mode"].tap()
    app.buttons["About the work"].tap()
    reveal(app.switches["Manuscripts & scores"], in: app)
    XCTAssertTrue(app.switches["Programme notes"].exists)
    capture("Classical topics")
    scrollToTop(app)
    app.buttons["cinema-mode"].tap()
    app.buttons["My photos"].tap()
    reveal(app.buttons["Choose photos"], in: app)
    XCTAssertTrue(app.buttons["Choose an album"].exists)
    capture("Personal photos")
    reveal(app.buttons["Save montage"], in: app)
    XCTAssertFalse(app.buttons["Save montage"].isEnabled)
    app.buttons["Cancel"].tap()
    XCTAssertFalse(app.navigationBars["Set up Cinema"].exists)
  }

  @MainActor func testBeethovenDefaults() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_CINEMA_SETUP_QUERY"] = "Beethoven Symphony No. 6"
    app.launch()
    XCTAssertTrue(app.navigationBars["Set up Cinema"].waitForExistence(timeout: 10))
    capture("Beethoven setup")
    reveal(app.staticTexts["Work & composer"], in: app)
    XCTAssertTrue(app.staticTexts["Work & composer"].exists)
    reveal(app.staticTexts["Relaxed · 16 seconds"], in: app)
    XCTAssertTrue(app.staticTexts["Relaxed · 16 seconds"].exists)
    capture("Presentation")
  }

  @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
      app.swipeUp()
    }
    XCTAssertTrue(element.exists)
  }
  @MainActor private func scrollToTop(_ app: XCUIApplication) {
    for _ in 0..<5 {
      if app.buttons["cinema-mode"].isHittable { return }
      app.swipeDown()
    }
  }
  @MainActor private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
