# Recently played

Recently played is available from Library on iPhone, iPad and Apple TV. It offers
an album grid and a dated track list, with an All rooms / individual room filter.
The filter does not change the room selected for playback.

The companion bridge records music played through any controller, including the
official Roon app, while it is connected to the local Roon server. Native apps do
not need to remain open. This is shared bridge history, not Roon's existing
profile history. Installing this version starts collection; older plays and plays
missed during disconnection cannot be imported. ARC coverage is not promised.

## Retention and counting

- Keep up to 14 days and 10,000 qualifying plays across the entire store.
- A play qualifies after 30 observed playing seconds, or half the known track
  duration, whichever is shorter. It appears before the track necessarily ends.
- Paused time, buffering, forward seeks and disconnected time do not count.
  Live radio and unknown-duration streams are excluded.
- Repeated notifications, pause/resume and a known continuing session after a
  short reconnect do not create new plays. A natural end-to-start transition
  can start a repeated play. An ordinary backward seek does not.
- Groups are observed once per Roon zone. Independent rooms retain separate
  plays. A recently removed zone can continue on a new zone when track metadata
  and an output establish continuity.
- The timestamp means first observed playing, not a reconstructed Roon start
  time. Roon does not supply a durable recording ID in transport metadata, so
  indistinguishable repeats, manual seeks near the end and long connection gaps
  cannot be classified perfectly. Counts can differ from Roon's history.

Album grouping uses album title, displayed artist and artwork as conservative
hints. Compilation/classical albums with changing performer labels, or changed
artwork, can appear as multiple groups. These hints do not establish exact edition
identity. Plays with no album information remain visible in Tracks.

## Reopening music

Select an album or track to find current Roon candidates. Choose the recording or
edition, then use Play Now, Play Next or Queue in the selected playback room.
Album details also allow selecting an individual track. Resolution uses isolated
browse sessions and fresh keys. Opening history or a candidate never starts music.
Unavailable items remain in history; no first title-only match is played silently.

The screens refresh on entry and while visible every 30 seconds, offer manual
refresh and load older pages on demand. A failed refresh preserves loaded rows
with an error. A disconnected bridge, an empty history and an old bridge have
separate messages. Artwork uses the existing bounded native cache.

## Bridge contract and storage

This requires the accompanying `roon-web-stack` changes. All history endpoints
use the existing paired-client access check under `/api/:client_id/history`:

| Method and path | Purpose |
| --- | --- |
| `GET /capabilities` | Version 1, retention and size limits |
| `GET /tracks` | Newest events, room list, recording status and next cursor |
| `GET /albums` | Albums derived from retained events, newest first |
| `POST /resolve` | `{eventId, kind, zoneId?}` → read-only candidate choices |
| `POST /browse` | `{path, zoneId?}` → isolated music detail page |
| `POST /play` | `{path, zoneId, action}` → explicit Play Now / Play Next / Queue |

List requests support `roomId`, `cursor` and `limit` (default 100, maximum 200).
Cursors bind the Core, view, room filter and observation boundary. Responses
include the Core, revision, first collection time, oldest retained timestamp and
recording/disconnection/storage-error status. Changing the connected Core cannot
return another Core's history.

The default store is `config/playback-history.json` relative to the bridge process,
inside the existing persistent config volume. Operators may override the path with
`HISTORY_FILE`. It is a versioned JSON snapshot, capped at 16 MiB, with bounded
metadata and at most 256 short-lived session checkpoints. No image files or
append-only play logs are stored. A temporary replacement file is also bounded.

Writes are serialized and coalesced, with atomic replacement. Cleanup runs at
startup, on writes and hourly while idle; reads and the native screens also filter
expired rows immediately. Checkpoints are refreshed at most once a minute and
when a play qualifies or a connection closes, not on each position update.
Corrupt/unreadable storage is preserved and recording reports degradation instead
of silently overwriting the file. A transient write failure leaves the last
committed file intact and retries on subsequent work.

## Validation and rollout

Implemented in the native and companion bridge repositories. The local API was
built and restarted on 27 September 2026 and is connected to Roon with history
recording enabled. The matching signed iPhone build was installed and launched on
David's connected iPhone 17 Pro the same day. The universal build was also
installed and launched on David's 12.9-inch iPad Pro; Apple TV hardware has not
been updated.

Validation covers qualification, skips/seeks, short tracks, repeat detection,
normal seek subscriptions, reconnect/restart checkpoints, Core changes, grouping,
retention without new playback, event/byte ceilings, atomic-write failure,
corrupt storage, cursor/filter validation, paired access and isolated explicit
playback. Native tests cover expiry, connection capability caching, failed/stale
requests, pagination and sidebar integration.

Verified on 27 September 2026:

- Bridge: all 503 tests across 49 suites passed; TypeScript checks, lint for
  changed sources and the production bundle passed.
- Native: all 253 logic tests passed; iOS and tvOS simulator builds passed.
- Simulator flows passed on iPhone and iPad (two tests each), and Apple TV
  (one remote-navigation test), including explicit queue feedback. Screenshots
  were inspected on all three platforms.
- The signed iPhone build passed; device tools confirmed installation and the
  running House Remote process on the physical iPhone. Phone UI interaction was
  not inspected.

A read-only observation of the existing running bridge confirmed six local rooms,
including paused and actively playing rooms with continuing position updates.
Live read-only browsing also confirmed album search candidates and the action
menu's “Add Next” label, which is mapped to the app's Play Next action.
The live restart exposed a revoked Core proxy in a late subscription callback.
The recorder now ignores callbacks from replaced connections; a lifecycle
regression test covers revoked proxies and stale notifications after reconnect.
After the repaired deployment, the same API process stayed connected throughout
a 35-second observation, and a qualifying play appeared in both Tracks and Albums
and was confirmed in the saved history file.
Feature validation did not issue real-room playback or queue commands. Repeat,
transfer and failure scenarios use deterministic fixtures; physical-device
browsing and replay behaviour remains unverified.
