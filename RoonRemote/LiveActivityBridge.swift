import ActivityKit
import Foundation
import os.log

/// Starts a Now Playing Live Activity so watchOS can show it in the Smart Stack
/// and open the Watch app from a tap. Apple does not let a music remote force
/// the Watch UI to the front; this is the supported path.
@MainActor
final class LiveActivityBridge {
  static let shared = LiveActivityBridge()
  private static let log = Logger(subsystem: "com.djehring.roonremote", category: "live")

  private var lastAlertKey: String?

  func publish() {
    let store = MockStore.shared
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    guard case .main = store.session, store.client.isPaired else {
      Task { await endAll() }
      return
    }
    let zone = store.selectedZone
    guard let track = zone.track, zone.state != .stopped else {
      lastAlertKey = nil
      Task { await endAll() }
      return
    }
    let state = RoonNowPlayingAttributes.ContentState(
      zoneName: zone.name,
      title: track.title,
      artist: track.artist,
      isPlaying: store.isPlaying
    )
    let alertKey = store.isPlaying ? "\(zone.id)|\(track.id)" : nil
    let shouldAlert = store.isPlaying && alertKey != lastAlertKey
    if let alertKey {
      lastAlertKey = alertKey
    }
    Task {
      await upsert(zoneId: zone.id, state: state, alert: shouldAlert)
    }
  }

  private func upsert(
    zoneId: String,
    state: RoonNowPlayingAttributes.ContentState,
    alert: Bool
  ) async {
    let content = ActivityContent(state: state, staleDate: nil)
    if let activity = Activity<RoonNowPlayingAttributes>.activities.first {
      if alert {
        let alertConfig = AlertConfiguration(
          title: LocalizedStringResource(stringLiteral: state.title),
          body: LocalizedStringResource(stringLiteral: "\(state.artist) · \(state.zoneName)"),
          sound: .default
        )
        await activity.update(content, alertConfiguration: alertConfig)
      } else {
        await activity.update(content)
      }
      return
    }
    do {
      let attributes = RoonNowPlayingAttributes(zoneId: zoneId)
      _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
      if alert, let activity = Activity<RoonNowPlayingAttributes>.activities.first {
        let alertConfig = AlertConfiguration(
          title: LocalizedStringResource(stringLiteral: state.title),
          body: LocalizedStringResource(stringLiteral: "\(state.artist) · \(state.zoneName)"),
          sound: .default
        )
        await activity.update(content, alertConfiguration: alertConfig)
      }
    } catch {
      Self.log.error("live activity failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func endAll() async {
    for activity in Activity<RoonNowPlayingAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
