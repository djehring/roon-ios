# Editable Cinema soundtracks

Implemented locally on 21 September 2026 in `roon-ios` and the companion
`roon-web-stack` repository. Install matching native and bridge builds to use it.

## Experience

- **Create Cinema** is visible on album and playlist detail pages and in the queue.
  AI results use the same label. **New Cinema** starts an empty soundtrack.
- The setup offers an editable name, source description and **Music**. Non-AI
  sources default to **Album artwork**, without research or an OpenAI key.
- **Music** supports native drag reordering on iPhone/iPad, explicit move controls
  on all platforms, remove and Undo. Repeated tracks are separate occurrences.
- **Add music** browses albums/playlists, searches Roon and captures the room queue.
  It collects selections before **Add N tracks** appends them. Choosing music sends
  no playback commands. Roon recording-selection pages are resolved safely; multiple
  recordings can be opened for an explicit choice.
- A captured queue offers **Include current track**. It contains the current song
  and upcoming rows at capture time; played history and future automatic-radio
  additions are outside the snapshot. Changing rooms does not change the draft.
- **Edit → Music** updates saved shared Cinema items and personal-photo montages.
  Music, title and presentation saves reuse pictures. Changing picture topics or
  context prepares replacements while the saved montage remains available.
- Changes take effect on the next explicit playback. The source Roon playlist and
  current room queue are unaffected by editing. Cancel protects modified drafts.
- **Presentation → Show track title** keeps the current room's track title and
  artist visible after playback controls fade. It works independently of picture
  captions; turn it off for a clean montage. Older items default to off.
- **Presentation → Picture motion** offers Still, Gentle motion and Ken Burns.
  Ken Burns slowly pans and zooms, continuing back and forth for a single cover.
  Holding a photograph pauses motion; the system's Reduce Motion setting keeps
  pictures still. These choices save without fetching replacement pictures.

## Storage and bridge contract

`GET /api/:client_id/time-capsules/capabilities` advertises `musicVersion: 1` and
`maxTracks: 1000`. Older bridges produce an update message before submission.

- `POST music/browse`: `{path, zoneId?}` → collection metadata and safe child paths.
- `POST music/import`: the same body → `{tracks}` in original order.
- `POST music/queue`: `{zoneId}` → named snapshot and `includesCurrent`.
- `PUT /:id/content`: `{request, baseRevision, mutationId}` → ready item or generation
  job. Stale revisions return 409; the editor retains its draft and offers saving
  a new Cinema item. Identical mutation retries are idempotent.

Requests retain the original query/date anchor and optionally store `title`,
`sourceLabel` and `clientRequestId`. Tracks optionally store a unique occurrence
`entryId`, cover key, duration and verified `roonPath`. Old manifests still decode.
Saved items retain their ID and use revisions to protect against concurrent writes.
Picture completion merges soundtrack edits made during generation.

Browse routes use isolated Roon sessions and page through collections rather than
the normal UI's 500-row or queue subscription's 150-row windows. Incomplete imports
and soundtracks over 1,000 tracks fail explicitly. Research context samples at most
40 tracks; that limit never truncates the saved soundtrack.

Roon browse keys expire, so saved routes contain verified titles, artists, cover
keys and positions instead. Playback resolves these in a fresh session. Queue
snapshots use an exact album/cover/title match. An unavailable or ambiguous recording
is reported for replacement rather than silently substituting another version.
The first resolved track uses **Play Now**, later occurrences use **Queue**; Cinema
playback disables shuffle to preserve the saved order. AI-only metadata keeps its
existing resolution path.

## Verification

Unit tests cover occurrence identity, drag ordering, Undo, import limits, source
metadata round trips, personal-photo persistence, music saves without playback or
research, optimistic concurrency and edits during picture generation. Bridge tests
also cover pagination beyond 500 rows, temporary queue subscriptions, the extra Roon
recording page, and rejection of command rows during import.

Native UI tests exercise adding a collection, reordering, removing/undoing, saving
and reopening, plus creation from an empty soundtrack. Existing Cinema picture
regeneration, failure, viewing and setup tests remain covered.

Read-only checks against the local Roon bridge imported a 113-track playlist, a
41-track classical album, a search-selected recording, and a 10-track room queue;
the complete album catalogue contained 637 entries. No live-room playback or paid
picture generation was used for verification.


Validation results on 21 September 2026: 217 native logic tests and all 461 bridge
tests passed, along with native creation/editing UI checks and Apple TV remote
navigation. The bridge's staged changes were checked in a separate checkout;
TypeScript checking and lint for all changed files pass. Two existing tour-date
tests now pin their clock so their forthcoming-event fixtures remain deterministic.
Audio-session setup runs on a serial worker and reuses the active session. The app
built and launched on an iPad with an empty Xcode issue navigator; the Apple TV
build succeeds with the existing App Intents metadata notice.

Screenshots: [iPhone](design/assets/cinema-music/iphone-music.png),
[iPad](design/assets/cinema-music/ipad-music.png),
[Apple TV](design/assets/cinema-music/tv-music.png).

Presentation follow-up: 211 native logic tests and 26 targeted bridge tests pass.
iPhone, iPad and Apple TV UI checks cover enabling track titles, selecting Ken Burns,
saving without picture generation and keeping the current title visible after controls
fade. iPhone/iPad also reopen the saved settings and verify turning the overlay off.
Single-image pan/zoom and reversal were visually checked with a local test image.
TypeScript checking and lint for the changed options and their tests pass.

Presentation screenshots: [iPhone](design/assets/cinema-music/iphone-presentation.png),
[iPad](design/assets/cinema-music/ipad-presentation.png).
