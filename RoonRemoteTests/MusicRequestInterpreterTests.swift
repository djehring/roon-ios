import Foundation
import Testing

@Suite("Music request interpretation")
struct MusicRequestInterpreterTests {
  private let rooms = ["Kitchen Speakers", "Office", "Living Room"]

  @Test func spokenNumbersMatchStationDigits() {
    #expect(RoonVoiceMatch.score("BBC Radio 3", query: "Radio Three") >= 50)
    #expect(RoonVoiceMatch.score("BBC Radio 6 Music", query: "six music") >= 50)
    #expect(RoonVoiceMatch.digits("Radio Three") == "Radio 3")
  }

  @Test func spokenPlaylistNamesIgnoreSpacing() {
    #expect(RoonVoiceMatch.score("Bathtime 3", query: "Bath Time three") == 95)
    #expect(RoonVoiceMatch.score("Bathtime", query: "Bath Time three") < 50)
    #expect(RoonVoiceMatch.score("Rumours Fleetwood Mac", query: "Rumours — Fleetwood Mac") == 100)
  }

  @Test func findsPartialRoomAfterPreposition() {
    let request = MusicRequestHeuristics.interpret("Radio 3 in the kitchen", roomNames: rooms)
    #expect(request.query == "Radio 3")
    #expect(request.room == "Kitchen Speakers")
    #expect(request.kind == .radio)
  }

  @Test(arguments: ["Radio 3 in the kitchen with Roon", "Radio 3 in the kitchen using House Remote."])
  func removesEitherAppName(_ phrase: String) {
    let request = MusicRequestHeuristics.interpret(SiriMusicRequest.removingAppName(phrase), roomNames: rooms)
    #expect(request.query == "Radio 3")
    #expect(request.room == "Kitchen Speakers")
  }

  @Test func findsBareTrailingRoomOnlyWhenExact() {
    let bare = MusicRequestHeuristics.interpret("Radio 3 office", roomNames: rooms)
    #expect(bare.query == "Radio 3")
    #expect(bare.room == "Office")
    #expect(MusicRequestHeuristics.interpret("Radio 3 kitchen", roomNames: rooms).room == nil)
  }

  @Test(arguments: ["Life on Mars", "jazz in the 1960s", "Live in the USA"])
  func keepsMusicPrepositions(_ phrase: String) {
    let request = MusicRequestHeuristics.interpret(phrase, roomNames: rooms)
    #expect(request.query == phrase)
    #expect(request.room == nil)
  }

  @Test func classifiesNamedKinds() {
    #expect(MusicRequestHeuristics.classify("the album Kind of Blue") == (.album, "Kind of Blue"))
    #expect(MusicRequestHeuristics.classify("my playlist Sunday Morning") == (.playlist, "Sunday Morning"))
    #expect(MusicRequestHeuristics.classify("Sunday Morning playlist") == (.playlist, "Sunday Morning"))
    #expect(MusicRequestHeuristics.classify("music by Miles Davis") == (.artist, "Miles Davis"))
    #expect(MusicRequestHeuristics.classify("Classic FM") == (.radio, "Classic FM"))
    #expect(MusicRequestHeuristics.classify("British jazz from the 1960s") == (nil, "British jazz from the 1960s"))
  }

  @Test func unknownKindTriesStationsBeforeOtherLibraryItems() {
    #expect(MusicPlayRequest(query: "x", kind: nil).lookups == [.radio, .album, .playlist, .artist, .genre])
    #expect(MusicPlayRequest(query: "x", kind: .described).lookups.isEmpty)
    #expect(MusicPlayRequest(query: "x", kind: .artist).lookups == [.artist])
  }

  @Test func acceptsModelClassificationFromSpokenWords() {
    let utterance = "put on some Miles Davis in the office please"
    let heuristic = MusicRequestHeuristics.interpret(utterance, roomNames: rooms)
    let generated = MusicPlayRequest(query: "Miles Davis", room: "Office", kind: .artist)
    let request = MusicRequestInterpreter.reconcile(generated, heuristic: heuristic, utterance: utterance, roomNames: rooms)
    #expect(request == MusicPlayRequest(query: "Miles Davis", room: "Office", kind: .artist))
  }

  @Test func rejectsInventedMusicAndRooms() {
    let utterance = "Radio Three in the kitchen"
    let heuristic = MusicRequestHeuristics.interpret(utterance, roomNames: rooms)
    let invented = MusicPlayRequest(query: "BBC Radio 3", room: "Kitchen Speakers", kind: .radio)
    #expect(MusicRequestInterpreter.reconcile(invented, heuristic: heuristic, utterance: utterance, roomNames: rooms) == heuristic)

    let wrongRoom = MusicPlayRequest(query: "Radio 3", room: "Office", kind: .radio)
    let roomless = MusicRequestHeuristics.interpret("Radio 3", roomNames: rooms)
    #expect(MusicRequestInterpreter.reconcile(wrongRoom, heuristic: roomless, utterance: "Radio 3", roomNames: rooms).room == nil)
  }

  @Test func recognisesSearchCommands() {
    #expect(MusicRequestHeuristics.command("Play Radio 3 in the kitchen") == "Radio 3 in the kitchen")
    #expect(MusicRequestHeuristics.command("put on some jazz") == "some jazz")
    #expect(MusicRequestHeuristics.command("Miles Davis") == nil)
  }

  @Test func prefersTheBridgeInterpretation() async {
    let request = await MusicRequestInterpreter.interpret("put on some Miles Davis in the office", roomNames: rooms) { _, _ in
      MusicPlayRequest(query: "Miles Davis", room: "Office", kind: .artist)
    }
    #expect(request == MusicPlayRequest(query: "Miles Davis", room: "Office", kind: .artist))
  }

  @Test func fallsBackWhenTheBridgeFails() async {
    struct Unavailable: Error {}
    let request = await MusicRequestInterpreter.interpret("Radio 3 in the kitchen", roomNames: rooms) { _, _ in
      throw Unavailable()
    }
    #expect(request.room == "Kitchen Speakers")
    #expect(request.kind == .radio)
  }

  @Test func longGenreIsADescription() {
    let utterance = "British Jazz from the 1960s"
    let heuristic = MusicRequestHeuristics.interpret(utterance, roomNames: rooms)
    let generated = MusicPlayRequest(query: utterance, room: "", kind: .genre)
    let request = MusicRequestInterpreter.reconcile(generated, heuristic: heuristic, utterance: utterance, roomNames: rooms)
    #expect(request.kind == .described)
    #expect(request.query == utterance)
    let jazz = MusicRequestInterpreter.reconcile(MusicPlayRequest(query: "jazz", room: "", kind: .genre),
      heuristic: MusicRequestHeuristics.interpret("some jazz", roomNames: rooms), utterance: "some jazz", roomNames: rooms)
    #expect(jazz.kind == .genre)
  }

  @Test func keepsFullDescriptionForAISearch() {
    let utterance = "chilled British jazz from the 1960s in Office"
    let heuristic = MusicRequestHeuristics.interpret(utterance, roomNames: rooms)
    let generated = MusicPlayRequest(query: "British jazz", room: "Office", kind: .described)
    let request = MusicRequestInterpreter.reconcile(generated, heuristic: heuristic, utterance: utterance, roomNames: rooms)
    #expect(request.query == "chilled British jazz from the 1960s")
    #expect(request.room == "Office")
  }
}
