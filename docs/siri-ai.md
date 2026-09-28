# Siri AI music integration

House Remote is a remote control for Roon. The bridge finds the tracks, and the
app submits that ordered list with an explicit Roon zone ID to the bridge for
playback. Roon plays the music on that room's equipment. Siri's audio schema
describes the command; this integration does not stream the music to the phone,
select a phone audio output, or use Spotify or Apple Music for playback.

House Remote uses the iOS 27 `.audio.songCollection`, `.audio.playAudio`, and
`.system.searchInApp` schemas. An `IntentValueQuery` receives `MediaIntents.AudioSearch`
and sends its search text to the existing `/aisearch` endpoint. The play intent
submits the captured result list to `/play-tracks`. Query resolution never plays
music. Search-only requests open the app's AI Search tab.

An explicitly named zone ID, query time context, and result list survive app
relaunches in a bounded local cache. Playback requires that exact zone to remain
available. Results without a named room remain unassigned until the play intent
asks for a room. The audio play intent keeps Apple's schema parameters and presents
room-bound music collections using its audio parameter. The Play in a room shortcut
prompts for a complete music-and-room request. An old cached implicit room is not
accepted as an explicit choice.
Repeated resolution of the same request in the same room reuses results for two
minutes, avoiding redundant AI searches and changing entity identifiers.
Native Siri AI queries can contain the app name, or just a follow-up room.
`SiriMusicRequest` removes a trailing app invocation and recognizes room-only
follow-ups. Those reuse the most recent substantive search on the same bridge
for up to five minutes. With no recent music context, they return a localized
request for the music and room instead of sending “Play” to AI Search.
The play intent uses `LongRunningIntent` with regular elapsed-time updates because
Roon's track lookup and queue creation can exceed the default 30-second background
limit. House Remote reports success only after receiving a fresh Roon event showing
one of the requested tracks playing in the captured room.
No full-library Spotlight indexing or audio URL resolution is included. Existing
App Shortcuts remain available on iOS 18–26; their play action falls back to AI
Search after the existing station/album resolver finds no match.

Apple references:

- [Responding to audio search and playback requests](https://developer.apple.com/documentation/mediaintents/responding-to-audio-search-and-playback-requests)
- [Audio schemas](https://developer.apple.com/documentation/appintents/app-schema-domain-audio)
- [In-app search schema](https://developer.apple.com/documentation/appintents/appschema/systemintent/searchinapp)
- [Extended background execution](https://developer.apple.com/documentation/appintents/longrunningintent)

## Apple documentation review

Reviewed Apple's current Siri AI overview, audio integration guide, CosmoTunes
sample, WWDC26 sessions 343/345, and AppIntentsTesting documentation on 2026-09-28.

- The documented audio path is `AudioSearch` → `IntentValueQuery` → audio entities
  → an intent adopting `.audio.playAudio`. The app decides how to search for
  matching content. House Remote can pass the supplied search string to its own
  AI service. CosmoTunes' keyword tokenization is sample application logic, not
  a requirement to split a descriptive music request.
  [Audio integration guide](https://developer.apple.com/documentation/mediaintents/responding-to-audio-search-and-playback-requests)
- The search string is based on Siri's understanding of the request. It is not a
  documented verbatim-transcript interface, nor a mechanism for forcing Siri to
  skip its own planning. The structured query path also supports content that is
  not indexed ahead of time. Missing full-library Spotlight indexing alone does
  not establish the cause of this failure.
  [WWDC structured search discussion](https://developer.apple.com/videos/play/wwdc2026/343/)
- `.system.searchInApp` presents search results in the app. It is separate from
  the audio entity lookup and play action; opening search is not completed playback.
  [Search-in-app schema](https://developer.apple.com/documentation/appintents/appschema/systemintent/searchinapp)
- Apple Intelligence only consumes schema-defined properties. Additional optional
  parameters are for Shortcuts. The published `.audio.playAudio` contract has
  audio content, playback attributes, warmup result, and queue location, but no
  custom Roon-room field. A room added to our Swift intent or entity is therefore
  not automatically a Siri-understood playback destination. Our room prompt is
  app-side handling. It was subsequently verified in an actual Siri AI conversation
  using the room list described below.
  [Schema contract rules](https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence),
  [Play-audio schema](https://developer.apple.com/documentation/appintents/appschema/audiointent/playaudio)
- The successful `testNativeAudioIntentPlayback` starts with
  `entities(matching:)`, not `SiriMusicAudioQuery.values(for: AudioSearch)`.
  It therefore bypasses the structured query and its union-valued result.
  The subsequent `testNativeAudioSearchHandoff` covers the structured query using
  `IntentDefinitions.valueQueries`; its verified result is recorded below.
  It deliberately does not start playback. Siri's natural-language routing is
  still a separate boundary that needs to succeed.
  [Value-query test definitions](https://developer.apple.com/documentation/appintentstesting/intentdefinitions),
  [Testing guidance](https://developer.apple.com/documentation/appintentstesting/testing-your-app-intents-code)

These findings support retaining the native audio integration. The earlier
handoff failures do not establish an Apple defect; the room-list flow subsequently
reached the play handler successfully.

## Device verification

**Status on 2026-09-28: the user confirmed working Siri AI playback and the Roon
room list.** The verified request omits the room initially, then uses the room list.
The iPhone is running iOS 27.0 (24A437), using Xcode 27.0 (27A266a).
Build 6 includes the native audio schemas and explicitly executes search,
entity resolution, and playback in the main app, where bridge pairing lives.

Verified boundaries:

- At 19:12 BST, a fresh conversation in the new Siri AI app received
  `Play British jazz from the 1960s using House Remote.` The trace shows the full
  description reaching AI Search, followed by `collection.resolve`,
  `audio.play.perform`, and `audio.room.requested`. The user saw the room list.
  Office was then resolved, and `bridge.play.send` submitted the ten captured
  tracks with Office's zone ID. The user confirmed that it was working.
  This is actual Siri AI routing, unlike the direct intent tests below.
- The diagnostic ended at 19:13:07 BST while bridge playback was still pending in
  the captured trace. Siri subsequently displayed an app-quit error, but the UI
  test's app teardown is a possible cause; this is not established as an app crash.
  The captured run contains no final `playback.confirmed` entry. Keep automated
  diagnostics alive through room selection and bridge completion when checking
  Siri's final success response. Preserve the installed working build.
- At 19:09 BST, `testNativeAudioSearchHandoff` passed on the iPhone. A real
  `AudioSearch` crossed the system/app boundary, returned one collection with
  the complete query as its title, and a repeated query returned the same
  identifier. The test used the bridge's AI search without invoking playback.
- Captured native `AudioSearch` requests contained the complete description
  `British jazz from the 1960s`. House Remote forwarded the description to its
  existing AI Search. Repeated resolution reused the same collection; there is
  no evidence of House Remote splitting this request into separate keyword searches.
- `AppIntentsTesting` invoked the native collection query and play intent across
  the app/system boundary with an explicit Office room. Ten tracks were submitted,
  five were unavailable, and a fresh Roon event confirmed “Down in the Village”
  playing in Office. This validates the app's search/play path, not Siri routing.
- Earlier tests exercised the new Siri AI conversation app (`com.apple.campo`)
  directly. Some conversations called the full-query search repeatedly without ever calling
  `collection.resolve` or `audio.play.perform`. Later conversations rejected House
  Remote before any search callback. An explicit 25-second registration wait did
  not restore playback: Siri replied that House Remote could not play music.
- A subsequent search-only conversation on the final installed build used
  `Search House Remote for British jazz from the 1960s.` Siri reported no results;
  the app trace showed no audio/entity search callback. This response is not
  evidence that House Remote's AI search ran and returned an empty list.
- Device Console captured `assistant_service` parameter-conversion failures during
  one rejected conversation: `FlowToolTransformationError Code=3` and
  `InitializeToolTask failed to inject parameters`. The preceding conversions were
  in Apple's MediaIntents bundle. Private tool identifiers were redacted, so these
  logs do not establish whether the underlying cause is app metadata or Siri.
- A Spotify permission prompt was reported by the user during a failed route.
  Spotify has no role in this integration and its access was not authorized.

The 284 unit tests previously passed, covering complete query preservation,
known-room suffixes, ordered playback, cancellation, bridge errors, cache and
follow-up boundaries, and fresh playback confirmation. iOS/tvOS builds and schema
metadata extraction passed. These checks independently validate app behavior.
The successful Siri conversation above was entered as text; spoken recognition
has not been separately verified.

### Device diagnostics

`SiriPlaybackDeviceTests` contains four separate, opt-in diagnostics:

- `testNativeAudioSearchHandoff` uses the structured `AudioSearch` value query,
  checks the returned collection's full title and repeated-query identity,
  and never invokes playback. Enable `TEST_RUNNER_ROON_NATIVE_SEARCH_TEST=1`.
- `testSiriAIConversationDiagnostic` opens the **new Siri AI conversation app**.
  Enable `TEST_RUNNER_ROON_SIRI_INSPECT=1`, supply
  `TEST_RUNNER_ROON_SIRI_AI_REQUEST`, and optionally set
  `TEST_RUNNER_ROON_SIRI_AI_NEW=1` to create a fresh conversation. Set
  `TEST_RUNNER_ROON_SIRI_INDEX_WAIT=25` when checking asynchronous registration after
  installing a build. The diagnostic captures a screenshot; passing XCTest only
  means that automation completed, not that Siri played anything.
- `testNativeAudioIntentPlayback` uses `AppIntentsTesting`, independently of Siri's
  language routing. Enable `TEST_RUNNER_ROON_NATIVE_AUDIO_TEST=1`. This really plays
  music; its default request names Office. Override `TEST_RUNNER_ROON_SIRI_REQUEST`
  to name a different intended room.
- `testLiveSiriPlayback` uses the older `XCUISiriService` interface. Enable
  `TEST_RUNNER_ROON_SIRI_LIVE_TEST=1` only when diagnosing that interface. Its result
  must not be described as a successful Siri AI conversation.

Retrieve `Library/Application Support/Siri/diagnostics.json` from the app container
for incoming queries and `playback.confirmed` events. The debug-only trace is
bounded to 100 entries and omits bridge credentials. Check the requested room's
actual playback as well as the trace.

### Remaining acceptance checks

Use the new Siri AI conversation interface with the phone paired to its bridge
and the same AI configuration as in-app search:

1. Search for `British jazz from the 1960s` in House Remote. Confirm the complete
   description reaches AI Search and playback remains unchanged.
2. Check whether naming Office in the initial request reliably reaches playback.
   This phrasing failed in earlier tests; the verified route chooses a room from
   the subsequent list.
3. Repeat the successful room-list flow through Siri's final success response
   without UI-test teardown interrupting the app. If Siri removes a spoken room
   from the music query, the app must ask again instead of using the current UI room.
4. Check unavailable rooms, missing AI configuration, unavailable bridge, and
   unavailable tracks. Never report success without fresh playback confirmation.
5. Repeat with the app foregrounded, backgrounded, and terminated, including a
   slow bridge response. Siri controls search-resolution timeouts.

Do not present an old App Shortcut, a successful build, or a direct intent test as
completion of these Siri AI checks.
