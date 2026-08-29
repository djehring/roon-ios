import SwiftUI

struct OnboardingFlow: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    Group {
      switch store.session {
      case .onboarding(.localNetwork):
        LocalNetworkStep()
      case .onboarding(.findingBridge):
        FindingBridgeStep()
      case .onboarding(.pin):
        PinStep()
      case .onboarding(.waitingForCore):
        WaitingForCoreStep()
      case .onboarding(.chooseZone):
        ChooseZoneStep()
      case .main:
        EmptyView()
      }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.background)
  }
}

private struct OnboardingChrome<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 28) {
      Spacer(minLength: 24)
      Image(systemName: "hifispeaker.2.fill")
        .font(.system(size: 44, weight: .light))
        .foregroundStyle(Palette.accent)
      VStack(spacing: 10) {
        Text(title)
          .font(.system(size: 28, weight: .semibold))
          .multilineTextAlignment(.center)
        Text(subtitle)
          .font(.system(size: 16))
          .foregroundStyle(Palette.secondary)
          .multilineTextAlignment(.center)
      }
      content
      Spacer()
    }
  }
}

struct LocalNetworkStep: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    OnboardingChrome(
      title: "Find your house",
      subtitle: "Roon Remote uses the local network to reach the bridge on your Wi-Fi."
    ) {
      Button("Continue") { store.advanceOnboarding() }
        .buttonStyle(GoldFillButton())
    }
  }
}

struct FindingBridgeStep: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    OnboardingChrome(
      title: "Looking for your Roon bridge",
      subtitle: "This is a prototype, so discovery always succeeds."
    ) {
      ProgressView()
        .tint(Palette.accent)
        .controlSize(.large)
    }
    .onAppear {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
        store.advanceOnboarding()
      }
    }
  }
}

struct PinStep: View {
  @Environment(MockStore.self) private var store
  private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

  var body: some View {
    @Bindable var store = store
    OnboardingChrome(
      title: "Enter the pairing code",
      subtitle: "From web Settings, or Roon Settings > Extensions. Prototype: any code except 000000."
    ) {
      VStack(spacing: 22) {
        HStack(spacing: 10) {
          ForEach(0..<6, id: \.self) { index in
            Capsule()
              .fill(Palette.surface)
              .frame(width: 36, height: 48)
              .overlay {
                Text(digit(at: index))
                  .font(.system(size: 22, weight: .medium, design: .rounded))
                  .foregroundStyle(Palette.primary)
              }
              .overlay {
                Capsule()
                  .stroke(
                    store.pinError ? Color.red.opacity(0.7) : Palette.accent.opacity(
                      index == store.pinDigits.count ? 1 : 0.25
                    ),
                    lineWidth: 1
                  )
              }
          }
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3),
                  spacing: 12) {
          ForEach(keys, id: \.self) { key in
            Button {
              tap(key)
            } label: {
              Text(key)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Palette.primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(key.isEmpty ? Color.clear : Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(key.isEmpty)
          }
        }
      }
    }
  }

  private func digit(at index: Int) -> String {
    let chars = Array(store.pinDigits)
    guard index < chars.count else { return "" }
    return String(chars[index])
  }

  private func tap(_ key: String) {
    store.pinError = false
    if key == "⌫" {
      if !store.pinDigits.isEmpty {
        store.pinDigits.removeLast()
      }
      return
    }
    guard store.pinDigits.count < 6 else { return }
    store.pinDigits.append(key)
    if store.pinDigits.count == 6 {
      store.submitPin()
    }
  }
}

struct WaitingForCoreStep: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    OnboardingChrome(
      title: "Enable the extension",
      subtitle: "In Roon Settings, enable this extension, then wait. This screen retries until Core is paired."
    ) {
      ProgressView()
        .tint(Palette.accent)
        .controlSize(.large)
        .onAppear {
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            store.advanceOnboarding()
          }
        }
    }
  }
}

struct ChooseZoneStep: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Choose a room")
        .font(.system(size: 28, weight: .semibold))
      Text("This is the zone the phone and Watch will control.")
        .foregroundStyle(Palette.secondary)
      VStack(spacing: 0) {
        ForEach(store.zones) { zone in
          Button {
            store.selectZone(zone.id)
            store.session = .main
          } label: {
            HStack {
              Image(systemName: "hifispeaker.fill")
                .foregroundStyle(Palette.accent)
              VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                  .foregroundStyle(Palette.primary)
                Text(zone.track?.title ?? "Nothing playing")
                  .font(.footnote)
                  .foregroundStyle(Palette.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundStyle(Palette.tertiary)
            }
            .padding(.vertical, 14)
          }
          if zone.id != store.zones.last?.id {
            Divider().background(Palette.hairline)
          }
        }
      }
      Spacer()
    }
  }
}

struct GoldFillButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(Palette.onAccent)
      .frame(maxWidth: .infinity, minHeight: 50)
      .background(Palette.accent.opacity(configuration.isPressed ? 0.75 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
