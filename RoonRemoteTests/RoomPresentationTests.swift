import Testing
import UIKit

@Suite("Room presentation")
struct RoomPresentationTests {
  @Test(
    "room names map to recognizable symbols",
    arguments: [
      ("Kitchen", "refrigerator.fill"),
      ("Dining Room", "fork.knife"),
      ("Main Bedroom", "bed.double.fill"),
      ("Office", "desktopcomputer"),
      ("Home Gym", "dumbbell.fill"),
      ("Conservatory", "leaf.fill"),
      ("Garden", "tree.fill"),
      ("Garage", "car.fill"),
      ("Snug", "fireplace.fill"),
      ("Big Sitting Room", "sofa.fill"),
    ]
  )
  func roomSymbols(room: String, symbol: String) {
    #expect(RoomPresentation.symbol(for: room) == symbol)
    #expect(UIImage(systemName: symbol) != nil)
  }

  @Test("unknown room names use a speaker")
  func defaultSymbol() {
    #expect(RoomPresentation.symbol(for: "The West Wing") == "hifispeaker.fill")
  }

  @Test("playing and paused rooms name their track")
  func activeStatus() {
    let track = demoTrack()
    #expect(
      RoomPresentation.status(
        for: Zone(id: "playing", name: "Kitchen", track: track, state: .playing)
      ) == "Playing · So What"
    )
    #expect(
      RoomPresentation.status(
        for: Zone(id: "paused", name: "Office", track: track, state: .paused)
      ) == "Paused · So What"
    )
  }

  @Test("empty rooms have an explicit idle status")
  func idleStatus() {
    #expect(
      RoomPresentation.status(
        for: Zone(id: "idle", name: "Gym", track: nil, state: .stopped)
      ) == "Nothing playing"
    )
  }

  @Test("popover grows for the room list and then caps")
  func popoverHeight() {
    #expect(RoomPickerLayout.height(roomCount: 0) == 138)
    #expect(RoomPickerLayout.height(roomCount: 4) == 342)
    #expect(RoomPickerLayout.height(roomCount: 100) == RoomPickerLayout.maximumHeight)
  }

  private func demoTrack() -> Track {
    Track(
      id: "track",
      title: "So What",
      artist: "Miles Davis",
      album: "Kind of Blue",
      position: "0:00",
      remaining: "9:22",
      progress: 0,
      imageKey: nil
    )
  }
}
