import SwiftUI
import WatchKit

@main
struct RoonRemoteWatchApp: App {
  @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
  @State private var store: WatchStore?
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      ZStack {
        if let store {
          WatchRootView(store: store)
            .onChange(of: scenePhase) { _, phase in
              if phase == .active {
                store.activate()
              }
            }
        }
        if store?.showsFindingServer ?? true {
          FindingServerOverlay()
        }
      }
      .task {
        await Task.yield()
        if store == nil {
          let next = WatchStore()
          next.activate()
          store = next
        }
      }
    }
  }
}

private enum WatchPane: Hashable {
  case rooms
  case queue
  case transfer
}

struct WatchRootView: View {
  @Bindable var store: WatchStore
  @State private var pane: WatchPane?

  var body: some View {
    ZStack {
      NavigationStack {
        nowPlaying
          .navigationTitle(store.snapshot.zoneName)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button {
                pane = .queue
              } label: {
                Image(systemName: "list.bullet")
              }
              .disabled(!store.canControl)
              .accessibilityLabel("Queue")
            }
            ToolbarItem(placement: .topBarTrailing) {
              Button {
                pane = .rooms
              } label: {
                Image(systemName: "hifispeaker")
              }
              .disabled(!store.canControl)
              .accessibilityLabel("Rooms")
            }
          }
          .navigationDestination(item: $pane) { pane in
            switch pane {
            case .rooms:
              WatchRoomsView(store: store)
            case .queue:
              WatchQueueView(store: store)
            case .transfer:
              WatchTransferView(store: store, pane: $pane)
            }
          }
      }
    }
    .onAppear { store.activate() }
  }

  private var nowPlaying: some View {
    ZStack {
      if store.canControl || store.snapshot.title != nil {
        CoverArt(
          title: store.snapshot.album ?? store.snapshot.title ?? "empty",
          image: store.cover,
          corner: 10
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        LinearGradient(
          colors: [.clear, .black.opacity(0.78)],
          startPoint: .center,
          endPoint: .bottom
        )
        overlayCopy
      } else {
        Text(store.phoneReachable ? "Pair Roon on iPhone" : "Open Roon on iPhone")
          .font(.footnote)
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .focusable(store.crownEnabled)
    .modifier(CrownVolume(store: store, enabled: store.crownEnabled))
    .onTapGesture { tapPlayPause() }
    .gesture(playbackDrag)
    .contextMenu {
      if store.canControl {
        Button {
          store.stop()
        } label: {
          Label("Stop", systemImage: "stop.fill")
        }
        Button {
          store.mute()
        } label: {
          Label(
            store.snapshot.muted ? "Unmute" : "Mute",
            systemImage: store.snapshot.muted ? "speaker.wave.2.fill" : "speaker.slash.fill"
          )
        }
        .disabled(store.snapshot.volumeOutputId == nil)
        Button {
          pane = .transfer
        } label: {
          Label("Transfer", systemImage: "arrow.left.arrow.right")
        }
        .disabled(store.snapshot.zones.count < 2)
      }
    }
  }

  private var overlayCopy: some View {
    VStack(spacing: 2) {
      Spacer()
      if let hud = store.volumeHUD {
        Text("\(Int(hud.rounded()))")
          .font(.system(size: 34, weight: .semibold, design: .rounded))
          .foregroundStyle(.white)
      } else if !store.snapshot.isPlaying, store.snapshot.title != nil {
        Image(systemName: store.snapshot.isLoading ? "ellipsis" : "play.fill")
          .font(.title2)
          .foregroundStyle(.white.opacity(0.9))
          .padding(.bottom, 4)
      }
      Text(store.snapshot.title ?? "Nothing playing")
        .font(.headline)
        .lineLimit(1)
        .foregroundStyle(.white)
      Text(store.snapshot.artist ?? store.snapshot.zoneName)
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.72))
        .lineLimit(1)
    }
    .padding(.horizontal, 6)
    .padding(.bottom, 2)
  }

  private var playbackDrag: some Gesture {
    DragGesture(minimumDistance: 24)
      .onEnded { value in
        guard store.canControl else { return }
        let dx = value.translation.width
        let dy = value.translation.height
        if abs(dx) > abs(dy) {
          WKInterfaceDevice.current().play(.click)
          if dx < 0 {
            store.skip()
          } else {
            store.previous()
          }
        } else if dy < 0 {
          pane = .queue
        } else {
          pane = .rooms
        }
      }
  }

  private func tapPlayPause() {
    guard store.canControl, !store.snapshot.isLoading else { return }
    WKInterfaceDevice.current().play(.click)
    store.playPause()
  }
}

private struct WatchRoomsView: View {
  @Bindable var store: WatchStore

  var body: some View {
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

private struct WatchQueueView: View {
  @Bindable var store: WatchStore

  var body: some View {
    Group {
      if store.snapshot.queue.isEmpty {
        Text("Queue is empty")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding()
      } else {
        List {
          ForEach(store.snapshot.queue) { item in
            Button {
              WKInterfaceDevice.current().play(.click)
              store.playFromHere(item.id)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                  .lineLimit(1)
                if !item.artist.isEmpty {
                  Text(item.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("Queue")
  }
}

private struct WatchTransferView: View {
  @Bindable var store: WatchStore
  @Binding var pane: WatchPane?

  var body: some View {
    let others = store.snapshot.zones.filter { $0.id != store.snapshot.zoneId }
    Group {
      if others.isEmpty {
        Text("No other rooms")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding()
      } else {
        List {
          ForEach(others) { zone in
            Button {
              WKInterfaceDevice.current().play(.click)
              store.transfer(to: zone.id)
              pane = nil
            } label: {
              Text(zone.name)
            }
          }
        }
      }
    }
    .navigationTitle("Transfer")
  }
}

private struct CrownVolume: ViewModifier {
  @Bindable var store: WatchStore
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
