import XCTest

final class CinemaRemoteUITests: XCTestCase {
  @MainActor func testRemoteCanChooseTrackTitleAndKenBurns() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_CINEMA_PREVIEW_JSON"] = CinemaPlaylistFixture.json
    app.launchEnvironment["ROON_CINEMA_PREVIEW_LIBRARY"] = "1"
    app.launchEnvironment["ROON_CINEMA_PREVIEW_FAIL"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["cinema-item-preview-a"].waitForExistence(timeout: 10))
    let remote = XCUIRemote.shared
    remote.press(.right)
    remote.press(.down)
    XCTAssertTrue(app.buttons["cinema-edit"].hasFocus)
    remote.press(.select)
    XCTAssertTrue(app.staticTexts["Edit Cinema"].waitForExistence(timeout: 5))
    for _ in 0..<5 {
      if app.buttons["cinema-presentation"].hasFocus { break }
      remote.press(.down)
    }
    XCTAssertTrue(app.buttons["cinema-presentation"].hasFocus, app.debugDescription)
    remote.press(.select)
    let title = app.buttons["cinema-show-track-title"]
    let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: title)
    XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed)
    remote.press(.select)
    XCTAssertEqual(title.value as? String, "On")
    remote.press(.down)
    remote.press(.down)
    XCTAssertTrue(app.buttons["cinema-picture-motion"].hasFocus, app.debugDescription)
    remote.press(.select)
    XCTAssertTrue(app.buttons["Ken Burns"].waitForExistence(timeout: 5))
    remote.press(.down)
    remote.press(.down)
    XCTAssertTrue(app.cells["Ken Burns"].hasFocus || app.buttons["Ken Burns"].hasFocus, app.debugDescription)
    remote.press(.select)
    XCTAssertTrue(app.buttons["cinema-picture-motion"].label.contains("Ken Burns"))
    capture("TV Cinema presentation options")
    for _ in 0..<8 {
      if app.buttons["cinema-save"].hasFocus { break }
      remote.press(.down)
    }
    XCTAssertTrue(app.buttons["cinema-save"].hasFocus, app.debugDescription)
    remote.press(.select)
    XCTAssertTrue(app.buttons["cinema-watch"].waitForExistence(timeout: 5))
    remote.press(.up)
    remote.press(.right)
    XCTAssertTrue(app.buttons["cinema-watch"].hasFocus, app.debugDescription)
    remote.press(.select)
    XCTAssertTrue(app.buttons["Close montage"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Close montage"].waitForNonExistence(timeout: 10))
    XCTAssertEqual(app.staticTexts["cinema-track-title"].label, "Dancing Queen")
    XCTAssertEqual(app.staticTexts["cinema-track-artist"].label, "ABBA")
    capture("TV Cinema persistent track title")
  }

  @MainActor func testRemoteCanReachEditAndSave() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_CINEMA_PREVIEW_JSON"] = CinemaPlaylistFixture.json
    app.launchEnvironment["ROON_CINEMA_PREVIEW_LIBRARY"] = "1"
    app.launchEnvironment["ROON_CINEMA_PREVIEW_DELAY"] = "20"
    app.launch()
    XCTAssertTrue(app.buttons["cinema-item-preview-a"].waitForExistence(timeout: 10))
    let remote = XCUIRemote.shared
    remote.press(.right)
    XCTAssertTrue(app.buttons["cinema-play"].hasFocus, app.debugDescription)
    remote.press(.down)
    XCTAssertTrue(app.buttons["cinema-edit"].hasFocus, app.debugDescription)
    remote.press(.select)
    XCTAssertTrue(app.staticTexts["Edit Cinema"].waitForExistence(timeout: 5))
    capture("TV Cinema editor")
    remote.press(.down)
    XCTAssertTrue(app.buttons["cinema-edit-music"].hasFocus, app.debugDescription)
    remote.press(.select)
    XCTAssertTrue(app.buttons["cinema-add-music"].waitForExistence(timeout: 5))
    capture("TV Cinema music editor")
    remote.press(.menu)
    XCTAssertTrue(app.staticTexts["Edit Cinema"].waitForExistence(timeout: 5))
    // Save is always reachable below the option pane, including with long topic lists.
    remote.press(.right)
    for _ in 0..<14 {
      if app.buttons["cinema-save"].hasFocus { break }
      remote.press(.down)
    }
    XCTAssertTrue(app.buttons["cinema-save"].hasFocus, app.debugDescription)
    remote.press(.select)
    XCTAssertTrue(app.buttons["cinema-watch"].waitForExistence(timeout: 5))
    capture("TV Cinema saved")
    remote.press(.up)
    XCTAssertTrue(app.buttons["cinema-play"].hasFocus, app.debugDescription)
    remote.press(.right)
    XCTAssertTrue(app.buttons["cinema-watch"].hasFocus, app.debugDescription)
    remote.press(.select)
    XCTAssertFalse(app.staticTexts["Updating pictures…"].exists)
    capture("TV saved Cinema playback")
    XCTAssertTrue(app.buttons["Close montage"].waitForExistence(timeout: 30))
  }

  @MainActor private func capture(_ title: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = title
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
