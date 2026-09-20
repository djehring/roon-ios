import AVFoundation
import MediaPlayer
import UIKit

/// Publishes lock-screen / Control Center Now Playing for the selected zone.
///
/// A `.playback` session is what makes iOS treat this as a live Now Playing
/// target instead of a snapshot taken at lock. While the zone is playing we
/// also loop a silent buffer so the `audio` background mode keeps this
/// process (and the SSE stream) alive after the phone locks. Without that,
/// iOS suspends us and the Live Activity freezes on the old track.
/// Watch auto-launch still uses the Live Activity, not this buffer.
///
/// tvOS shares this: registering the commands is what routes the Siri Remote's
/// play/pause button, Siri, and the iPhone Apple TV Remote to the Roon zone.
@MainActor
final class NowPlayingBridge {
  static let shared = NowPlayingBridge()

  private weak var store: MockStore?
  private var commandsReady = false
  private var lastSignature: String?
  #if os(iOS)
  private var silencePlayer: AVAudioPlayer?
  private var wantsKeepAlive = false
  private var observingInterruptions = false
  #endif

  private init() {}

  func attach(store: MockStore) {
    self.store = store
    registerCommandsIfNeeded()
    #if os(iOS)
    NowPlayingLiveActions.playPause = { [weak self] in
      guard let store = self?.store else { return }
      store.resumeSync()
      store.togglePlay()
      await Self.flushLiveActivity()
    }
    #endif
  }

  /// Live Activities are an iPhone feature; tvOS has no Watch companion to feed.
  private static func flushLiveActivity() async {
    #if os(iOS)
    await LiveActivityBridge.shared.flush()
    #endif
  }

  func publish() {
    guard let store, case .main = store.session, store.client.isPaired else {
      clear()
      return
    }
    let zone = store.selectedZone
    guard let track = zone.track, zone.state != .stopped else {
      clear()
      return
    }
    apply(track: track, playing: store.isPlaying, store: store)
  }

  /// Stops the keep-alive buffer so AI search can take the mic session.
  func yieldAudioSession() {
    #if os(iOS)
    stopKeepAlive()
    #endif
  }

  private func apply(track: Track, playing: Bool, store: MockStore) {
    activatePlaybackSession()
    #if os(iOS)
    setKeepAlivePlaying(playing)
    #endif
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: track.title,
      MPMediaItemPropertyArtist: track.artist,
      MPMediaItemPropertyAlbumTitle: track.album,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
    ]
    if let elapsed = TimeCode.seconds(from: track.position) {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    }
    if let duration = track.durationSeconds, duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let image = artworkImage(for: track, store: store) {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    let signature = "\(track.id)|\(playing)|\(track.position)|\(track.imageKey ?? "")|\(info[MPMediaItemPropertyArtwork] != nil)"
    let center = MPNowPlayingInfoCenter.default()
    if signature != lastSignature {
      center.nowPlayingInfo = info
      lastSignature = signature
    }
    center.playbackState = playing ? .playing : .paused
    MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = track.isSeekable
  }

  private func artworkImage(for track: Track, store: MockStore) -> UIImage? {
    guard let key = track.imageKey else { return nil }
    let sizes = [ArtworkCache.heroPixels, ArtworkCache.gridPixels, ArtworkCache.thumbnailPixels]
    for pixels in sizes {
      if let data = store.artwork.data(for: ArtworkCache.Key(imageKey: key, pixels: pixels)),
         let image = UIImage(data: data)
      {
        return image
      }
    }
    return nil
  }

  private func activatePlaybackSession() {
    let session = AVAudioSession.sharedInstance()
    guard session.category != .playAndRecord else { return }
    do {
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
    } catch {
      // Lock-screen Now Playing is best-effort if the session is in use.
    }
  }

  #if os(iOS)
  private func setKeepAlivePlaying(_ playing: Bool) {
    wantsKeepAlive = playing
    if playing {
      startKeepAliveIfNeeded()
    } else {
      stopKeepAlive()
    }
  }

  private func startKeepAliveIfNeeded() {
    observeInterruptionsIfNeeded()
    if AVAudioSession.sharedInstance().category == .playAndRecord { return }
    if let player = silencePlayer, player.isPlaying { return }
    activatePlaybackSession()
    do {
      let player = try AVAudioPlayer(data: Self.silenceWAV)
      player.numberOfLoops = -1
      player.volume = 1
      player.prepareToPlay()
      guard player.play() else { return }
      silencePlayer = player
    } catch {
      // Keep-alive is best-effort; lock-screen updates resume on the next tick.
    }
  }

  private func stopKeepAlive() {
    wantsKeepAlive = false
    silencePlayer?.stop()
    silencePlayer = nil
  }

  private func observeInterruptionsIfNeeded() {
    guard !observingInterruptions else { return }
    observingInterruptions = true
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        self?.handleInterruption(notification)
      }
    }
  }

  private func handleInterruption(_ notification: Notification) {
    guard wantsKeepAlive else { return }
    let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
    guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
    startKeepAliveIfNeeded()
  }

  /// Digital silence at full volume. A muted player does not hold the
  /// `audio` background assertion, so the samples themselves are zeros.
  private static let silenceWAV: Data = {
    let sampleRate = 8_000
    let frames = sampleRate * 2
    let dataSize = frames * 2
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
    ascii("RIFF")
    u32(UInt32(36 + dataSize))
    ascii("WAVE")
    ascii("fmt ")
    u32(16)
    u16(1)
    u16(1)
    u32(UInt32(sampleRate))
    u32(UInt32(sampleRate * 2))
    u16(2)
    u16(16)
    ascii("data")
    u32(UInt32(dataSize))
    data.append(Data(count: dataSize))
    return data
  }()
  #endif

  private func clear() {
    #if os(iOS)
    stopKeepAlive()
    #endif
    guard lastSignature != nil || MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else {
      return
    }
    lastSignature = nil
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = nil
    center.playbackState = .stopped
  }

  private func runRemote(_ work: (MockStore) -> Void) {
    guard let store else { return }
    store.resumeSync()
    work(store)
  }

  private func registerCommandsIfNeeded() {
    guard !commandsReady else { return }
    commandsReady = true
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.togglePlayPauseCommand.isEnabled = true
    center.nextTrackCommand.isEnabled = true
    center.previousTrackCommand.isEnabled = true
    center.stopCommand.isEnabled = true
    center.changePlaybackPositionCommand.isEnabled = false

    center.playCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { store in
          guard !store.isPlaying else { return }
          store.togglePlay()
        }
        await Self.flushLiveActivity()
      }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { store in
          guard store.isPlaying else { return }
          store.togglePlay()
        }
        await Self.flushLiveActivity()
      }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { $0.togglePlay() }
        await Self.flushLiveActivity()
      }
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { $0.skip() }
        await Self.flushLiveActivity()
      }
      return .success
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { $0.previous() }
        await Self.flushLiveActivity()
      }
      return .success
    }
    center.stopCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { $0.stop() }
        await Self.flushLiveActivity()
      }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      Task { @MainActor in
        self?.runRemote { store in
          guard let duration = store.currentTrack?.durationSeconds, duration > 0 else { return }
          store.seek(toProgress: event.positionTime / duration)
        }
      }
      return .success
    }
  }
}
