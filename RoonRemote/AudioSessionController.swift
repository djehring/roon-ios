import AVFoundation
import Foundation

enum RemoteAudioMode: Equatable {
  case ambient, playback, recording
}

/// Accessed only on AudioSessionController's serial queue.
protocol RemoteAudioDriver: AnyObject {
  func activate(_ mode: RemoteAudioMode) throws
  func deactivate() throws
  func keepAlive(_ playing: Bool) throws
  func reset()
  #if os(iOS)
  func startRecording(to url: URL) throws
  func stopRecording() throws -> Data
  #endif
}

/// Session changes and player/recorder work can block. Keep them off the UI thread
/// and serialize all three owners: Now Playing, hardware volume and voice search.
/// Mutable state and the driver are confined to `queue`; callers only enqueue work.
final class AudioSessionController: @unchecked Sendable {
  static let shared = AudioSessionController(driver: SystemRemoteAudioDriver(), observeSystem: true)
  private let queue = DispatchQueue(label: "com.djehring.roonremote.audio-session", qos: .userInitiated)
  private let driver: RemoteAudioDriver
  private var activeMode: RemoteAudioMode?
  private var playback: Bool?
  private var volumeEnabled = false
  private var recording = false
  private var interrupted = false
  private var observers: [NSObjectProtocol] = []

  init(driver: RemoteAudioDriver, observeSystem: Bool = false) {
    self.driver = driver
    if observeSystem {
      let center = NotificationCenter.default
      observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
        object: nil, queue: nil) { [weak self] notification in
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
        self?.interruption(began: type == .began,
          shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
      })
      observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
        object: nil, queue: nil) { [weak self] _ in self?.mediaServicesReset() })
    }
  }

  deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  /// nil means no Now Playing item; false keeps transport controls active while paused.
  func setPlayback(_ playing: Bool?) {
    queue.async {
      if self.playback != playing && playing == true { self.interrupted = false }
      self.playback = playing
      try? self.refresh()
    }
  }

  func setVolumeEnabled(_ enabled: Bool) {
    queue.async {
      self.volumeEnabled = enabled
      try? self.refresh()
    }
  }

  func interruption(began: Bool, shouldResume: Bool) {
    queue.async {
      self.interrupted = began || !shouldResume
      self.activeMode = nil
      try? self.driver.keepAlive(false)
      if !self.interrupted { try? self.refresh() }
    }
  }

  func mediaServicesReset() {
    queue.async {
      self.driver.reset()
      self.activeMode = nil
      self.recording = false
      self.interrupted = false
      try? self.refresh()
    }
  }

  #if os(iOS)
  func startRecording(to url: URL) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          try self.activate(.recording)
          try self.driver.startRecording(to: url)
          self.recording = true
          continuation.resume()
        } catch {
          self.recording = false
          try? self.refresh()
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func stopRecording() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        let result = Result { try self.driver.stopRecording() }
        self.recording = false
        // Restore the latest room state even if reading the recording failed.
        try? self.refresh()
        continuation.resume(with: result)
      }
    }
  }
  #endif

  /// Wait for queued transitions, without ever blocking their caller's thread.
  func flush() async {
    await withCheckedContinuation { continuation in
      queue.async { continuation.resume() }
    }
  }

  private func refresh() throws {
    guard !recording, !interrupted else { return }
    let desired: RemoteAudioMode? = playback != nil ? .playback : volumeEnabled ? .ambient : nil
    guard let desired else {
      try driver.keepAlive(false)
      if activeMode != nil {
        defer { activeMode = nil }
        try driver.deactivate()
      }
      return
    }
    try activate(desired)
    try driver.keepAlive(desired == .playback && playback == true)
  }

  private func activate(_ mode: RemoteAudioMode) throws {
    guard activeMode != mode else { return }
    try driver.keepAlive(false)
    if activeMode != nil {
      activeMode = nil
      try driver.deactivate()
    }
    try driver.activate(mode)
    activeMode = mode
  }
}

private final class SystemRemoteAudioDriver: RemoteAudioDriver {
  #if os(iOS)
  private var silencePlayer: AVAudioPlayer?
  private var recorder: AVAudioRecorder?
  #endif

  func activate(_ mode: RemoteAudioMode) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let session = AVAudioSession.sharedInstance()
    let category: AVAudioSession.Category = mode == .recording ? .playAndRecord : mode == .playback ? .playback : .ambient
    #if os(iOS)
    let options: AVAudioSession.CategoryOptions = mode == .recording ? [.defaultToSpeaker] : [.mixWithOthers]
    #else
    let options: AVAudioSession.CategoryOptions = [.mixWithOthers]
    #endif
    if session.category != category || session.mode != .default || session.categoryOptions != options {
      try session.setCategory(category, mode: .default, options: options)
    }
    // The blocking API supports our iOS/tvOS 18 deployment target. Only this
    // background queue calls it, and only when the desired session changes.
    try session.setActive(true)
  }

  func deactivate() throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func keepAlive(_ playing: Bool) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    #if os(iOS)
    guard playing else {
      silencePlayer?.stop()
      silencePlayer = nil
      return
    }
    if silencePlayer?.isPlaying == true { return }
    let player = try AVAudioPlayer(data: Self.silenceWAV)
    player.numberOfLoops = -1
    player.volume = 1
    player.prepareToPlay()
    if player.play() { silencePlayer = player }
    #endif
  }

  func reset() {
    try? keepAlive(false)
    #if os(iOS)
    recorder?.stop()
    recorder = nil
    #endif
  }

  #if os(iOS)
  func startRecording(to url: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let next = try AVAudioRecorder(url: url, settings: [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44100,
      AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ])
    guard next.record() else {
      throw NSError(domain: "HouseRemoteAudio", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Could not start microphone recording. Please try again."])
    }
    recorder = next
  }

  func stopRecording() throws -> Data {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let current = recorder else { throw CocoaError(.fileNoSuchFile) }
    current.stop()
    recorder = nil
    defer { try? FileManager.default.removeItem(at: current.url) }
    return try Data(contentsOf: current.url)
  }

  /// Digital silence at full volume; muting the player loses background audio time.
  private static let silenceWAV: Data = {
    let sampleRate = 8_000
    let dataSize = sampleRate * 2 * 2
    var data = Data()
    data.reserveCapacity(44 + dataSize)
    func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
    func u16(_ value: UInt16) {
      var little = value.littleEndian
      data.append(Data(bytes: &little, count: 2))
    }
    func u32(_ value: UInt32) {
      var little = value.littleEndian
      data.append(Data(bytes: &little, count: 4))
    }
    ascii("RIFF"); u32(UInt32(36 + dataSize)); ascii("WAVE"); ascii("fmt ")
    u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2))
    u16(2); u16(16); ascii("data"); u32(UInt32(dataSize))
    data.append(Data(count: dataSize))
    return data
  }()
  #endif
}
