import Foundation
import Testing

@Suite("Audio session ownership")
@MainActor
struct AudioSessionControllerTests {
  @Test func nowPlayingTicksReuseTheSessionAndAllAudioWorkLeavesTheMainThread() async {
    let driver = AudioDriverProbe()
    let audio = AudioSessionController(driver: driver)
    audio.setVolumeEnabled(true)
    for _ in 0..<100 { audio.setPlayback(true) }
    await audio.flush()
    #expect(driver.activations == [.ambient, .playback])
    #expect(driver.keepAlivePlaying)
    #expect(!driver.usedMainThread)
  }

  @Test func pauseAndStopKeepTheRightOwner() async {
    let driver = AudioDriverProbe()
    let audio = AudioSessionController(driver: driver)
    audio.setVolumeEnabled(true)
    audio.setPlayback(true)
    audio.setPlayback(false)
    await audio.flush()
    #expect(driver.mode == .playback)
    #expect(!driver.keepAlivePlaying)
    #expect(driver.activations == [.ambient, .playback])
    audio.setPlayback(nil)
    await audio.flush()
    #expect(driver.mode == .ambient)
    audio.setVolumeEnabled(false)
    await audio.flush()
    #expect(driver.mode == nil)
    #expect(!driver.deactivatedWhilePlaying)
  }

  @Test func recordingOwnsTheSessionUntilItFinishesThenUsesTheLatestRoomState() async throws {
    let driver = AudioDriverProbe()
    let audio = AudioSessionController(driver: driver)
    audio.setPlayback(true)
    try await audio.startRecording(to: URL(fileURLWithPath: "/tmp/audio-test.m4a"))
    audio.setVolumeEnabled(true)
    audio.setPlayback(nil)
    await audio.flush()
    #expect(driver.mode == .recording)
    #expect(!driver.keepAlivePlaying)
    #expect(try await audio.stopRecording() == Data([1, 2, 3]))
    #expect(driver.mode == .ambient)
    #expect(!driver.usedMainThread)
    #expect(!driver.deactivatedWhilePlaying)
  }

  @Test func failedRecordingRestoresPlaybackAndReadFailureAlsoReleasesTheMicrophone() async throws {
    let driver = AudioDriverProbe()
    let audio = AudioSessionController(driver: driver)
    audio.setPlayback(true)
    driver.failRecording = true
    await #expect(throws: AudioProbeFailure.self) {
      try await audio.startRecording(to: URL(fileURLWithPath: "/tmp/audio-test.m4a"))
    }
    #expect(driver.mode == .playback)
    #expect(driver.keepAlivePlaying)
    driver.failRecording = false
    try await audio.startRecording(to: URL(fileURLWithPath: "/tmp/audio-test.m4a"))
    driver.failRead = true
    await #expect(throws: AudioProbeFailure.self) { try await audio.stopRecording() }
    #expect(driver.mode == .playback)
    #expect(driver.keepAlivePlaying)
    #expect(!driver.deactivatedWhilePlaying)
  }

  @Test func interruptionSuspendsAutomaticTicksAndResumesOnlyWhenAllowed() async {
    let driver = AudioDriverProbe()
    let audio = AudioSessionController(driver: driver)
    audio.setPlayback(true)
    audio.interruption(began: true, shouldResume: false)
    for _ in 0..<10 { audio.setPlayback(true) }
    await audio.flush()
    #expect(!driver.keepAlivePlaying)
    #expect(driver.activations == [.playback])
    audio.interruption(began: false, shouldResume: true)
    await audio.flush()
    #expect(driver.keepAlivePlaying)
    #expect(driver.activations == [.playback, .playback])
    audio.interruption(began: true, shouldResume: false)
    audio.interruption(began: false, shouldResume: false)
    audio.setPlayback(true)
    await audio.flush()
    #expect(!driver.keepAlivePlaying)
    audio.setPlayback(false)
    audio.setPlayback(true)
    await audio.flush()
    #expect(driver.keepAlivePlaying)
  }

  @Test func mediaServiceResetInvalidatesTheCachedSession() async {
    let driver = AudioDriverProbe()
    let audio = AudioSessionController(driver: driver)
    audio.setPlayback(true)
    audio.mediaServicesReset()
    await audio.flush()
    #expect(driver.activations == [.playback, .playback])
    #expect(driver.keepAlivePlaying)
    #expect(!driver.usedMainThread)
  }
}

private struct AudioProbeFailure: Error { }

/// Tests read only after an awaited queue barrier; mutations use the audio queue.
private final class AudioDriverProbe: RemoteAudioDriver {
  var activations: [RemoteAudioMode] = []
  var mode: RemoteAudioMode?
  var keepAlivePlaying = false
  var recording = false
  var usedMainThread = false
  var deactivatedWhilePlaying = false
  var failRecording = false
  var failRead = false

  func activate(_ mode: RemoteAudioMode) throws {
    usedMainThread = usedMainThread || Thread.isMainThread
    self.mode = mode
    activations.append(mode)
  }
  func deactivate() throws {
    usedMainThread = usedMainThread || Thread.isMainThread
    deactivatedWhilePlaying = deactivatedWhilePlaying || keepAlivePlaying || recording
    mode = nil
  }
  func keepAlive(_ playing: Bool) throws {
    usedMainThread = usedMainThread || Thread.isMainThread
    keepAlivePlaying = playing
  }
  func reset() { mode = nil; recording = false; keepAlivePlaying = false }
  func startRecording(to url: URL) throws {
    usedMainThread = usedMainThread || Thread.isMainThread
    if failRecording { throw AudioProbeFailure() }
    recording = true
  }
  func stopRecording() throws -> Data {
    usedMainThread = usedMainThread || Thread.isMainThread
    recording = false
    if failRead { throw AudioProbeFailure() }
    return Data([1, 2, 3])
  }
}
