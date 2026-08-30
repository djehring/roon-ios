import Testing

@Suite("Queue timeline")
struct QueueTimelineTests {
  private func item(_ id: String, _ title: String, artist: String = "Miles Davis") -> QueueItem {
    QueueItem(id: id, title: title, artist: artist, album: "Kind of Blue", imageKey: nil)
  }

  private func track(_ title: String, artist: String = "Miles Davis") -> Track {
    Track(
      id: "current",
      title: title,
      artist: artist,
      album: "Kind of Blue",
      position: "0:10",
      remaining: "9:12",
      progress: 0.02,
      imageKey: nil
    )
  }

  private var queue: [QueueItem] {
    [
      item("1", "So What"),
      item("2", "Freddie Freeloader"),
      item("3", "Blue in Green"),
    ]
  }

  @Test("up next is the track after the one playing, not the one playing")
  func upNextSkipsTheCurrentTrack() {
    // The reported bug: Roon leads the queue with the current track, so the
    // first entry named what was already playing.
    #expect(QueueTimeline.upNext(queue: queue, current: track("So What"))?.title == "Freddie Freeloader")
  }

  @Test("upcoming drops the playing track and keeps the rest in order")
  func upcomingDropsTheCurrentTrack() {
    let upcoming = QueueTimeline.upcoming(queue: queue, current: track("So What"))

    #expect(upcoming.map(\.title) == ["Freddie Freeloader", "Blue in Green"])
  }

  @Test("a queue that already excludes the playing track is untouched")
  func queueWithoutCurrentTrackIsUntouched() {
    // Guards against losing a real entry if the bridge changes convention.
    let upcoming = QueueTimeline.upcoming(queue: queue, current: track("Flamenco Sketches"))

    #expect(upcoming.map(\.title) == ["So What", "Freddie Freeloader", "Blue in Green"])
  }

  @Test("only the first entry is dropped when a track repeats later")
  func repeatedTrackLaterInQueueSurvives() {
    let repeated = [item("1", "So What"), item("2", "Blue in Green"), item("3", "So What")]
    let upcoming = QueueTimeline.upcoming(queue: repeated, current: track("So What"))

    #expect(upcoming.map(\.title) == ["Blue in Green", "So What"])
  }

  @Test("matching ignores case and accents")
  func matchingIsForgiving() {
    let accented = [item("1", "Dvořák: Humoresque"), item("2", "Next")]
    let upcoming = QueueTimeline.upcoming(
      queue: accented,
      current: track("dvorak: humoresque")
    )

    #expect(upcoming.map(\.title) == ["Next"])
  }

  @Test("a different artist with the same title is not treated as the current track")
  func artistDistinguishesSameTitle() {
    let covers = [item("1", "My Way", artist: "Sid Vicious"), item("2", "Next")]
    let upcoming = QueueTimeline.upcoming(
      queue: covers,
      current: track("My Way", artist: "Frank Sinatra")
    )

    #expect(upcoming.map(\.title) == ["My Way", "Next"])
  }

  @Test("a missing artist on either side still matches on title")
  func missingArtistFallsBackToTitle() {
    let unnamed = [item("1", "So What", artist: ""), item("2", "Next")]
    let upcoming = QueueTimeline.upcoming(queue: unnamed, current: track("So What"))

    #expect(upcoming.map(\.title) == ["Next"])
  }

  @Test("the last queued track leaves nothing up next")
  func lastTrackLeavesNothing() {
    let single = [item("1", "So What")]

    #expect(QueueTimeline.upcoming(queue: single, current: track("So What")).isEmpty)
    #expect(QueueTimeline.upNext(queue: single, current: track("So What")) == nil)
  }

  @Test("an empty queue and an absent track are handled")
  func emptyInputs() {
    #expect(QueueTimeline.upcoming(queue: [], current: track("So What")).isEmpty)
    #expect(QueueTimeline.upNext(queue: [], current: nil) == nil)
    #expect(QueueTimeline.upcoming(queue: queue, current: nil).count == 3)
  }
}
