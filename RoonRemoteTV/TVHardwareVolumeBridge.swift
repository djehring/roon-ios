import AVFoundation
import GameController
import SwiftUI
import UIKit

/// Maps Siri Remote / Apple TV volume input to the selected Roon zone.
///
/// tvOS does not give apps a volume-button press type. When the system changes
/// `AVAudioSession.outputVolume` (HomePod, Bluetooth, or Volume Control aimed
/// at Apple TV) we treat that as a step. HID volume keys and any game-controller
/// button named volume are handled the same way. CEC/IR volume aimed at the TV
/// never reaches the process.
@MainActor
final class TVHardwareVolumeBridge {
  static let shared = TVHardwareVolumeBridge()

  private weak var store: MockStore?
  private var observation: NSKeyValueObservation?
  private var lastSystemVolume: Float = 0.5
  private var isRunning = false
  private var pressRecognizer: VolumePressRecognizer?
  private var controllerObservers: [NSObjectProtocol] = []
  private var repeatTask: Task<Void, Never>?
  private var ignoreSystemUntil: Date?

  private init() {}

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
    if isRunning {
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
    listenForControllers()
    bindControllers()
  }

  func stop() {
    observation?.invalidate()
    observation = nil
    controllerObservers.forEach(NotificationCenter.default.removeObserver)
    controllerObservers.removeAll()
    repeatTask?.cancel()
    repeatTask = nil
    isRunning = false
  }

  func install(in window: UIWindow?) {
    guard let window else { return }
    if let pressRecognizer, window.gestureRecognizers?.contains(pressRecognizer) == true {
      return
    }
    if let pressRecognizer {
      pressRecognizer.view?.removeGestureRecognizer(pressRecognizer)
    }
    let recognizer = VolumePressRecognizer()
    recognizer.onStep = { [weak self] up in
      self?.nudge(up: up, repeating: true)
    }
    recognizer.onEnd = { [weak self] in
      self?.repeatTask?.cancel()
      self?.repeatTask = nil
    }
    window.addGestureRecognizer(recognizer)
    pressRecognizer = recognizer
  }

  private func handleSystemVolumeChange(_ newValue: Float) {
    guard isRunning else {
      lastSystemVolume = newValue
      return
    }
    guard let store, case .main = store.session else {
      lastSystemVolume = newValue
      return
    }

    if let until = ignoreSystemUntil, Date() < until {
      lastSystemVolume = newValue
      return
    }
    let delta = newValue - lastSystemVolume
    lastSystemVolume = newValue
    guard abs(delta) > 0.001 else { return }
    applyStep(up: delta > 0)
  }

  private func nudge(up: Bool, repeating: Bool) {
    ignoreSystemUntil = Date().addingTimeInterval(0.35)
    applyStep(up: up)
    guard repeating else { return }
    repeatTask?.cancel()
    repeatTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 400_000_000)
      while !Task.isCancelled {
        self?.applyStep(up: up)
        try? await Task.sleep(nanoseconds: 120_000_000)
      }
    }
  }

  private func applyStep(up: Bool) {
    guard let store, case .main = store.session else { return }
    guard let output = store.outputs.first(where: { !$0.isFixed }) else { return }
    let span = max(output.max - output.min, 1)
    let step = max(1, span / 20)
    store.adjustVolume(by: up ? step : -step)
  }

  private func activateSessionIfNeeded() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
    } catch {
      // Volume bridging is best-effort; leave buttons alone if session fails.
    }
  }

  private func listenForControllers() {
    guard controllerObservers.isEmpty else { return }
    let center = NotificationCenter.default
    controllerObservers.append(
      center.addObserver(
        forName: .GCControllerDidConnect,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.bindControllers() }
      }
    )
    controllerObservers.append(
      center.addObserver(
        forName: .GCControllerDidDisconnect,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.bindControllers() }
      }
    )
  }

  private func bindControllers() {
    for controller in GCController.controllers() {
      for (name, button) in controller.physicalInputProfile.buttons {
        let lowered = String(describing: name).lowercased()
        guard lowered.contains("volume") else { continue }
        let up = lowered.contains("up") || lowered.contains("+")
        let down = lowered.contains("down") || lowered.contains("-")
        guard up || down else { continue }
        button.valueChangedHandler = { [weak self] _, _, pressed in
          Task { @MainActor in
            guard pressed else {
              self?.repeatTask?.cancel()
              self?.repeatTask = nil
              return
            }
            self?.nudge(up: up, repeating: true)
          }
        }
      }
    }
  }
}

/// Window-level press recognizer so volume HID keys are seen even when a
/// focused control is first responder.
final class VolumePressRecognizer: UIGestureRecognizer {
  var onStep: ((Bool) -> Void)?
  var onEnd: (() -> Void)?

  override init(target: Any?, action: Selector?) {
    super.init(target: target, action: action)
    cancelsTouchesInView = false
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
    if emit(presses, began: true) {
      state = .began
    } else {
      state = .failed
    }
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
    if emit(presses, began: false) {
      state = .ended
    } else if state == .began || state == .changed {
      state = .ended
    } else {
      state = .failed
    }
  }

  override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
    onEnd?()
    state = .cancelled
  }

  private func emit(_ presses: Set<UIPress>, began: Bool) -> Bool {
    var handled = false
    for press in presses {
      guard let code = press.key?.keyCode else { continue }
      let up: Bool
      switch code {
      case .keyboardVolumeUp: up = true
      case .keyboardVolumeDown: up = false
      default: continue
      }
      if began {
        onStep?(up)
      } else {
        onEnd?()
      }
      handled = true
    }
    return handled
  }
}

/// Installs the window press recognizer from SwiftUI.
struct TVHardwareVolumeInstaller: UIViewRepresentable {
  func makeUIView(context: Context) -> TVHardwareVolumeHostView {
    TVHardwareVolumeHostView()
  }

  func updateUIView(_ uiView: TVHardwareVolumeHostView, context: Context) {}
}

final class TVHardwareVolumeHostView: UIView {
  override func didMoveToWindow() {
    super.didMoveToWindow()
    TVHardwareVolumeBridge.shared.install(in: window)
  }
}

struct TVVolumeHUDOverlay: View {
  let hud: VolumeHUD

  var body: some View {
    VStack(spacing: 22) {
      Image(systemName: hud.symbolName)
        .font(.system(size: 64, weight: .medium))
        .contentTransition(.symbolEffect(.replace))
      Text("\(hud.displayValue)")
        .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
        .contentTransition(.numericText())
    }
    .foregroundStyle(.white)
    .frame(width: 220, height: 220)
    .background {
      RoundedRectangle(cornerRadius: 36, style: .continuous)
        .fill(.black.opacity(0.72))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Volume \(hud.displayValue)")
  }
}
