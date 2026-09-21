import Photos
import UIKit
import XCTest

final class CinemaPhotoAlbumUITests: XCTestCase {
  private let albumTitle = "Cinema Test · Coast & Cliffs"
  private let largeAlbumTitle = "Cinema Test · 201 Photos"
  private let folderTitle = "Cinema Test · Trips"

  @MainActor func testAlbumSelectionAndSave() throws {
    continueAfterFailure = false
    try seedAlbums()
    let app = launchSetup()
    app.buttons["Choose an album"].tap()
    allowPhotosAccess()
    XCTAssertTrue(app.buttons.containing(.staticText, identifier: albumTitle).firstMatch.waitForExistence(timeout: 10))
    capture("Albums before selection")
    app.buttons.containing(.staticText, identifier: albumTitle).firstMatch.tap()
    XCTAssertTrue(app.buttons["cinema-use-album"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["cinema-use-album"].label, "Use 3 photos")
    XCTAssertTrue(app.descendants(matching: .any)["cinema-photo-thumbnail-loaded"].firstMatch.waitForExistence(timeout: 10))
    capture("Album photo preview")
    app.buttons["cinema-use-album"].tap()
    XCTAssertTrue(app.navigationBars["Set up Cinema"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts[albumTitle].exists)
    let save = app.buttons["Save montage"]
    reveal(save, in: app)
    XCTAssertTrue(save.isEnabled)
    capture("Selected album")
    save.tap()
    XCTAssertTrue(app.buttons["cinema-watch"].waitForExistence(timeout: 30))
    capture("Saved album montage")
    app.buttons["cinema-watch"].tap()
    XCTAssertTrue(app.buttons["Close montage"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Photograph 1 of 3"].exists)
    app.buttons["Next photograph"].tap()
    XCTAssertTrue(app.staticTexts["Photograph 2 of 3"].waitForExistence(timeout: 3))
    capture("Album montage playback")

    // The saved copies must be readable after a fresh process starts.
    app.terminate()
    app.launchEnvironment.removeValue(forKey: "ROON_CINEMA_SETUP_QUERY")
    app.launch()
    XCTAssertTrue(app.buttons["Cinema"].waitForExistence(timeout: 10))
    app.buttons["Cinema"].tap()
    XCTAssertTrue(app.staticTexts[albumTitle].firstMatch.waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["cinema-watch"].waitForExistence(timeout: 5))
    app.buttons["cinema-watch"].tap()
    XCTAssertTrue(app.buttons["Close montage"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["This montage needs pictures"].exists)
    capture("Saved album after relaunch")
  }

  @MainActor func testFolderSearchAndCancelPreserveSelection() throws {
    continueAfterFailure = false
    try seedAlbums()
    let app = launchSetup()
    app.buttons["Choose an album"].tap()
    allowPhotosAccess()
    let album = app.buttons.containing(.staticText, identifier: albumTitle).firstMatch
    XCTAssertTrue(album.waitForExistence(timeout: 10))
    album.tap()
    app.buttons["cinema-album-photo-0"].tap()
    XCTAssertEqual(app.buttons["cinema-use-album"].label, "Use 2 photos")
    app.buttons["cinema-use-album"].tap()
    app.buttons["Choose an album"].tap()
    XCTAssertTrue(album.waitForExistence(timeout: 10))
    album.tap()
    XCTAssertEqual(app.buttons["cinema-album-photo-0"].value as? String, "Not selected")
    app.buttons["Deselect all"].tap()
    XCTAssertFalse(app.buttons["cinema-use-album"].isEnabled)
    app.navigationBars["Preview album"].buttons.element(boundBy: 0).tap()
    app.navigationBars["Choose an album"].buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Set up Cinema"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["cinema-photo-selection"].label, "\(albumTitle), 2 photos")

    app.buttons["Choose an album"].tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    search.tap()
    search.typeText(folderTitle)
    let family = app.buttons.containing(.staticText, identifier: "Family").firstMatch
    XCTAssertTrue(family.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts[folderTitle].exists)
    capture("Album folder search")
    family.tap()
    XCTAssertEqual(app.buttons["cinema-use-album"].label, "Use 2 photos")
    app.buttons["cinema-use-album"].tap()
    XCTAssertTrue(app.staticTexts["Family"].exists)
  }

  @MainActor func testLargeAlbumAllowsSubsetAndSavesOnlyChosenPhotos() throws {
    continueAfterFailure = false
    try seedAlbums()
    let app = launchSetup()
    app.buttons["Choose an album"].tap()
    allowPhotosAccess()
    let album = app.buttons.containing(.staticText, identifier: largeAlbumTitle).firstMatch
    XCTAssertTrue(album.waitForExistence(timeout: 10))
    XCTAssertTrue(album.isEnabled)
    album.tap()
    XCTAssertTrue(app.staticTexts["201 photos · 0 selected"].exists)
    XCTAssertFalse(app.buttons["cinema-use-album"].isEnabled)
    app.buttons["cinema-album-photo-1"].tap()
    app.buttons["cinema-album-photo-2"].tap()
    XCTAssertEqual(app.buttons["cinema-use-album"].label, "Use 2 photos")
    capture("Select from a large album")
    app.buttons["cinema-use-album"].tap()
    XCTAssertEqual(app.staticTexts["cinema-photo-selection"].label, "\(largeAlbumTitle), 2 photos")
    reveal(app.buttons["Save montage"], in: app)
    app.buttons["Save montage"].tap()
    XCTAssertTrue(app.buttons["cinema-watch"].waitForExistence(timeout: 30))
    app.buttons["cinema-watch"].tap()
    XCTAssertTrue(app.staticTexts["Photograph 1 of 2"].waitForExistence(timeout: 10))
    capture("Large album subset playback")
  }

  @MainActor func testDeniedAccessCanReturnToSetupAndChooseIndividualPhotos() throws {
    continueAfterFailure = false
    try seedAlbums()
    let app = launchSetup()
    app.buttons["Choose an album"].tap()
    let deny = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Don’t Allow", "Don't Allow")).firstMatch
    XCTAssertTrue(deny.waitForExistence(timeout: 5))
    deny.tap()
    XCTAssertTrue(app.staticTexts["Photos access is off. Use Choose photos to select pictures without library access."].waitForExistence(timeout: 5))
    capture("Photos access denied")
    app.navigationBars["Choose an album"].buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Set up Cinema"].waitForExistence(timeout: 5))
    app.buttons["Choose photos"].tap()
    let pickerCancel = app.buttons.matching(NSPredicate(format: "identifier == %@", "Cancel")).firstMatch
    XCTAssertTrue(pickerCancel.waitForExistence(timeout: 10))
    capture("Individual Photos picker without library access")
    pickerCancel.tap()
    XCTAssertTrue(app.navigationBars["Set up Cinema"].waitForExistence(timeout: 5))
  }

  @MainActor private func launchSetup() -> XCUIApplication {
    let app = XCUIApplication()
    app.terminate()
    app.resetAuthorizationStatus(for: .photos)
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_CINEMA_SETUP_QUERY"] = "Holiday soundtrack"
    app.launch()
    XCTAssertTrue(app.navigationBars["Set up Cinema"].waitForExistence(timeout: 10))
    app.buttons["cinema-mode"].tap()
    app.buttons["My photos"].tap()
    return app
  }

  @MainActor private func seedAlbums() throws {
    if PHPhotoLibrary.authorizationStatus(for: .readWrite) != .authorized {
      let authorized = expectation(description: "Photos authorization")
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in authorized.fulfill() }
      allowPhotosAccess()
      wait(for: [authorized], timeout: 10)
    }
    XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .readWrite), .authorized)
    let images = (0..<3).map { index in
      UIGraphicsImageRenderer(size: CGSize(width: 360, height: 240)).image { context in
        [UIColor.systemTeal, .systemOrange, .systemIndigo][index].setFill()
        context.fill(CGRect(x: 0, y: 0, width: 360, height: 240))
        ("Coast & Cliffs\nPhoto \(index + 1)" as NSString).draw(at: CGPoint(x: 25, y: 80), withAttributes: [
          .font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.white
        ])
      }
    }
    if findAlbum(albumTitle) == nil {
      try PHPhotoLibrary.shared().performChangesAndWait {
        let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumTitle)
        let assets = images.enumerated().map { index, image in
          let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
          request.creationDate = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86400)
          request.isFavorite = index == 0
          return request.placeholderForCreatedAsset!
        }
        album.addAssets(assets as NSArray)
      }
    }
    if findAlbum(largeAlbumTitle) == nil {
      try PHPhotoLibrary.shared().performChangesAndWait {
        let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.largeAlbumTitle)
        let assets = (0..<201).map { PHAssetChangeRequest.creationRequestForAsset(from: images[$0 % 3]).placeholderForCreatedAsset! }
        album.addAssets(assets as NSArray)
      }
    }
    if findAlbum("Family") == nil {
      let source = PHAsset.fetchAssets(in: try XCTUnwrap(findAlbum(albumTitle)), options: nil)
      try PHPhotoLibrary.shared().performChangesAndWait {
        let folder = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: self.folderTitle)
        let nested = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Family")
        nested.addAssets(source.objects(at: IndexSet(integersIn: 0..<2)) as NSArray)
        folder.addChildCollections([nested.placeholderForCreatedAssetCollection] as NSArray)
      }
    }
  }

  private func findAlbum(_ title: String) -> PHAssetCollection? {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "title == %@", title)
    return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
  }

  @MainActor private func allowPhotosAccess() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let allow = springboard.buttons["Allow Full Access"]
    if allow.waitForExistence(timeout: 5) { allow.tap() }
  }

  @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
      let form = app.collectionViews.firstMatch
      form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05,
        thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
        withVelocity: .slow, thenHoldForDuration: 0.1)
    }
  }

  @MainActor private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
