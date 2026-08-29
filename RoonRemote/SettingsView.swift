import SwiftUI

struct SettingsView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      List {
        Section("Bridge") {
          LabeledContent("Name", value: "roon-web-stack")
          LabeledContent("Version", value: "0.1.0-prototype")
          Button("Unpair…") { store.replayOnboarding() }
          LabeledContent("PIN", value: "482193")
          Button("Rotate PIN") {}
        }
        Section("Zone") {
          Picker("Displayed zone", selection: $store.selectedZoneId) {
            ForEach(store.zones) { zone in
              Text(zone.name).tag(zone.id)
            }
          }
        }
        Section("Appearance") {
          Picker("Appearance", selection: $store.appearance) {
            ForEach(Appearance.allCases, id: \.self) { item in
              Text(item.label).tag(item)
            }
          }
          .pickerStyle(.inline)
        }
        Section("Now Playing toolbar") {
          ForEach(store.toolbar) { action in
            Label(action.label, systemImage: action.symbol)
          }
          .onMove { store.toolbar.move(fromOffsets: $0, toOffset: $1) }
          .onDelete { store.toolbar.remove(atOffsets: $0) }
        }
        Section("Custom actions") {
          ForEach(store.customActions) { action in
            Label(action.label, systemImage: action.symbol)
          }
          Button("Record a custom action") {
            store.isRecordingAction = true
            store.selectedTab = .library
          }
        }
        Section("Watch") {
          Text("Controls the same zone as the phone.")
            .foregroundStyle(Palette.secondary)
        }
        Section("Prototype") {
          Button("Replay onboarding") { store.replayOnboarding() }
          Button("Preview share sheet") { store.showSharePreview = true }
        }
        Section("About") {
          LabeledContent("App", value: "0.1.0")
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.background)
      .navigationTitle("Settings")
      .environment(\.editMode, .constant(.active))
    }
    .sheet(isPresented: $store.showSharePreview) {
      SharePreviewView()
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
