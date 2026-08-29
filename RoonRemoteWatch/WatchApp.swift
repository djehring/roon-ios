import SwiftUI
import WatchKit

@main
struct RoonRemoteWatchApp: App {
  @State private var store = WatchStore()

  var body: some Scene {
    WindowGroup {
      WatchRootView()
        .environment(store)
        .task { store.activate() }
    }
  }
}

struct WatchRootView: View {
  @Environment(WatchStore.self) private var store

  var body: some View {
    TabView {
      nowPlaying
      zones
    }
    .tabViewStyle(.verticalPage)
  }

  private var nowPlaying: some View {
    VStack(spacing: 6) {
      if !store.canControl {
        Text(store.phoneReachable ? "Pair Roon on iPhone" : "Open Roon on iPhone")
          .font(.footnote)
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
      } else {
        CoverArt(
          title: store.snapshot.album ?? store.snapshot.title ?? "empty",
          image: store.cover,
          corner: 8
        )
        .frame(width: 72, height: 72)
        Text(store.snapshot.title ?? "Nothing playing")
          .font(.headline)
          .lineLimit(1)
        Text(store.snapshot.artist ?? store.snapshot.zoneName)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        HStack(spacing: 18) {
          Button {
            WKInterfaceDevice.current().play(.click)
            store.playPause()
          } label: {
            Image(
              systemName: store.snapshot.isLoading
                ? "ellipsis"
                : (store.snapshot.isPlaying ? "pause.fill" : "play.fill")
            )
          }
          .disabled(store.snapshot.isLoading)
          Button {
            WKInterfaceDevice.current().play(.click)
            store.skip()
          } label: {
            Image(systemName: "forward.end.fill")
          }
        }
        .font(.title3)
        .tint(Color(hex: 0xC4A46A))
      }
    }
    .focusable(store.crownEnabled)
    .modifier(CrownVolume(enabled: store.crownEnabled))
  }

  private var zones: some View {
    Group {
      if store.snapshot.zones.isEmpty {
        Text(store.canControl ? "No rooms yet" : "Open Roon on iPhone")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding()
      } else {
        List {
          ForEach(store.snapshot.zones) { zone in
            Button {
              WKInterfaceDevice.current().play(.click)
              store.selectZone(zone.id)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(zone.name)
                  if let subtitle = zone.subtitle {
                    Text(subtitle)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                }
                Spacer()
                if zone.id == store.snapshot.zoneId {
                  Image(systemName: "checkmark")
                    .foregroundStyle(Color(hex: 0xC4A46A))
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("Rooms")
  }
}

private struct CrownVolume: ViewModifier {
  @Environment(WatchStore.self) private var store
  let enabled: Bool

  func body(content: Content) -> some View {
    let min = store.snapshot.volumeMin
    let max = store.snapshot.volumeMax
    if enabled, max > min {
      content.digitalCrownRotation(
        Binding(
          get: { store.volume },
          set: { store.crownMoved($0) }
        ),
        from: min,
        through: max,
        by: max - min > 20 ? 1 : 0.5,
        sensitivity: .medium,
        isContinuous: true,
        isHapticFeedbackEnabled: true
      )
    } else {
      content
    }
  }
}
