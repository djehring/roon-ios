import Foundation
import Testing

@Suite("Now Playing performer credits")
@MainActor
struct ArtistCreditsTests {
  private let title = "Beethoven: Violin Sonatas Op. 12 & Op. 24"
  private let credits = "[[16206970|Alina Ibragimova]], [[9095290|Cédric Tiberghien]]"

  private var album: NowPlayingAlbum {
    NowPlayingAlbum(track: Track(id: "movement", title: "Allegro con brio",
      artist: "Ludwig van Beethoven", album: title, position: "6:01", remaining: "2:48",
      progress: 0.68, imageKey: "album-cover"))
  }

  @Test func separatesLinkedPerformersWithoutSplittingBandNames() {
    #expect(ArtistCredits.names(in: credits) == ["Alina Ibragimova", "Cédric Tiberghien"])
    #expect(ArtistCredits.names(in: "[[1|Earth, Wind & Fire]] / [[2|AC/DC]]") == ["Earth, Wind & Fire", "AC/DC"])
    #expect(ArtistCredits.names(in: "Earth, Wind & Fire") == ["Earth, Wind & Fire"])
    #expect(ArtistCredits.names(in: "[[1|Soloist]] & Chamber Orchestra") == ["Soloist", "Chamber Orchestra"])
    #expect(ArtistCredits.names(in: "Soloist / Orchestra") == ["Soloist", "Orchestra"])
    #expect(ArtistCredits.names(in: "  ") == [])
  }

  @Test func foldsSearchAccentsWithoutChangingDisplayedNames() {
    #expect(ArtistCredits.searchQuery("Cédric Tiberghien") == "Cedric Tiberghien")
    #expect(ArtistCredits.names(in: credits).last == "Cédric Tiberghien")
  }

  @Test func resolvesPerformersWhenLongAlbumSearchMisses() async throws {
    var queries: [String] = []
    let names = try await album.artistNames { path in
      queries.append(path.query ?? "")
      let items: [CinemaMusicItem] = path.query == title ? [] : [
        CinemaMusicItem(title: title, subtitle: credits, imageKey: "album-cover", kind: "list", path: path),
      ]
      return CinemaMusicPage(title: "Search", kind: "list", path: path, items: items)
    }
    #expect(queries == [title, "Beethoven Violin Sonatas"])
    #expect(names == ["Alina Ibragimova", "Cédric Tiberghien"])
    #expect(names?.contains("Ludwig van Beethoven") == false)
  }

  @Test func opensAlbumResultsAndRejectsAnotherRecordingOfTheSameWork() async throws {
    var albumPageLoads = 0
    let names = try await album.artistNames { path in
      if path.steps.isEmpty {
        var child = path
        child.steps = [CinemaMusicStep(title: "Albums", index: 0)]
        return CinemaMusicPage(title: "Search", kind: "list", path: path, items: [
          CinemaMusicItem(title: "Albums", kind: "list", path: child),
        ])
      }
      albumPageLoads += 1
      return CinemaMusicPage(title: "Albums", kind: "list", path: path, items: [
        CinemaMusicItem(title: title, subtitle: "[[1|Wrong Performer]]", imageKey: "different-cover", kind: "list", path: path),
        CinemaMusicItem(title: title, subtitle: credits, imageKey: "album-cover", kind: "list", path: path),
      ])
    }
    #expect(albumPageLoads == 1)
    #expect(names == ["Alina Ibragimova", "Cédric Tiberghien"])
  }

  @Test func leavesAnUnmatchedAlbumUnchanged() async throws {
    let names = try await album.artistNames { path in
      CinemaMusicPage(title: "Search", kind: "list", path: path, items: [
        CinemaMusicItem(title: title, subtitle: "Wrong Performer", imageKey: "other-cover", kind: "list", path: path),
      ])
    }
    #expect(names == nil)
  }
}
