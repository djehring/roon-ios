import Foundation
import HealthKit
import os.log

/// Keeps Now Playing on-wrist while a zone is playing, the same way a trainer
/// app stays up during a workout. The session is discarded so nothing is written
/// to Health.
@MainActor
final class WatchPlaybackSession: NSObject, HKWorkoutSessionDelegate {
  static let shared = WatchPlaybackSession()
  private static let log = Logger(
    subsystem: "com.djehring.roonremote.watchkitapp",
    category: "workout"
  )

  private let healthStore = HKHealthStore()
  private var session: HKWorkoutSession?
  private var startTask: Task<Void, Never>?

  func startIfNeeded() {
    guard session == nil, startTask == nil else { return }
    startTask = Task { await start() }
  }

  func stopIfNeeded() {
    startTask?.cancel()
    startTask = nil
    guard let session else { return }
    let builder = session.associatedWorkoutBuilder()
    if session.state == .running || session.state == .prepared {
      session.end()
    }
    builder.discardWorkout()
    self.session = nil
  }

  private func start() async {
    defer { startTask = nil }
    guard !Task.isCancelled else { return }
    guard HKHealthStore.isHealthDataAvailable() else { return }
    do {
      try await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
      guard !Task.isCancelled else { return }
      let config = HKWorkoutConfiguration()
      config.activityType = .other
      config.locationType = .indoor
      let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
      session.delegate = self
      self.session = session
      session.startActivity(with: .now)
      Self.log.info("playback session started")
    } catch {
      Self.log.error("playback session failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession,
    didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState,
    date: Date
  ) {
    guard toState == .ended || toState == .stopped else { return }
    Task { @MainActor in
      if self.session === workoutSession {
        self.session = nil
      }
    }
  }

  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession,
    didFailWithError error: Error
  ) {
    Task { @MainActor in
      Self.log.error("playback session error: \(error.localizedDescription, privacy: .public)")
      if self.session === workoutSession {
        self.session = nil
      }
    }
  }
}

extension WatchAppDelegate {
  func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
    Task { @MainActor in
      WatchPlaybackSession.shared.startIfNeeded()
    }
    WatchSessionRelay.shared.activate()
    WatchSessionRelay.shared.pull()
  }
}
