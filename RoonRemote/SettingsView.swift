import SwiftUI
import WatchConnectivity

/// Compact root's Settings tab. The regular root hosts `SettingsList` directly,
/// inside the navigation stack it already owns for the detail column.
struct SettingsView: View {
  var body: some View {
    NavigationStack {
      SettingsList()
    }
  }
}

struct SettingsList: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
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
      Section("Siri") {
        Text("Say \"Hey Siri, play Radio 3 in the Kitchen with Roon.\" Room names match your Roon zones. Radio stations come from Live Radio first, then albums.")
          .foregroundStyle(Palette.secondary)
      }
      if WCSession.isSupported() {
        Section("Watch") {
          Text("Same room as the phone. Tap to play, swipe for skip, queue, and rooms. Crown is volume. Long-press for stop, mute, and transfer.")
            .foregroundStyle(Palette.secondary)
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

private extension Appearance {
  var label: String {
    switch self {
    case .system: "System"
    case .dark: "Dark"
    case .light: "Light"
    }
  }
}
