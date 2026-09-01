import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// Maps iPhone hardware volume buttons to the selected Roon zone's volume.
///
/// iOS has no public "volume button pressed" API. The supported approach is to
/// observe `AVAudioSession.outputVolume`, hide the system HUD with an off-screen
/// `MPVolumeView`, and snap system volume back to a midpoint so presses still
/// register at the edges — same pattern the official Roon app relies on.
@MainActor
final class HardwareVolumeBridge {
  static let shared = HardwareVolumeBridge()

  private weak var store: MockStore?
  private var observation: NSKeyValueObservation?
  private var lastSystemVolume: Float = 0.5
  private var ignoringSystemWrites = false
  private var isRunning = false
  private let baseline: Float = 0.5
  /// Off-screen view that suppresses the system volume HUD and owns the slider
  /// we use to reset system volume after each press.
  private let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))

  private init() {}

  /// Host must keep this view in the hierarchy (can be zero-size / hidden).
  var hudSuppressingView: UIView { volumeView }

  func attach(store: MockStore) {
    self.store = store
  }

  func setActive(_ active: Bool) {
    if active {
      start()
    } else {
      stop()
    }
  }

  func start() {
    guard !isRunning else {
      activateSessionIfNeeded()
      return
    }
    isRunning = true
    activateSessionIfNeeded()
    lastSystemVolume = AVAudioSession.sharedInstance().outputVolume
    observation = AVAudioSession.sharedInstance().observe(
      \.outputVolume,
      options: [.new]
    ) { [weak self] _, change in
      guard let newValue = change.newValue else { return }
      Task { @MainActor in
        self?.handleSystemVolumeChange(newValue)
      }
    }
    // Midpoint so volume-up still works near silence and volume-down near max.
    writeSystemVolume(baseline)
  }

  func stop() {
    observation?.invalidate()
    observation = nil
    isRunning = false
  }

  private func handleSystemVolumeChange(_ newValue: Float) {
    guard isRunning, !ignoringSystemWrites else {
      lastSystemVolume = newValue
      return
    }
    guard let store, case .main = store.session else {
      lastSystemVolume = newValue
      return
    }
    // Don't fight the mic session used by AI search recording.
    if AVAudioSession.sharedInstance().category == .playAndRecord {
      lastSystemVolume = newValue
      return
    }

    let delta = newValue - lastSystemVolume
    lastSystemVolume = newValue
    guard abs(delta) > 0.001 else { return }

    guard let output = store.outputs.first(where: { !$0.isFixed }) else {
      writeSystemVolume(baseline)
      return
    }
    let span = max(output.max - output.min, 1)
    let step = max(1, span / 20)
    store.adjustVolume(by: delta > 0 ? step : -step)
    writeSystemVolume(baseline)
  }

  private func activateSessionIfNeeded() {
    let session = AVAudioSession.sharedInstance()
    guard session.category != .playAndRecord else { return }
    // Now Playing owns `.playback` so lock-screen controls stay live.
    guard session.category != .playback else { return }
    do {
      try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
    } catch {
      // Volume bridging is best-effort; leave buttons alone if session fails.
    }
  }

  private func writeSystemVolume(_ value: Float) {
    guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else {
      lastSystemVolume = AVAudioSession.sharedInstance().outputVolume
      return
    }
    ignoringSystemWrites = true
    slider.value = value
    lastSystemVolume = value
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      self?.ignoringSystemWrites = false
      self?.lastSystemVolume = AVAudioSession.sharedInstance().outputVolume
    }
  }
}

/// Keeps the hidden `MPVolumeView` in the SwiftUI hierarchy so iOS suppresses
/// the system volume HUD while this app is foregrounded.
struct HardwareVolumeHUDSuppressor: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let host = UIView(frame: .zero)
    host.isUserInteractionEnabled = false
    host.isAccessibilityElement = false
    let volumeView = HardwareVolumeBridge.shared.hudSuppressingView
    volumeView.isUserInteractionEnabled = false
    volumeView.alpha = 0.01
    volumeView.clipsToBounds = true
    host.addSubview(volumeView)
    return host
  }

  func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Centered Roon-style volume readout shown while hardware/keyboard volume changes.
struct VolumeHUDOverlay: View {
  let hud: VolumeHUD

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: hud.symbolName)
        .font(.system(size: 40, weight: .medium))
        .contentTransition(.symbolEffect(.replace))
      Text("\(hud.displayValue)")
        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
        .contentTransition(.numericText())
    }
    .foregroundStyle(.white)
    .frame(width: 120, height: 120)
    .background {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(.black.opacity(0.72))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Volume \(hud.displayValue)")
  }
}
