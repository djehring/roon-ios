import XCTest

final class CinemaRemoteUITests: XCTestCase {
  @MainActor func testRemoteCanReachEditAndRegenerate() throws {
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
    // Save is always reachable below the option pane, including with long topic lists.
    remote.press(.right)
    for _ in 0..<14 {
      if app.buttons["cinema-save"].hasFocus { break }
      remote.press(.down)
    }
    XCTAssertTrue(app.buttons["cinema-save"].hasFocus, app.debugDescription)
    remote.press(.select)
    XCTAssertTrue(app.buttons["cinema-watch"].waitForExistence(timeout: 5))
    capture("TV Cinema updating")
    remote.press(.right)
    XCTAssertTrue(app.buttons["cinema-play"].hasFocus, app.debugDescription)
    remote.press(.right)
    XCTAssertTrue(app.buttons["cinema-watch"].hasFocus, app.debugDescription)
    remote.press(.select)
    XCTAssertTrue(app.staticTexts["Updating pictures…"].waitForExistence(timeout: 5))
    capture("TV Cinema preparation")
    XCTAssertTrue(app.buttons["Close montage"].waitForExistence(timeout: 30))
  }

  @MainActor private func capture(_ title: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = title
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
