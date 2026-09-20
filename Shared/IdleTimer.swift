#if os(iOS) || os(tvOS)
import SwiftUI
import UIKit

/// Keeps the display awake for as long as the view is on screen.
///
/// A montage or a drifting cover is something to look at, so the system screen
/// saver appearing over it — after as little as two minutes on Apple TV — is a
/// bug rather than a rest. The previous setting is put back on the way out, so
/// nesting this inside another view that wants it does not clear it early.
struct ScreenStaysAwake: ViewModifier {
  @State private var previous = false

  func body(content: Content) -> some View {
    content.onAppear {
      previous = UIApplication.shared.isIdleTimerDisabled
      UIApplication.shared.isIdleTimerDisabled = true
    }.onDisappear { UIApplication.shared.isIdleTimerDisabled = previous }
  }
}

extension View {
  func screenStaysAwake() -> some View { modifier(ScreenStaysAwake()) }
}
#endif
