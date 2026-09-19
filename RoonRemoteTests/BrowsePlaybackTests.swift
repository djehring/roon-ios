import Foundation
import Testing

@MainActor
@Suite("Browse playback feedback")
struct BrowsePlaybackTests {
  @Test(arguments: ["Play", "Play Now", "Play Album", "Play Playlist", "Play From Here", "Shuffle", "Shuffle All", "  PLAY NOW  "])
  func immediatePlaybackActions(_ title: String) {
    #expect(BrowsePlayback.startsPlayback(title))
  }

  @Test(arguments: ["Queue", "Add to Queue", "Play Next", "Queue Next", "Add to Playlist", "Search"])
  func deferredActions(_ title: String) {
    #expect(!BrowsePlayback.startsPlayback(title))
  }

  @Test func acknowledgesBeforeOpeningNowPlaying() async {
    let playback = BrowsePlayback()
    var opened = false
    await playback.run(actionTitle: "Play Album", room: "Kitchen", feedbackDuration: .zero) {
      #expect(playback.isRunning)
      #expect(playback.feedback?.title == "Starting playback…")
      #expect(playback.feedback?.room == "Kitchen")
      #expect(playback.feedback?.isLoading == true)
      #expect(!opened)
    } showNowPlaying: {
      #expect(playback.feedback?.title == "Playback started")
      #expect(playback.feedback?.isLoading == false)
      opened = true
    }
    #expect(opened)
    #expect(!playback.isRunning)
    #expect(playback.feedback == nil)
    #expect(playback.error == nil)
  }

  @Test(arguments: ["Queue", "Play Next"])
  func queueDoesNotNavigate(_ action: String) async {
    let playback = BrowsePlayback()
    var performed = false
    await playback.run(actionTitle: action, room: "Kitchen", feedbackDuration: .zero) {
      performed = true
    } showNowPlaying: {
      Issue.record("Queue actions should keep the browse screen open")
    }
    #expect(performed)
  }

  @Test func failureStaysInBrowseAndAllowsRetry() async {
    let playback = BrowsePlayback()
    await playback.run(actionTitle: "Play", room: "Kitchen", feedbackDuration: .zero) {
      throw RoonAPIError.browseAction("Room unavailable")
    } showNowPlaying: {
      Issue.record("Failed playback should not navigate")
    }
    #expect(playback.error == "Room unavailable")
    #expect(playback.feedback == nil)
    #expect(!playback.isRunning)

    var opened = false
    await playback.run(actionTitle: "Play", room: "Kitchen", feedbackDuration: .zero) {
      #expect(playback.error == nil)
    } showNowPlaying: {
      opened = true
    }
    #expect(opened)
  }

  @Test func duplicateTapsDoNotRepeatTheCommand() async {
    let playback = BrowsePlayback()
    var commands = 0
    var navigation = 0
    await playback.run(actionTitle: "Play", room: "Kitchen", feedbackDuration: .zero) {
      commands += 1
      await playback.run(actionTitle: "Play", room: "Kitchen", feedbackDuration: .zero) {
        commands += 1
      } showNowPlaying: {
        navigation += 1
      }
    } showNowPlaying: {
      navigation += 1
    }
    #expect(commands == 1)
    #expect(navigation == 1)
  }

  @Test func cancellationClearsFeedback() async {
    let playback = BrowsePlayback()
    await playback.run(actionTitle: "Play", room: "Kitchen", feedbackDuration: .zero) {
      throw CancellationError()
    } showNowPlaying: {
      Issue.record("Cancelled playback should not navigate")
    }
    #expect(playback.feedback == nil)
    #expect(playback.error == nil)
    #expect(!playback.isRunning)
  }
}
