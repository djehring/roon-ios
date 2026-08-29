import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum Palette {
  static let background = Color.adaptive(light: 0xF3F3F5, dark: 0x0C0C0E)
  static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x161618)
  static let accent = Color(hex: 0xC4A46A)
  static let onAccent = Color(hex: 0x0C0C0E)
  static let primary = Color.adaptive(light: 0x1C1C1E, dark: 0xFFFFFF)
  static let secondary = Color.adaptiveFill(lightBlack: 0.52, darkWhite: 0.60)
  static let tertiary = Color.adaptiveFill(lightBlack: 0.36, darkWhite: 0.36)
  static let hairline = Color.adaptiveFill(lightBlack: 0.10, darkWhite: 0.08)
}

extension Color {
  init(hex: UInt32, alpha: Double = 1) {
    let r = Double((hex >> 16) & 0xFF) / 255
    let g = Double((hex >> 8) & 0xFF) / 255
    let b = Double(hex & 0xFF) / 255
    self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
  }

  static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
      UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
    })
  }

  static func adaptiveFill(lightBlack: CGFloat, darkWhite: CGFloat) -> Color {
    Color(uiColor: UIColor { traits in
      if traits.userInterfaceStyle == .dark {
        return UIColor(white: 1, alpha: darkWhite)
      }
      return UIColor(white: 0, alpha: lightBlack)
    })
  }
}

private extension UIColor {
  convenience init(hex: UInt32, alpha: CGFloat = 1) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: alpha
    )
  }
}

enum Motion {
  static let sheet = Animation.easeInOut(duration: 0.25)
}

struct CoverArt: View {
  let title: String
  var corner: CGFloat = 12
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let colors = Self.colors(for: title, scheme: colorScheme)
    RoundedRectangle(cornerRadius: corner, style: .continuous)
      .fill(
        LinearGradient(
          colors: colors,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay {
        Image(systemName: "music.note")
          .font(.system(size: 28, weight: .light))
          .foregroundStyle(
            colorScheme == .dark
              ? Color.white.opacity(0.35)
              : Color.black.opacity(0.28)
          )
      }
      .overlay {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .stroke(Palette.hairline, lineWidth: 1)
      }
  }

  static func colors(for title: String, scheme: ColorScheme) -> [Color] {
    let hash = abs(title.hashValue)
    let hue = Double(hash % 360) / 360
    if scheme == .light {
      return [
        Color(hue: hue, saturation: 0.22, brightness: 0.86),
        Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1),
              saturation: 0.28, brightness: 0.74),
      ]
    }
    return [
      Color(hue: hue, saturation: 0.35, brightness: 0.28),
      Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1),
            saturation: 0.45, brightness: 0.18),
    ]
  }
}
