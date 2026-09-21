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
  private struct Publication: Equatable {
    var snapshot: NowPlayingSnapshot
    var artwork: Data?
  }

  private var lastPublication: Publication?
  private var wantsPublish = false
  private var worker: Task<Void, Never>?

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
    await shared.flush()
    #if os(iOS)
    await LiveActivityBridge.shared.flush()
    #endif
  }

  func publish() {
    wantsPublish = true
    if worker == nil {
      worker = Task { await self.drain() }
    }
  }

  private func flush() async {
    publish()
    await worker?.value
  }

  private func drain() async {
    while wantsPublish {
      wantsPublish = false
      let snapshot = currentSnapshot()
      AudioSessionController.shared.setPlayback(snapshot?.isPlaying)
      // Session activation runs off the main thread. Publishing before it
      // finishes can leave the system holding the previous session's card.
      await AudioSessionController.shared.flush()
      guard !wantsPublish else { continue }
      if let snapshot, let store {
        apply(snapshot: snapshot, store: store)
      } else {
        clear()
      }
    }
    worker = nil
  }

  private func currentSnapshot() -> NowPlayingSnapshot? {
    guard let store, case .main = store.session, store.client.isPaired else {
      return nil
    }
    return NowPlayingSnapshot(zone: store.selectedZone, isPlaying: store.isPlaying)
  }

  private func apply(snapshot: NowPlayingSnapshot, store: MockStore) {
    let track = snapshot.track
    let art = artworkData(for: track, store: store)
    let publication = Publication(snapshot: snapshot, artwork: art)
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: snapshot.title,
      MPMediaItemPropertyArtist: snapshot.artist,
      MPMediaItemPropertyAlbumTitle: track?.album ?? "",
      MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyIsLiveStream: track?.durationSeconds == nil,
    ]
    if let position = track?.position, let elapsed = TimeCode.seconds(from: position) {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    }
    if let duration = track?.durationSeconds, duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let art, let image = UIImage(data: art) {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    let center = MPNowPlayingInfoCenter.default()
    if publication != lastPublication || center.nowPlayingInfo == nil {
      center.nowPlayingInfo = info
      lastPublication = publication
    }
    center.playbackState = snapshot.isPlaying ? .playing : .paused
    MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = track?.isSeekable == true
  }

  private func artworkData(for track: Track?, store: MockStore) -> Data? {
    guard let key = track?.imageKey else { return nil }
    let sizes = [ArtworkCache.heroPixels, ArtworkCache.gridPixels, ArtworkCache.thumbnailPixels]
    for pixels in sizes {
      if let data = store.artwork.data(for: ArtworkCache.Key(imageKey: key, pixels: pixels)) {
        return data
      }
    }
    return nil
  }

  private func clear() {
    guard lastPublication != nil || MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else {
      return
    }
    lastPublication = nil
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
