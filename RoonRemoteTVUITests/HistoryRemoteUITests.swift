import XCTest

final class HistoryRemoteUITests: XCTestCase {
  override func setUp() { super.setUp(); continueAfterFailure = false }
  @MainActor func testHistoryCanBeBrowsedWithTheRemote() {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launch()
    select("Library", in: app)
    let history = app.buttons["open-history"]
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    focusAndSelect(history, in: app)
    XCTAssertTrue(app.staticTexts["Kind of Blue"].firstMatch.waitForExistence(timeout: 5))
    select("Tracks", in: app)
    XCTAssertTrue(app.staticTexts["Freddie Freeloader"].firstMatch.waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Recently played on Apple TV"; screenshot.lifetime = .keepAlways; add(screenshot)
    focusAndSelect(app.buttons["history-track-demo-history-0"], in: app)
    XCTAssertTrue(app.staticTexts["Choose the recording or edition you want."].waitForExistence(timeout: 5))
    focusAndSelect(app.buttons["history-choice-0"], in: app)
    XCTAssertTrue(app.buttons["history-Queue"].waitForExistence(timeout: 5))
    let detail = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    detail.name = "Recently played actions on Apple TV"; detail.lifetime = .keepAlways; add(detail)
    focusAndSelect(app.buttons["history-Queue"], in: app)
    XCTAssertTrue(app.staticTexts["Queue updated"].waitForExistence(timeout: 5))
  }
  @MainActor private func select(_ title: String, in app: XCUIApplication) {
    focusAndSelect(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch, in: app)
  }
  @MainActor private func focusAndSelect(_ target: XCUIElement, in app: XCUIApplication) {
    XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
    for _ in 0..<20 {
      if target.hasFocus { XCUIRemote.shared.press(.select); return }
      guard let current = app.descendants(matching: .any).allElementsBoundByIndex.first(where: { $0.hasFocus }) else {
        XCUIRemote.shared.press(.down); continue
      }
      if current.elementType == .cell && current.frame.contains(CGPoint(x: target.frame.midX, y: target.frame.midY)) {
        XCUIRemote.shared.press(.select); return
      }
      let dx = target.frame.midX - current.frame.midX
      let dy = target.frame.midY - current.frame.midY
      if abs(dy) > 20 { XCUIRemote.shared.press(dy > 0 ? .down : .up) }
      else { XCUIRemote.shared.press(dx > 0 ? .right : .left) }
    }
    XCTFail("Could not focus \(target): \(app.debugDescription)")
  }
}
