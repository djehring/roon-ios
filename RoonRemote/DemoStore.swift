import Foundation
import UIKit

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
  /// Sample browse pages, artwork and playback let the UI be exercised without
  /// sending playback commands to a real room.
  func applyDemoContent() {
    var track = Track(
      id: "demo-track",
      title: "So What",
      artist: "Miles Davis",
      album: "Kind of Blue",
      position: "3:12",
      remaining: "5:48",
      progress: 0.35,
      imageKey: "demo-cover"
    )
    if ProcessInfo.processInfo.environment["ROON_ARTIST_PREVIEW_CLASSICAL"] == "1" {
      track.title = "Violin Sonata No. 1 in D Major, Op. 12 No 1: I. Allegro con brio"
      track.artist = "Ludwig van Beethoven"
      track.album = "Beethoven: Violin Sonatas Op. 12 & Op. 24"
    }
    let pausedTrack = Track(
      id: "demo-paused",
      title: "Violin Sonata in F-flat Major",
      artist: "Mozart",
      album: "The Complete Sonatas",
      position: "1:08",
      remaining: "5:21",
      progress: 0.17,
      imageKey: nil
    )
    zones = [
      Zone(id: "living", name: "Big Sitting Room", track: track, state: .playing),
      Zone(id: "conservatory", name: "Conservatory", track: pausedTrack, state: .paused),
      Zone(id: "dining", name: "Dining Room", track: nil, state: .stopped),
      Zone(id: "gym", name: "Gym", track: nil, state: .stopped),
      Zone(id: "kitchen", name: "Kitchen", track: nil, state: .stopped),
      Zone(id: "office", name: "Office", track: nil, state: .stopped),
      Zone(id: "snug", name: "Snug", track: nil, state: .stopped),
    ]
    selectedZoneId = "living"
    isPlaying = true
    outputs = [
      Output(
        id: "living-main",
        zoneId: "living",
        name: "Big Sitting Room",
        volume: 42,
        min: 0,
        max: 100,
        muted: false,
        isFixed: false,
        canGroupWith: ["conservatory-main", "dining-main", "gym-main", "kitchen-main", "office-main", "snug-main"]
      ),
    ]
    houseOutputs = [
      OutputDescription(displayName: "Big Sitting Room", zoneId: "living", outputId: "living-main"),
      OutputDescription(displayName: "Conservatory", zoneId: "conservatory", outputId: "conservatory-main"),
      OutputDescription(displayName: "Dining Room", zoneId: "dining", outputId: "dining-main"),
      OutputDescription(displayName: "Gym", zoneId: "gym", outputId: "gym-main"),
      OutputDescription(displayName: "Kitchen", zoneId: "kitchen", outputId: "kitchen-main"),
      OutputDescription(displayName: "Office", zoneId: "office", outputId: "office-main"),
      OutputDescription(displayName: "Snug", zoneId: "snug", outputId: "snug-main"),
    ]
    queue = [
      QueueItem(
        id: "q0",
        title: "So What",
        artist: "Miles Davis",
        album: "Kind of Blue",
        imageKey: "demo-cover"
      ),
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
    seedDemoArtwork(for: "demo-cover")
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
    isAwaitingServer = false
    isDiscovering = false
    if let hierarchy = ProcessInfo.processInfo.environment["ROON_BROWSE_PREVIEW_HIERARCHY"] {
      libraryLaunchHierarchy = hierarchy
      selectedTab = .library
    }
  }

  /// Exercises the same feedback/navigation path without controlling a real room.
  func performDemoBrowseAction(itemKey: String, actionTitle: String, zoneId: String) async throws {
    try await Task.sleep(for: .seconds(1))
    if ProcessInfo.processInfo.environment["ROON_BROWSE_PREVIEW_FAIL"] == "1" {
      throw RoonAPIError.browseAction("The room is unavailable. Please try again.")
    }
    guard BrowsePlayback.startsPlayback(actionTitle),
          let index = zones.firstIndex(where: { $0.id == zoneId }) else { return }
    let titles = ["So What", "Freddie Freeloader", "Blue in Green", "All Blues", "Flamenco Sketches"]
    let trackIndex = itemKey.components(separatedBy: "-track-").last.flatMap(Int.init) ?? 0
    let title = titles[min(trackIndex, titles.count - 1)]
    zones[index].track = Track(
      id: itemKey, title: title, artist: "Miles Davis", album: "Kind of Blue",
      position: "0:00", remaining: "9:00", progress: 0, imageKey: "demo-cover"
    )
    zones[index].state = .playing
    if selectedZoneId == zoneId { isPlaying = true }
  }

  /// Puts a real square image in the artwork cache.
  ///
  /// Without this the fixtures leave every `imageKey` nil, so anything that only
  /// misbehaves once actual artwork exists — a `scaledToFill` backdrop, say —
  /// renders its placeholder branch and looks correct in the simulator while
  /// being broken against a bridge.
  private func seedDemoArtwork(for imageKey: String) {
    for pixels in [ArtworkCache.thumbnailPixels, ArtworkCache.gridPixels, ArtworkCache.heroPixels] {
      guard let data = Self.demoCover(pixels: pixels) else { continue }
      artwork.insert(data, for: ArtworkCache.Key(imageKey: imageKey, pixels: pixels))
    }
  }

  private static func demoCover(pixels: Int) -> Data? {
    let size = CGSize(width: pixels, height: pixels)
    let image = UIGraphicsImageRenderer(size: size).image { context in
      let space = CGColorSpaceCreateDeviceRGB()
      let colors = [
        UIColor(red: 0.18, green: 0.26, blue: 0.38, alpha: 1).cgColor,
        UIColor(red: 0.68, green: 0.47, blue: 0.30, alpha: 1).cgColor,
      ]
      guard let gradient = CGGradient(
        colorsSpace: space,
        colors: colors as CFArray,
        locations: [0, 1]
      ) else { return }
      context.cgContext.drawLinearGradient(
        gradient,
        start: .zero,
        end: CGPoint(x: size.width, y: size.height),
        options: []
      )
    }
    return image.jpegData(compressionQuality: 0.9)
  }

  /// Roon's browse root is a menu rather than content, and Library is one of
  /// its rows. Modelling that here is what lets the Library sidebar entry's
  /// step through the root be exercised without a bridge.
  private static let browseRootRows = [
    "Library", "Playlists", "My Live Radio", "Genres", "TIDAL", "Qobuz", "Settings",
  ]

  func demoArtistCreditPage(path: CinemaMusicPath) -> CinemaMusicPage {
    let classical = ProcessInfo.processInfo.environment["ROON_ARTIST_PREVIEW_CLASSICAL"] == "1"
    let title = classical ? "Beethoven: Violin Sonatas Op. 12 & Op. 24" : "Kind of Blue"
    let credits = classical
      ? "[[16206970|Alina Ibragimova]], [[9095290|Cédric Tiberghien]]"
      : "[[1|Miles Davis]]"
    // Reproduce the live long-title search miss, followed by the shorter query.
    let items: [CinemaMusicItem] = classical && path.query == title ? [] : [
      CinemaMusicItem(title: title, subtitle: credits, imageKey: "demo-cover", kind: "list", path: path),
    ]
    return CinemaMusicPage(title: "Search", kind: "list", path: path, items: items)
  }

  func demoBrowsePage(
    hierarchy: String,
    itemKey: String?,
    input: String?,
    childTitled: String? = nil
  ) -> BrowsePage {
    if hierarchy == "search" {
      let rows: [(String, String)]?
      let title: String
      switch itemKey {
      case nil where input != nil:
        title = "Search"
        rows = ["Alina Ibragimova", "Cedric Tiberghien"].contains(input ?? "")
          ? [("Artists", "demo-search-artists"), ("Albums", "demo-performer-albums")]
          : [("Artists", "demo-search-artists")]
      case "demo-search-artists":
        title = "Artists"
        rows = [("Miles Davis", "demo-artist-miles-davis")]
      case "demo-artist-miles-davis":
        title = "Miles Davis"
        rows = [("Discography", "demo-miles-discography")]
      case "demo-miles-discography":
        title = "Discography"
        rows = [("Kind of Blue", "kind-of-blue"), ("1958 Miles", "1958-miles")]
      default:
        title = ""
        rows = nil
      }
      if itemKey == "demo-performer-albums" {
        return BrowsePage(title: "Albums", items: [
          BrowseNode(
            id: "demo-beethoven", title: "Beethoven: Violin Sonatas Op. 12 & Op. 24",
            subtitle: "[[16206970|Alina Ibragimova]], [[9095290|Cédric Tiberghien]]",
            symbol: "opticaldisc", actions: [], isPrompt: false, children: [],
            itemKey: "beethoven-sonatas", hierarchy: hierarchy, hint: "list"
          ),
        ])
      }
      if let rows {
        return BrowsePage(title: title, items: rows.map { name, key in
          BrowseNode(
            id: key, title: name, symbol: "opticaldisc", actions: [],
            isPrompt: false, children: [], itemKey: key, hierarchy: hierarchy, hint: "list"
          )
        })
      }
    }

    if hierarchy == "browse", itemKey == nil, childTitled == nil {
      return BrowsePage(
        title: "Browse",
        items: Self.browseRootRows.enumerated().map { index, name in
          BrowseNode(
            id: "demo-browse-root-\(index)",
            title: name,
            subtitle: nil,
            symbol: "folder",
            actions: [],
            isPrompt: false,
            children: [],
            itemKey: "browse-root-\(index)",
            imageKey: nil,
            hierarchy: hierarchy,
            hint: nil
          )
        }
      )
    }

    if let itemKey {
      if itemKey.contains("-track-") {
        return BrowsePage(title: "Track actions", items: ["Play Now", "Queue", "Play Next"].map { title in
          BrowseNode(
            id: "\(itemKey)-\(title)", title: title, subtitle: nil, symbol: "play.circle",
            actions: [], isPrompt: false, children: [], itemKey: "\(itemKey)-\(title)",
            imageKey: nil, hierarchy: hierarchy, hint: "action"
          )
        })
      }
      let tracks = [
        ("So What", "Miles Davis"),
        ("Freddie Freeloader", "Miles Davis"),
        ("Blue in Green", "Miles Davis"),
        ("All Blues", "Miles Davis"),
        ("Flamenco Sketches", "Miles Davis"),
      ]
      let collectionActions: [BrowseNode] = hierarchy == "playlists" ? [] : [
        BrowseNode(
          id: "\(itemKey)-play", title: "Play Album", subtitle: nil, symbol: "play.circle",
          actions: [], isPrompt: false, children: [], itemKey: itemKey,
          imageKey: nil, hierarchy: hierarchy, hint: "action"
        ),
      ]
      return BrowsePage(
        title: itemKey.replacingOccurrences(of: "-", with: " ").capitalized,
        items: collectionActions + tracks.enumerated().map { index, track in
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
    let scrambled = names.reversed().map { $0 }
    let filtered = input.map { query in
      scrambled.filter { $0.0.localizedCaseInsensitiveContains(query) }
    } ?? scrambled
    return BrowsePage(
      title: childTitled
        ?? library.first { $0.hierarchy == hierarchy }?.title
        ?? hierarchy.capitalized,
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
