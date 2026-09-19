import XCTest

final class BrowsePlaybackRemoteUITests: XCTestCase {
  @MainActor func testPlaylistTrackOpensNowPlaying() {
    let app = launch()
    select("A Love Supreme", in: app)
    select("Freddie Freeloader", in: app)
    XCTAssertTrue(app.descendants(matching: .any)["browse-playback-feedback"].firstMatch.waitForExistence(timeout: 3))
    capture("TV playback feedback")
    XCTAssertTrue(app.descendants(matching: .any)["now-playing-screen"].firstMatch.waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["Freddie Freeloader"].exists)
    capture("TV Now Playing after browse")
  }

  @MainActor func testFailureKeepsBrowseOpen() {
    let app = launch(fail: true)
    select("A Love Supreme", in: app)
    select("Freddie Freeloader", in: app)
    XCTAssertTrue(app.alerts["Unable to complete playback action"].waitForExistence(timeout: 5))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(app.staticTexts["Freddie Freeloader"].exists)
    XCTAssertFalse(app.descendants(matching: .any)["now-playing-screen"].firstMatch.exists)
  }

  @MainActor private func launch(fail: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_BROWSE_PREVIEW_HIERARCHY"] = "playlists"
    app.launchEnvironment["ROON_BROWSE_PREVIEW_FAIL"] = fail ? "1" : "0"
    app.launch()
    return app
  }

  @MainActor private func select(_ title: String, in app: XCUIApplication) {
    let target = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
    for _ in 0..<16 {
      if target.hasFocus {
        XCUIRemote.shared.press(.select)
        return
      }
      let focused = app.buttons.allElementsBoundByIndex.first { $0.hasFocus }
      guard let focused else {
        XCUIRemote.shared.press(.down)
        continue
      }
      let dx = target.frame.midX - focused.frame.midX
      let dy = target.frame.midY - focused.frame.midY
      if abs(dy) > 100 {
        XCUIRemote.shared.press(dy > 0 ? .down : .up)
      } else {
        XCUIRemote.shared.press(dx > 0 ? .right : .left)
      }
    }
    XCTFail("Could not focus \(title): \(app.debugDescription)")
  }

  @MainActor private func capture(_ title: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = title
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
