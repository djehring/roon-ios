import Foundation
import Testing

@Suite("Cinema setup")
struct CapsuleOptionsTests {
  @Test func topicSelectionIgnoresOrderButOtherOptionsStillMatter() {
    var selected = CapsuleOptions(mode: .artist, subject: " Crowded House ")
    selected.topics = [.artistImages, .career, .places, .albumCovers]
    var returned = selected
    returned.subject = "Crowded House"
    returned.topics = [.albumCovers, .artistImages, .career, .places, .places]
    #expect(selected == returned)
    returned.topics.removeAll { $0 == .places }
    #expect(selected != returned)
    returned = selected
    returned.pace = .lively
    #expect(selected != returned)
    returned = selected
    returned.order = .shuffled
    #expect(selected != returned)
    returned = selected
    returned.subject = "David Bowie"
    #expect(selected != returned)
  }
  @Test func suggestsContextWithoutLosingANamedArtistToDates() {
    #expect(CapsuleMode.suggested(query: "UK top ten this week in 1978", tracks: []) == .period)
    #expect(CapsuleMode.suggested(query: "Top ten from 1984", tracks: []) == .period)
    #expect(CapsuleMode.suggested(query: "Top Django Reinhardt hits 1939 to 1945", tracks: []) == .artist)
    #expect(CapsuleMode.suggested(query: "Beethoven Symphony No. 6", tracks: []) == .work)
    #expect(CapsuleMode.suggested(query: "Brazilian jazz in the sixties", tracks: []) == .artist)
  }
  @Test func usesTrackMetadataForArtistAndClassicalWorkSubjects() {
    let bowie = [
      CapsuleTrack(artist: "David Bowie", track: "Changes", album: "Hunky Dory"),
      CapsuleTrack(artist: "David Bowie", track: "Heroes", album: "Heroes"),
    ]
    #expect(CapsuleMode.artist.suggestedSubject(query: "Bowie greatest hits", tracks: bowie) == "David Bowie")
    let concerto = [
      CapsuleTrack(artist: "Beethoven", track: "Piano Concerto No. 5: I. Allegro", album: ""),
      CapsuleTrack(artist: "Beethoven", track: "Piano Concerto No. 5: II. Adagio", album: ""),
    ]
    #expect(
      CapsuleMode.work.suggestedSubject(query: "Emperor concerto", tracks: concerto)
        == "Beethoven — Piano Concerto No. 5"
    )
  }
  @Test func albumCoversAreAnExplicitRememberedTopic() throws {
    let options = CapsuleOptions(mode: .artist, subject: "David Bowie")
    #expect(!options.topics.contains(.albumCovers))
    var selected = options
    selected.topics.append(.albumCovers)
    let restored = try JSONDecoder().decode(CapsuleOptions.self, from: JSONEncoder().encode(selected))
    #expect(restored.topics.contains(.albumCovers))
  }
  @Test func savedPreferencesStayWithinTheirModeAndDoNotCarryOverDatesOrSubjects() throws {
    let suite = "CinemaTests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var first = CapsuleOptions(mode: .period, subject: "1978", locale: "en_GB")
    first.topics = [.headlines]
    first.periodStart = "1978-01-01"; first.periodEnd = "1978-12-31"
    first.pace = .lively; first.region = "US"
    first.rememberPreferences(in: defaults)
    var later = CapsuleOptions(mode: .period, subject: "1984", locale: "fr_FR")
    later.restorePreferences(from: defaults)
    #expect(later.subject == "1984")
    #expect(later.region == "FR")
    #expect(later.periodStart == nil)
    #expect(later.topics == [.headlines])
    #expect(later.pace == .lively)
    var classical = CapsuleOptions(mode: .work, subject: "Beethoven")
    classical.restorePreferences(from: defaults)
    #expect(classical.pace == .relaxed)
    #expect(!classical.topics.contains(.headlines))
  }
  @Test func requestRoundTripKeepsSoundtrackAndOptions() throws {
    var request = CapsuleRequest(context: CapsuleSearchContext(query: "Django hits"), tracks: [])
    request.options = CapsuleOptions(mode: .artist, subject: "Django and Paris")
    request.options?.topics = [.artistImages, .places]
    let restored = try JSONDecoder().decode(CapsuleRequest.self, from: JSONEncoder().encode(request))
    #expect(restored == request)
    #expect(restored.query == "Django hits")
    #expect(restored.options?.subject == "Django and Paris")
  }
  @Test func oldSavedRequestsStillDecode() throws {
    let data = Data(#"{"query":"1984","requestedAt":"2026-09-18T00:00:00Z","locale":"en_GB","timeZone":"Europe/London","tracks":[]}"#.utf8)
    let restored = try JSONDecoder().decode(CapsuleRequest.self, from: data)
    #expect(restored.options == nil)
  }
  @Test func relaxedAndLivelyPacingPreservePauseAndManualNavigation() {
    var clock = MontagePlayback()
    clock.advance(seconds: 15, playing: true, count: 4, secondsPerPhoto: 16)
    #expect(clock.index == 0)
    clock.advance(seconds: 30, playing: false, count: 4, secondsPerPhoto: 16)
    clock.advance(seconds: 1, playing: true, count: 4, secondsPerPhoto: 16)
    #expect(clock.index == 1)
    clock.move(1, count: 4)
    #expect(clock.elapsed == 0)
    clock.advance(seconds: 5, playing: true, count: 4, secondsPerPhoto: 5)
    #expect(clock.index == 3)
    clock.advance(seconds: 5, playing: true, count: 4, secondsPerPhoto: 0)
    #expect(clock.index == 3)
  }
}
