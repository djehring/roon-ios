import XCTest

final class CoverScreensaverRemoteUITests: XCTestCase {
  @MainActor func testIdleNowPlayingFillsTheScreenAndBackReturns() {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launch()
    XCTAssertTrue(app.descendants(matching: .any)["now-playing-screen"].firstMatch.waitForExistence(timeout: 10))

    let screensaver = app.descendants(matching: .any)["cover-screensaver"].firstMatch
    XCTAssertTrue(
      screensaver.waitForExistence(timeout: 20),
      "an untouched remote on Now Playing should hand the screen to the cover: \(app.debugDescription)"
    )
    // Let the cover finish being presented before measuring or photographing it.
    Thread.sleep(forTimeInterval: 2)
    // Zoomed square art overhangs a 16:9 screen on every side, which is what
    // gives the drift somewhere to go. Nothing of the screen is left uncovered.
    XCTAssertGreaterThanOrEqual(screensaver.frame.width, app.frame.width, "the cover should fill the screen")
    XCTAssertGreaterThanOrEqual(screensaver.frame.height, app.frame.height, "the cover should fill the screen")
    capture("TV idle cover screensaver")

    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(app.descendants(matching: .any)["now-playing-screen"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(screensaver.exists, app.debugDescription)
    capture("TV Now Playing after back")
  }

  @MainActor func testTouchingTheRemoteKeepsTheControls() {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launch()
    XCTAssertTrue(app.descendants(matching: .any)["now-playing-screen"].firstMatch.waitForExistence(timeout: 10))

    // Stepping between the transport buttons for longer than the idle wait must
    // never take the controls away mid-press.
    for _ in 0..<7 {
      XCUIRemote.shared.press(.right)
      Thread.sleep(forTimeInterval: 2)
    }
    XCTAssertFalse(app.descendants(matching: .any)["cover-screensaver"].firstMatch.exists, app.debugDescription)
  }

  @MainActor private func capture(_ title: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = title
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
