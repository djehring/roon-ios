import SwiftUI

/// Primary CTA that keeps tvOS focus + select working (custom ButtonStyle does not).
struct TVPrimaryButton: View {
  let title: String
  var minHeight: CGFloat = 60
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 22, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
    .buttonStyle(.borderedProminent)
    .tint(Palette.accent)
    .foregroundStyle(Palette.onAccent)
  }
}
