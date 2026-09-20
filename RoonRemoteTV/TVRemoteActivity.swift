import SwiftUI
import UIKit

/// When the Siri Remote was last touched.
///
/// tvOS has no "user is idle" callback, and SwiftUI cannot report it either: a
/// focus move is handled by the focus engine, so no view in Now Playing hears
/// the press that caused it. A gesture recognizer on the window sees every press
/// and every touch-surface swipe wherever focus happens to be, which is what the
/// cover screensaver needs to know.
///
/// The reading is deliberately not observable. Nothing should redraw because the
/// viewer pressed a button; the screensaver asks for the idle time on its own
/// clock instead.
@MainActor
final class TVRemoteActivity {
  static let shared = TVRemoteActivity()

  private var lastActivity = Date()
  private var recognizer: RemoteActivityRecognizer?

  private init() {}

  var idleSeconds: TimeInterval { Date().timeIntervalSince(lastActivity) }

  func note() { lastActivity = Date() }

  func install(in window: UIWindow?) {
    guard let window else { return }
    if let recognizer, recognizer.view === window { return }
    if let recognizer {
      recognizer.view?.removeGestureRecognizer(recognizer)
    }
    let created = RemoteActivityRecognizer()
    created.onActivity = { [weak self] in self?.note() }
    window.addGestureRecognizer(created)
    recognizer = created
  }
}

/// Watches the remote without ever taking anything from it: the state is left at
/// `.possible` for the whole sequence, so UIKit keeps handing presses and touches
/// to the focused control and to the focus engine.
final class RemoteActivityRecognizer: UIGestureRecognizer {
  var onActivity: (() -> Void)?
  /// A swipe arrives as a stream of touches. Reporting each one would be a Date
  /// write per frame for no gain, since any single report resets the idle clock.
  private var lastReport = Date.distantPast

  override init(target: Any?, action: Selector?) {
    super.init(target: target, action: action)
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
    allowedPressTypes = [
      UIPress.PressType.select,
      .menu,
      .playPause,
      .upArrow,
      .downArrow,
      .leftArrow,
      .rightArrow,
    ].map { NSNumber(value: $0.rawValue) }
    allowedTouchTypes = [UITouch.TouchType.indirect, .direct].map { NSNumber(value: $0.rawValue) }
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
    report()
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
    report()
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    report()
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    report()
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    report()
  }

  private func report() {
    let now = Date()
    guard now.timeIntervalSince(lastReport) > 0.25 else { return }
    lastReport = now
    onActivity?()
  }
}

/// Attaches the window recognizer from SwiftUI, the same way the hardware volume
/// bridge does.
struct TVRemoteActivityInstaller: UIViewRepresentable {
  func makeUIView(context: Context) -> TVRemoteActivityHostView {
    TVRemoteActivityHostView()
  }

  func updateUIView(_ uiView: TVRemoteActivityHostView, context: Context) {}
}

final class TVRemoteActivityHostView: UIView {
  override func didMoveToWindow() {
    super.didMoveToWindow()
    TVRemoteActivity.shared.install(in: window)
  }
}
