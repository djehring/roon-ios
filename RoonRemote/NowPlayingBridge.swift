import MediaPlayer
import UIKit

/// Publishes lock-screen / Control Center Now Playing for the selected zone.
/// Watch auto-launch uses the Live Activity, not a fake local audio session.
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
    if let key = track.imageKey,
       let data = store.artwork.data(
         for: ArtworkCache.Key(imageKey: key, pixels: ArtworkCache.thumbnailPixels)
       ),
       let image = UIImage(data: data)
    {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    let signature = "\(track.id)|\(playing)|\(track.position)|\(track.imageKey ?? "")"
    let center = MPNowPlayingInfoCenter.default()
    if signature != lastSignature {
      center.nowPlayingInfo = info
      lastSignature = signature
    }
    center.playbackState = playing ? .playing : .paused
    MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = track.isSeekable
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
        guard let store = self?.store, !store.isPlaying else { return }
        store.togglePlay()
      }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        guard let store = self?.store, store.isPlaying else { return }
        store.togglePlay()
      }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.store?.togglePlay() }
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.store?.skip() }
      return .success
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.store?.previous() }
      return .success
    }
    center.stopCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.store?.stop() }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      Task { @MainActor in
        guard let store = self?.store,
              let duration = store.currentTrack?.durationSeconds,
              duration > 0
        else { return }
        store.seek(toProgress: event.positionTime / duration)
      }
      return .success
    }
  }
}
