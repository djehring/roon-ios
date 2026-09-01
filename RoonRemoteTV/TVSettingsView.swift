import SwiftUI

struct TVSettingsView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    ScrollView {
      VStack(alignment: .leading, spacing: 36) {
        Text("Settings")
          .font(.system(size: 44, weight: .bold))

        settingsSection("Bridge") {
          infoRow("Name", store.selectedBridge?.name ?? "roon-web-stack")
          infoRow("Version", store.bridgeVersion.isEmpty ? "—" : store.bridgeVersion)
          infoRow("PIN", store.pairingPinDisplay.isEmpty ? "—" : store.pairingPinDisplay)
          Button {
            store.rotatePin()
          } label: {
            TVSettingsRowLabel(title: "Rotate PIN")
          }
          .tvUnplated()
          Button {
            store.replayOnboarding()
          } label: {
            TVSettingsRowLabel(title: "Unpair…", destructive: true)
          }
          .tvUnplated()
        }

        settingsSection("OpenAI") {
          SecureField("API key", text: $store.openAIApiKey)
            .onChange(of: store.openAIApiKey) { _, _ in
              store.saveOpenAIApiKey()
            }
        }

        settingsSection("Zone") {
          ForEach(store.zones) { zone in
            Button {
              store.selectZone(zone.id)
            } label: {
              TVSettingsRowLabel(
                title: zone.name,
                checked: zone.id == store.selectedZoneId
              )
            }
            .tvUnplated()
          }
        }

        settingsSection("About") {
          infoRow("App", "0.1.0")
          infoRow("Platform", "Apple TV")
        }
      }
      .padding(48)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .background(Palette.background)
    .onAppear { store.refreshPairingPin() }
  }

  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 36) {
      Text(title)
        .font(.title2.weight(.semibold))
        .foregroundStyle(Palette.secondary)
      content()
    }
  }

  private func infoRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value)
        .foregroundStyle(Palette.secondary)
    }
    .font(.title3)
    .padding(.horizontal, 28)
    .padding(.vertical, 22)
    .background(Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

private struct TVSettingsRowLabel: View {
  let title: String
  var checked: Bool = false
  var destructive: Bool = false
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    HStack {
      Text(title)
        .foregroundStyle(titleColor)
      Spacer()
      if checked {
        Image(systemName: "checkmark")
          .foregroundStyle(isFocused ? Palette.onAccent : Palette.accent)
      }
    }
    .font(.title3)
    .padding(.horizontal, 28)
    .padding(.vertical, 22)
    .background(isFocused ? Color.white : Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var titleColor: Color {
    if isFocused { return Palette.onAccent }
    return destructive ? .red.opacity(0.85) : Palette.primary
  }
}
