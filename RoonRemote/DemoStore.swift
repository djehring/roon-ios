import Foundation

#if DEBUG
extension MockStore {
  /// True when the app was launched with `-roon-demo-store`.
  static var wantsDemoContent: Bool {
    ProcessInfo.processInfo.arguments.contains("-roon-demo-store")
  }

  static var wantsDemoOnboarding: Bool {
    ProcessInfo.processInfo.arguments.contains("-roon-demo-onboarding")
  }

  /// Fills the store with stand-in content and skips straight to the main
  /// session.
  ///
  /// Layout work is otherwise invisible on a machine with no bridge on the
  /// network: with nothing to pair against, the app never leaves onboarding.
  /// Nothing here talks to the bridge, so browse and artwork stay empty --
  /// enough to check shells, spacing, and adaptivity, not content.
  func applyDemoContent() {
    let track = Track(
      id: "demo-track",
      title: "So What",
      artist: "Miles Davis",
      album: "Kind of Blue",
      position: "3:12",
      remaining: "5:48",
      progress: 0.35,
      imageKey: nil
    )
    zones = [
      Zone(id: "living", name: "Living Room", track: track, state: .playing),
      Zone(id: "kitchen", name: "Kitchen", track: nil, state: .stopped),
      Zone(id: "study", name: "Study", track: nil, state: .paused),
    ]
    selectedZoneId = "living"
    isPlaying = true
    outputs = [
      Output(
        id: "living-main",
        zoneId: "living",
        name: "Living Room",
        volume: 42,
        min: 0,
        max: 100,
        muted: false,
        isFixed: false,
        canGroupWith: ["kitchen-main", "study-main"]
      ),
    ]
    houseOutputs = [
      OutputDescription(displayName: "Living Room", zoneId: "living", outputId: "living-main"),
      OutputDescription(displayName: "Kitchen", zoneId: "kitchen", outputId: "kitchen-main"),
      OutputDescription(displayName: "Study", zoneId: "study", outputId: "study-main"),
    ]
    queue = [
      QueueItem(
        id: "q1",
        title: "Freddie Freeloader",
        artist: "Miles Davis",
        album: "Kind of Blue",
        imageKey: nil
      ),
      QueueItem(
        id: "q2",
        title: "Blue in Green",
        artist: "Miles Davis",
        album: "Kind of Blue",
        imageKey: nil
      ),
      QueueItem(
        id: "q3",
        title: "All Blues",
        artist: "Miles Davis",
        album: "Kind of Blue",
        imageKey: nil
      ),
    ]
    aiQuery = "Late-night acoustic jazz"
    aiResults = [
      SuggestedTrack(
        id: "ai-1",
        title: "Blue in Green",
        artist: "Miles Davis",
        album: "Kind of Blue",
        error: nil,
        corrected: false
      ),
      SuggestedTrack(
        id: "ai-2",
        title: "Naima",
        artist: "John Coltrane",
        album: "Giant Steps",
        error: nil,
        corrected: false
      ),
      SuggestedTrack(
        id: "ai-3",
        title: "Peace Piece",
        artist: "Bill Evans",
        album: "Everybody Digs Bill Evans",
        error: nil,
        corrected: true
      ),
    ]
    recognizedAlbums = [
      BrowseNode(
        id: "recognized-1",
        title: "Kind of Blue",
        subtitle: "Miles Davis",
        symbol: "opticaldisc",
        actions: ["Play Now"],
        isPrompt: false,
        children: [],
        itemKey: "kind-of-blue",
        imageKey: nil,
        hierarchy: "albums",
        hint: nil
      ),
      BrowseNode(
        id: "recognized-2",
        title: "Blue Train",
        subtitle: "John Coltrane",
        symbol: "opticaldisc",
        actions: ["Play Now"],
        isPrompt: false,
        children: [],
        itemKey: "blue-train",
        imageKey: nil,
        hierarchy: "albums",
        hint: nil
      ),
    ]
    bridgeVersion = "demo"
    storyTitle = "Modal jazz finds its shape"
    storyBody = """
    ## The session

    Recorded in two afternoons at Columbia's 30th Street Studio in 1959, *Kind of
    Blue* traded chord changes for scales. Miles handed the band sketches rather
    than charts, so what you hear is first-take music being decided in the room.

    - Bill Evans shapes the harmony from underneath
    - Paul Chambers holds the pulse without ever crowding it
    - Jimmy Cobb keeps the ride cymbal conversational

    **So What** is the thesis: two chords, sixteen bars each, and enough space
    that every soloist has to bring an idea rather than a pattern. Coltrane
    answers Miles with density; Evans answers both with restraint.

    ## Why it endured

    The record sold on atmosphere and survived on structure. Modal playing gave
    improvisers room to think melodically instead of racing the changes, and that
    permission reshaped the next decade of jazz.
    """
    session = .main
  }

  func demoBrowsePage(
    hierarchy: String,
    itemKey: String?,
    input: String?
  ) -> BrowsePage {
    if let itemKey {
      let tracks = [
        ("So What", "Miles Davis"),
        ("Freddie Freeloader", "Miles Davis"),
        ("Blue in Green", "Miles Davis"),
        ("All Blues", "Miles Davis"),
        ("Flamenco Sketches", "Miles Davis"),
      ]
      return BrowsePage(
        title: itemKey.replacingOccurrences(of: "-", with: " ").capitalized,
        items: tracks.enumerated().map { index, track in
          BrowseNode(
            id: "\(itemKey)-track-\(index)",
            title: track.0,
            subtitle: track.1,
            symbol: "music.note",
            actions: ["Play Now", "Queue", "Play Next"],
            isPrompt: false,
            children: [],
            itemKey: "\(itemKey)-track-\(index)",
            imageKey: nil,
            hierarchy: hierarchy,
            hint: nil
          )
        }
      )
    }

    let names: [(String, String)] = [
      ("A Love Supreme", "John Coltrane"),
      ("Blue Train", "John Coltrane"),
      ("Chet Baker Sings", "Chet Baker"),
      ("Ellington at Newport", "Duke Ellington"),
      ("Getz/Gilberto", "Stan Getz & João Gilberto"),
      ("Head Hunters", "Herbie Hancock"),
      ("Kind of Blue", "Miles Davis"),
      ("Mingus Ah Um", "Charles Mingus"),
      ("Night Train", "Oscar Peterson Trio"),
      ("Saxophone Colossus", "Sonny Rollins"),
      ("The Black Saint", "Charles Mingus"),
      ("Time Out", "The Dave Brubeck Quartet"),
      ("Waltz for Debby", "Bill Evans Trio"),
      ("1958 Miles", "Miles Davis"),
    ]
    let filtered = input.map { query in
      names.filter { $0.0.localizedCaseInsensitiveContains(query) }
    } ?? names
    return BrowsePage(
      title: library.first { $0.hierarchy == hierarchy }?.title ?? hierarchy.capitalized,
      items: filtered.enumerated().map { index, album in
        BrowseNode(
          id: "demo-\(hierarchy)-\(index)",
          title: album.0,
          subtitle: album.1,
          symbol: "opticaldisc",
          actions: ["Play Now", "Queue", "Play Next"],
          isPrompt: false,
          children: [],
          itemKey: album.0.lowercased().replacingOccurrences(of: " ", with: "-"),
          imageKey: nil,
          hierarchy: hierarchy,
          hint: nil
        )
      }
    )
  }
}
#endif
