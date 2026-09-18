import XCTest
import UIKit

final class CinemaPlaylistUITests: XCTestCase {
  @MainActor func testNewMontageImmediatelyShowsLoadedCoverEvenForUnrelatedMusic() throws {
    let app = launchNewMontage(coverSource: "current")
    XCTAssertTrue(app.staticTexts["Updating pictures…"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["cinema-artwork-image"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.descendants(matching: .any)["cinema-artwork-loading"].exists)
    capture("New montage with immediate album artwork")
  }

  @MainActor func testWatchOnlyNewMontageFetchesPlaylistCoverWithNoCurrentSong() throws {
    let app = launchNewMontage(coverSource: "playlist")
    XCTAssertTrue(app.staticTexts["Music is stopped"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["cinema-artwork-image"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.descendants(matching: .any)["cinema-artwork-loading"].exists)
    XCTAssertFalse(app.buttons["Play music"].isEnabled)
    capture("Watch-only montage with playlist album artwork")
  }

  @MainActor private func launchNewMontage(coverSource: String) -> XCUIApplication {
    let cover = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).pngData { context in
      UIColor.systemIndigo.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
      ("ALBUM\nCOVER" as NSString).draw(at: CGPoint(x: 25, y: 75), withAttributes: [
        .font: UIFont.boldSystemFont(ofSize: 38), .foregroundColor: UIColor.white
      ])
    }
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_CINEMA_PREVIEW_JSON"] = CinemaPlaylistFixture.json
    app.launchEnvironment["ROON_CINEMA_PREVIEW_NEW"] = "1"
    app.launchEnvironment["ROON_CINEMA_PREVIEW_COVER"] = cover.base64EncodedString()
    app.launchEnvironment["ROON_CINEMA_PREVIEW_COVER_SOURCE"] = coverSource
    app.launch()
    return app
  }

  @MainActor func testEditRegenerateWatchAndDelete() throws {
    let app = launch(delay: "12")
    XCTAssertTrue(app.buttons["cinema-edit"].waitForExistence(timeout: 10))
    capture("Cinema library")
    app.buttons["cinema-edit"].tap()
    XCTAssertTrue(app.staticTexts["Edit Cinema"].waitForExistence(timeout: 5))
    let headlines = app.switches["Headlines"]
    reveal(headlines, app: app)
    headlines.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    capture("Cinema edit")
    app.buttons["cinema-save"].tap()
    XCTAssertTrue(app.buttons["cinema-watch"].waitForExistence(timeout: 5))
    app.buttons["cinema-watch"].tap()
    XCTAssertTrue(app.staticTexts["Updating pictures…"].waitForExistence(timeout: 5))
    let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"),
      object: app.buttons["Close Cinema"])
    XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 5), .completed)
    capture("Cinema immediate artwork")
    XCTAssertTrue(app.buttons["Close montage"].waitForExistence(timeout: 25))
    app.buttons["Cinema playlists"].tap()
    XCTAssertTrue(app.buttons["cinema-edit"].waitForExistence(timeout: 5))
    app.buttons["cinema-edit"].tap()
    reveal(app.switches["Headlines"], app: app)
    XCTAssertEqual(app.switches["Headlines"].value as? String, "0")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["cinema-delete"].waitForExistence(timeout: 5))
    app.buttons["cinema-delete"].tap()
    XCTAssertTrue(app.alerts["Delete Cinema item?"].waitForExistence(timeout: 5))
    app.alerts.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["cinema-item-preview-a"].exists)
    app.buttons["cinema-delete"].tap()
    app.alerts.buttons["Delete"].tap()
    XCTAssertTrue(app.buttons["cinema-item-preview-b"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["cinema-item-preview-a"].exists)
    capture("Cinema after deletion")
  }

  @MainActor func testFailedUpdateRetainsSavedPlaylist() throws {
    let app = launch(delay: "0", fail: true)
    XCTAssertTrue(app.buttons["cinema-edit"].waitForExistence(timeout: 10))
    app.buttons["cinema-edit"].tap()
    app.buttons["cinema-save"].tap()
    XCTAssertTrue(app.staticTexts["Preview: picture service unavailable"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["cinema-item-preview-a"].exists)
    XCTAssertTrue(app.buttons["cinema-watch"].isEnabled)
    capture("Cinema update failed")
  }

  @MainActor private func launch(delay: String, fail: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_CINEMA_PREVIEW_JSON"] = CinemaPlaylistFixture.json
    app.launchEnvironment["ROON_CINEMA_PREVIEW_LIBRARY"] = "1"
    app.launchEnvironment["ROON_CINEMA_PREVIEW_DELAY"] = delay
    app.launchEnvironment["ROON_CINEMA_PREVIEW_FAIL"] = fail ? "1" : "0"
    app.launch()
    return app
  }

  @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<6 {
      if element.exists && element.isHittable { return }
      app.swipeUp()
    }
  }
  @MainActor private func capture(_ title: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = title
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
