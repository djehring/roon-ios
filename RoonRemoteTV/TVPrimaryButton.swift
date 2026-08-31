import SwiftUI

/// Primary CTA with in-bounds focus fill. `.borderedProminent` paints a
/// Liquid Glass plate that overdraws the control next to it.
struct TVPrimaryButton: View {
  let title: String
  var minHeight: CGFloat = 60
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      TVPrimaryButtonLabel(title: title, minHeight: minHeight)
    }
    .tvUnplated()
  }
}

private struct TVPrimaryButtonLabel: View {
  let title: String
  var minHeight: CGFloat
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    Text(title)
      .font(.system(size: 22, weight: .semibold))
      .frame(maxWidth: .infinity, minHeight: minHeight)
      .foregroundStyle(isFocused ? Palette.onAccent : Palette.onAccent)
      .background(isFocused ? Color.white : Palette.accent)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

/// `.plain` and `.borderless` paint a Liquid Glass plate larger than the
/// control, which slides under the next key. This style is only the label.
struct TVChromeButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

extension View {
  /// Drops the system focus/hover plates that overdraw neighboring controls.
  func tvUnplated() -> some View {
    self
      .buttonStyle(TVChromeButtonStyle())
      .focusEffectDisabled()
      .hoverEffectDisabled()
  }
}

/// Circular icon used on Now Playing and volume rows.
struct TVIconButton: View {
  let symbol: String
  var size: CGFloat = 64
  var fontSize: CGFloat = 22
  var filled: Bool = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      TVIconButtonLabel(
        symbol: symbol,
        size: size,
        fontSize: fontSize,
        filled: filled
      )
    }
    .tvUnplated()
    .frame(width: size, height: size)
  }
}

private struct TVIconButtonLabel: View {
  let symbol: String
  var size: CGFloat
  var fontSize: CGFloat
  var filled: Bool
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: fontSize, weight: .medium))
      .frame(width: size, height: size)
      .foregroundStyle(iconColor)
      .background(background)
      .clipShape(Circle())
  }

  private var iconColor: Color {
    if isFocused { return Palette.onAccent }
    return filled ? Palette.onAccent : Palette.primary
  }

  private var background: Color {
    if isFocused { return .white }
    return filled ? Palette.accent : Palette.surface.opacity(0.85)
  }
}
