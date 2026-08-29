import SwiftUI

struct SettingsView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      List {
        Section("Bridge") {
          LabeledContent("Name", value: store.selectedBridge?.name ?? "roon-web-stack")
          LabeledContent("Version", value: store.bridgeVersion.isEmpty ? "—" : store.bridgeVersion)
          Button("Unpair…") { store.replayOnboarding() }
          LabeledContent("PIN", value: store.pairingPinDisplay.isEmpty ? "—" : store.pairingPinDisplay)
          Button("Rotate PIN") { store.rotatePin() }
        }
        Section("Zone") {
          Picker("Displayed zone", selection: $store.selectedZoneId) {
            ForEach(store.zones) { zone in
              Text(zone.name).tag(zone.id)
            }
          }
          .onChange(of: store.selectedZoneId) { _, id in
            store.selectZone(id)
          }
        }
        Section("Appearance") {
          Picker("Appearance", selection: $store.appearance) {
            ForEach(Appearance.allCases, id: \.self) { item in
              Text(item.label).tag(item)
            }
          }
          .pickerStyle(.inline)
          .onChange(of: store.appearance) { _, _ in
            store.saveAppearance()
          }
        }
        Section("Now Playing toolbar") {
          ForEach(store.toolbar) { action in
            Label(action.label, systemImage: action.symbol)
          }
          .onMove { offsets, destination in
            store.toolbar.move(fromOffsets: offsets, toOffset: destination)
            store.saveToolbar()
          }
          .onDelete { offsets in
            store.toolbar.remove(atOffsets: offsets)
            store.saveToolbar()
          }
        }
        Section("Custom actions") {
          ForEach(store.customActions) { action in
            Label(action.label, systemImage: action.symbol)
          }
          .onDelete { offsets in
            store.customActions.remove(atOffsets: offsets)
            store.saveCustomActions()
          }
          Button("Record a custom action") {
            store.beginRecordingAction()
          }
        }
        Section("About") {
          LabeledContent("App", value: "0.1.0")
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.background)
      .navigationTitle("Settings")
      .environment(\.editMode, .constant(.active))
      .onAppear { store.refreshPairingPin() }
    }
  }
}

private extension Appearance {
  var label: String {
    switch self {
    case .system: "System"
    case .dark: "Dark"
    case .light: "Light"
    }
  }
}
