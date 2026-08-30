import SwiftUI

struct TVSettingsView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    NavigationStack {
      List {
        Section("Bridge") {
          LabeledContent("Name", value: store.selectedBridge?.name ?? "roon-web-stack")
          LabeledContent(
            "Version",
            value: store.bridgeVersion.isEmpty ? "—" : store.bridgeVersion
          )
          LabeledContent(
            "PIN",
            value: store.pairingPinDisplay.isEmpty ? "—" : store.pairingPinDisplay
          )
          Button("Rotate PIN") { store.rotatePin() }
          Button("Unpair…", role: .destructive) { store.replayOnboarding() }
        }
        Section("Zone") {
          ForEach(store.zones) { zone in
            Button {
              store.selectZone(zone.id)
            } label: {
              HStack {
                Text(zone.name)
                Spacer()
                if zone.id == store.selectedZoneId {
                  Image(systemName: "checkmark")
                    .foregroundStyle(Palette.accent)
                }
              }
            }
          }
        }
        Section("About") {
          LabeledContent("App", value: "0.1.0")
          LabeledContent("Platform", value: "Apple TV")
        }
      }
      .navigationTitle("Settings")
      .onAppear { store.refreshPairingPin() }
    }
  }
}
