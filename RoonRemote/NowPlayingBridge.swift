import AVFoundation
import MediaPlayer
import UIKit

/// Publishes lock-screen / Control Center Now Playing for the selected zone.
///
/// A `.playback` session is what makes iOS treat this as a live Now Playing
/// target instead of a snapshot taken at lock. We do not play silent audio;
/// Watch auto-launch still uses the Live Activity.
@MainActor
final class NowPlayingBridge {
  static let shared = NowPlayingBridge()

  private weak var store: MockStore?
  private var commandsReady = false
  private var lastSignature: String?

  private init() {}

  func attach(store: MockStore) {
    self.store = store
    registerCommandsIfNeeded()
    NowPlayingLiveActions.playPause = { [weak self] in
      guard let store = self?.store else { return }
      store.resumeSync()
      store.togglePlay()
      await LiveActivityBridge.shared.flush()
    }
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

  private func apply(track: Track, playing: Bool, store: MockStore) {
    activatePlaybackSession()
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

  private func clear() {
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
        await LiveActivityBridge.shared.flush()
      }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { store in
          guard store.isPlaying else { return }
          store.togglePlay()
        }
        await LiveActivityBridge.shared.flush()
      }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { $0.togglePlay() }
        await LiveActivityBridge.shared.flush()
      }
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { $0.skip() }
        await LiveActivityBridge.shared.flush()
      }
      return .success
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { $0.previous() }
        await LiveActivityBridge.shared.flush()
      }
      return .success
    }
    center.stopCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.runRemote { $0.stop() }
        await LiveActivityBridge.shared.flush()
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
