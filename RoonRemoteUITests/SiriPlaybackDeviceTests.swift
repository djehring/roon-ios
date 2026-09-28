import XCTest
import AppIntents
import AppIntentsTesting
import MediaIntents

/// Opt-in device diagnostics. UI automation completion alone is not evidence of
/// playback: check the requested room and the app's playback.confirmed trace.
final class SiriPlaybackDeviceTests: XCTestCase {
  /// Verify the structured query used by Siri AI. This only searches the bridge;
  /// it does not invoke playback or replace any room's current queue.
  @available(iOS 27.0, *)
  @MainActor func testNativeAudioSearchHandoff() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["ROON_NATIVE_SEARCH_TEST"] == "1",
      "Set TEST_RUNNER_ROON_NATIVE_SEARCH_TEST=1 to test the structured AI search handoff.")
    XCUIApplication().launch()
    let definitions = IntentDefinitions(bundleIdentifier: "com.djehring.roonremote")
    let query = "British jazz from the 1960s"
    let input = AudioSearch(criteria: .searchQuery(query))
    let results = try await definitions.valueQueries["SiriMusicAudioQuery"].values(for: input)
    XCTAssertEqual(results.items.count, 1)
    guard results.items.count == 1 else { return }
    let collection = try results.items[0].as(AnyAppEntity.self)
    let title: String = try collection.title
    XCTAssertEqual(title, query)
    let repeated = try await definitions.valueQueries["SiriMusicAudioQuery"].values(for: input)
    XCTAssertEqual(repeated.items.count, 1)
    guard repeated.items.count == 1 else { return }
    let sameCollection = try repeated.items[0].as(AnyAppEntity.self)
    XCTAssertEqual(sameCollection.identifier, collection.identifier)
  }

  @MainActor func testSiriAIConversationDiagnostic() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["ROON_SIRI_INSPECT"] == "1")
    XCUIApplication().launch()
    // Installing a development build triggers asynchronous Siri tool indexing.
    // Use a delay only when investigating that registration boundary on-device.
    if let delay = ProcessInfo.processInfo.environment["ROON_SIRI_INDEX_WAIT"].flatMap(Double.init) {
      Thread.sleep(forTimeInterval: min(max(delay, 0), 60))
    }
    let siriAI = XCUIApplication(bundleIdentifier: "com.apple.campo")
    siriAI.activate()
    if let request = ProcessInfo.processInfo.environment["ROON_SIRI_AI_REQUEST"] {
      if ProcessInfo.processInfo.environment["ROON_SIRI_AI_NEW"] == "1",
        siriAI.buttons["closeButton"].isHittable { siriAI.buttons["closeButton"].tap() }
      if siriAI.buttons["newChatButton"].isHittable { siriAI.buttons["newChatButton"].tap() }
      let prompt = siriAI.textFields["promptViewTextField"]
      prompt.tap()
      prompt.typeText(request)
      siriAI.buttons["sendButton"].tap()
      Thread.sleep(forTimeInterval: 25)
      siriAI.activate()
      let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      screenshot.name = "Siri AI response (diagnostic only)"
      screenshot.lifetime = .keepAlways
      add(screenshot)
    }
    print("SIRI_WINDOW_BEGIN")
    for text in siriAI.staticTexts.allElementsBoundByIndex where text.isHittable { print(text.label) }
    for button in siriAI.buttons.allElementsBoundByIndex where button.isHittable { print("BUTTON: \(button.identifier) \(button.label)") }
    print("SIRI_WINDOW_END")
  }

  /// Exercise the schema intent across the system/app boundary independently
  /// of Siri's language routing. This intentionally plays in the named room.
  @available(iOS 27.0, *)
  @MainActor func testNativeAudioIntentPlayback() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["ROON_NATIVE_AUDIO_TEST"] == "1",
      "Set TEST_RUNNER_ROON_NATIVE_AUDIO_TEST=1 to test native audio intent playback.")
    XCUIDevice.shared.press(.home)
    XCUIApplication().launch()
    let definitions = IntentDefinitions(bundleIdentifier: "com.djehring.roonremote")
    let request = ProcessInfo.processInfo.environment["ROON_SIRI_REQUEST"]
      ?? "British jazz from the 1960s in Office"
    let results = try await definitions.entities["SiriMusicCollection"].entities(matching: request)
    let music = try XCTUnwrap(results.first)
    XCTAssertEqual(results.count, 1)
    try await definitions.intents["PlayAIMusicIntent"].makeIntent(audioEntity: music).run()
  }

  @MainActor func testLiveSiriPlayback() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["ROON_SIRI_LIVE_TEST"] == "1",
      "Set TEST_RUNNER_ROON_SIRI_LIVE_TEST=1 to exercise real Siri and room playback.")
    XCUIDevice.shared.press(.home)
    let app = XCUIApplication()
    app.launch()
    let siri = XCUIDevice.shared.siriService
    let request = ProcessInfo.processInfo.environment["ROON_SIRI_REQUEST"]
      ?? "Play British jazz from the 1960s in Office with House Remote"
    siri.activate(voiceRecognitionText: request)
  }

  @MainActor override func tearDownWithError() throws {
    guard ProcessInfo.processInfo.environment["ROON_SIRI_LIVE_TEST"] == "1" else { return }
    // Capture even when XCTest times out waiting for Siri to activate. On the
    // iOS 27 beta, Siri can complete the action despite that automation timeout.
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Siri response"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    XCUIDevice.shared.press(.home)
  }
}
