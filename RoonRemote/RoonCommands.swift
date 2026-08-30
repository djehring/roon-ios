import SwiftUI

struct RoonCommands: Commands {
  let store: MockStore

  var body: some Commands {
    CommandMenu("Playback") {
      Button(store.isPlaying ? "Pause" : "Play") {
        store.togglePlay()
      }
      .keyboardShortcut(.space, modifiers: [])

      Divider()

      Button("Previous Track") {
        store.previous()
      }
      .keyboardShortcut(.leftArrow, modifiers: .command)

      Button("Next Track") {
        store.skip()
      }
      .keyboardShortcut(.rightArrow, modifiers: .command)

      Divider()

      Button("Volume Up") {
        store.adjustVolume(by: 2)
      }
      .keyboardShortcut(.upArrow, modifiers: .command)

      Button("Volume Down") {
        store.adjustVolume(by: -2)
      }
      .keyboardShortcut(.downArrow, modifiers: .command)
    }

    CommandMenu("Navigate") {
      Button("Now Playing") {
        store.selectedTab = .nowPlaying
      }
      .keyboardShortcut("1", modifiers: .command)

      Button("Rooms") {
        store.selectedTab = .rooms
      }
      .keyboardShortcut("2", modifiers: .command)

      Button("Library") {
        store.selectedTab = .library
      }
      .keyboardShortcut("3", modifiers: .command)

      Button("Search") {
        store.selectedTab = .search
      }
      .keyboardShortcut("f", modifiers: .command)

      Button("Settings") {
        store.selectedTab = .settings
      }
      .keyboardShortcut(",", modifiers: .command)
    }
  }
}
