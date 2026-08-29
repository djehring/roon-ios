import SwiftUI

@main
struct RoonRemoteWatchApp: App {
  var body: some Scene {
    WindowGroup {
      WatchRootView()
    }
  }
}

struct WatchRootView: View {
  @State private var isPlaying = true
  @State private var volume = 0.62
  @State private var zone = "Living Room"

  var body: some View {
    TabView {
      nowPlaying
      zones
    }
    .tabViewStyle(.verticalPage)
  }

  private var nowPlaying: some View {
    VStack(spacing: 6) {
      CoverArt(title: "Kind of Blue", corner: 8)
        .frame(width: 72, height: 72)
      Text("So What")
        .font(.headline)
        .lineLimit(1)
      Text("Miles Davis")
        .font(.footnote)
        .foregroundStyle(.secondary)
      HStack(spacing: 18) {
        Button {
          isPlaying.toggle()
        } label: {
          Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        }
        Button {} label: {
          Image(systemName: "forward.end.fill")
        }
      }
      .font(.title3)
      .tint(Color(hex: 0xC4A46A))
    }
    .focusable()
    .digitalCrownRotation($volume, from: 0, through: 1, by: 0.02)
  }

  private var zones: some View {
    List {
      ForEach(["Living Room", "Kitchen", "Office"], id: \.self) { name in
        Button {
          zone = name
        } label: {
          HStack {
            Text(name)
            Spacer()
            if name == zone {
              Image(systemName: "checkmark")
                .foregroundStyle(Color(hex: 0xC4A46A))
            }
          }
        }
      }
    }
    .navigationTitle("Rooms")
  }
}
