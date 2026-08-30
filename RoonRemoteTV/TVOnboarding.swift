import SwiftUI

struct TVOnboardingFlow: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    Group {
      switch store.session {
      case .onboarding(.localNetwork):
        TVLocalNetworkStep()
      case .onboarding(.findingBridge):
        TVFindingBridgeStep()
      case .onboarding(.pin):
        TVPinStep()
      case .onboarding(.waitingForCore):
        TVWaitingForCoreStep()
      case .onboarding(.chooseZone):
        TVChooseZoneStep()
      case .main:
        EmptyView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.background)
  }
}

private struct TVOnboardingChrome<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 36) {
      Spacer(minLength: 40)
      Image(systemName: "hifispeaker.2.fill")
        .font(.system(size: 64, weight: .light))
        .foregroundStyle(Palette.accent)
      VStack(spacing: 14) {
        Text("Roon")
          .font(.system(size: 42, weight: .bold))
          .foregroundStyle(Palette.accent)
        Text(title)
          .font(.system(size: 38, weight: .semibold))
          .multilineTextAlignment(.center)
        Text(subtitle)
          .font(.system(size: 22))
          .foregroundStyle(Palette.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 780)
      }
      content
        .frame(maxWidth: 720)
      Spacer()
    }
    .padding(48)
  }
}

private struct TVLocalNetworkStep: View {
  @Environment(MockStore.self) private var store
  @FocusState private var continueFocused: Bool

  var body: some View {
    TVOnboardingChrome(
      title: "Connect to your Core",
      subtitle: "Roon uses your local network to find the bridge on Wi-Fi."
    ) {
      TVPrimaryButton(title: "Continue") {
        store.advanceOnboarding()
      }
      .focused($continueFocused)
    }
    .onAppear { continueFocused = true }
  }
}

private struct TVFindingBridgeStep: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    TVOnboardingChrome(
      title: "Looking for your bridge",
      subtitle: "Pick a discovered host, or enter host:port with the remote keyboard."
    ) {
      VStack(spacing: 24) {
        if store.isDiscovering {
          ProgressView()
            .tint(Palette.accent)
            .controlSize(.large)
        }
        if let error = store.discoveryError {
          Text(error)
            .font(.title3)
            .foregroundStyle(.red.opacity(0.85))
            .multilineTextAlignment(.center)
        }
        ForEach(store.discoveredBridges) { bridge in
          Button {
            store.selectBridge(bridge)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(bridge.name)
                  .font(.title2.weight(.semibold))
                Text("\(bridge.host):\(bridge.port)")
                  .font(.body)
                  .foregroundStyle(Palette.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundStyle(Palette.tertiary)
            }
            .padding(24)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          }
          .buttonStyle(.plain)
        }
        TextField("192.168.0.14:3000", text: $store.manualHost)
          .font(.title3)
          .padding(20)
          .background(Palette.surface)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        TVPrimaryButton(title: "Use this address") {
          store.useManualHost()
        }
        Button("Search again") {
          Task { await store.discoverBridges() }
        }
        .buttonStyle(.bordered)
        .tint(Palette.accent)
      }
    }
  }
}

private struct TVPinStep: View {
  @Environment(MockStore.self) private var store
  private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

  var body: some View {
    TVOnboardingChrome(
      title: "Enter the pairing code",
      subtitle: pinSubtitle
    ) {
      VStack(spacing: 28) {
        HStack(spacing: 14) {
          ForEach(0..<6, id: \.self) { index in
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(Palette.surface)
              .frame(width: 56, height: 72)
              .overlay {
                Text(digit(at: index))
                  .font(.system(size: 32, weight: .medium, design: .rounded))
              }
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(
                    store.pinError
                      ? Color.red.opacity(0.7)
                      : Palette.accent.opacity(index == store.pinDigits.count ? 1 : 0.25),
                    lineWidth: 2
                  )
              }
          }
        }
        if let failure = store.pairFailure {
          Text(failure)
            .font(.title3)
            .foregroundStyle(.red.opacity(0.85))
            .multilineTextAlignment(.center)
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
          ForEach(keys, id: \.self) { key in
            Button { tap(key) } label: {
              Text(key)
                .font(.system(size: 28, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(key.isEmpty ? Color.clear : Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(key.isEmpty)
          }
        }
        .frame(maxWidth: 420)
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
    store.pairFailure = nil
    if key == "⌫" {
      if !store.pinDigits.isEmpty { store.pinDigits.removeLast() }
      return
    }
    guard store.pinDigits.count < 6 else { return }
    store.pinDigits.append(key)
    if store.pinDigits.count == 6 {
      store.submitPin()
    }
  }

  private var pinSubtitle: String {
    if let bridge = store.selectedBridge {
      return "PIN from web Settings. Pairing \(bridge.host):\(bridge.port)."
    }
    return "Open web Settings and type the six-digit PIN shown there."
  }
}

private struct TVWaitingForCoreStep: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    TVOnboardingChrome(
      title: "Enable the extension",
      subtitle: "In Roon Settings, enable this extension. The TV waits until the bridge reports SYNC."
    ) {
      VStack(spacing: 16) {
        ProgressView()
          .tint(Palette.accent)
          .controlSize(.large)
        Text(store.syncState.rawValue)
          .font(.title3.weight(.semibold))
          .foregroundStyle(Palette.tertiary)
        if let error = store.discoveryError {
          Text(error)
            .font(.title3)
            .foregroundStyle(.red.opacity(0.85))
            .multilineTextAlignment(.center)
        }
      }
    }
  }
}

private struct TVChooseZoneStep: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text("Choose a room")
        .font(.system(size: 42, weight: .semibold))
      Text("This is the zone the TV will control.")
        .font(.title2)
        .foregroundStyle(Palette.secondary)
      if store.zones.isEmpty {
        ProgressView()
          .tint(Palette.accent)
          .frame(maxWidth: .infinity)
          .padding(.top, 40)
      } else {
        ForEach(store.zones) { zone in
          Button {
            store.selectZone(zone.id)
            store.finishOnboarding()
          } label: {
            HStack(spacing: 20) {
              Image(systemName: "hifispeaker.fill")
                .font(.title)
                .foregroundStyle(Palette.accent)
              VStack(alignment: .leading, spacing: 4) {
                Text(zone.name)
                  .font(.title2.weight(.semibold))
                Text(zone.track?.title ?? "Nothing playing")
                  .font(.body)
                  .foregroundStyle(Palette.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundStyle(Palette.tertiary)
            }
            .padding(28)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      Spacer()
    }
    .padding(64)
    .frame(maxWidth: 900)
  }
}
