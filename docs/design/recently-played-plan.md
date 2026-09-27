# Recently played — implementation plan

27 September 2026 · Implemented locally in the native and companion bridge repositories. See [implementation notes](../recently-played.md) for delivered behaviour and validation.

Add a shared **Recently played** destination to House Remote on iPhone, iPad and Apple TV. The bridge records listening as it happens and provides **Albums** and **Tracks** views. Keep at most **14 days** and **10,000 play events**, whichever removes older entries first.

**1. Define the initial experience**

- Add Recently played to the iPhone Library grid, the iPad Library sidebar and the Apple TV Library categories. Use a dedicated destination rather than inventing a Roon browse hierarchy.
- Open on Albums: artwork, album title, artist when known, and most recent play time. Tracks shows individual listening events, newest first, grouped into local calendar days; deliberate repeat plays remain separate rows.
- Default to All rooms, with an optional room filter. Display the room on track rows. Changing the history filter must not change the selected playback room.
- Selecting an album opens its details and playback actions. Selecting a track offers the existing Play Now, Play Next and Queue actions, targeting the currently selected playback room. Show that room in the action presentation.
- Explain the scope with: “Listening recorded by your bridge, kept for up to 14 days.” An empty history says it will appear as music plays while the bridge is connected.
- Distinguish an empty history, an unavailable bridge and a bridge that needs updating. Keep previously loaded rows visible during a refresh failure, with a retry action and an indication that they may be out of date.

The first release covers local Roon zones visible to the extension. It does not import Roon's existing history, promise ARC coverage, identify the listening person's profile, or add a Watch history screen. The history is shared by devices paired with the bridge.

**2. Confirm playback event behaviour before building the recorder**

The bridge already subscribes to zone changes in [zone-manager.ts](/Users/david/Development/Projects/roon-web-stack/app/roon-web-api/src/data/zone-manager.ts:70). Current handling replaces each room's current state and broadcasts it; there is no saved listening history. Track metadata is converted in [data-converter.ts](/Users/david/Development/Projects/roon-web-stack/app/roon-web-api/src/data/data-converter.ts:114).

The public transport model supplies display metadata, duration, position and playback state. It does not guarantee a durable recording ID in `now_playing`. Queue item IDs and browse item keys must not be treated as permanent recording identities.

Start with a read-only observation of normal playback and representative event fixtures. Establish which signals reliably distinguish track changes, pause/resume, repeat-one, seeking, grouped rooms, transfers and reconnects. Document any ambiguous cases before promising exact replay or exact play counts. Observation must not send playback commands.

Use this proposed qualification rule:

- A finite track qualifies after **30 seconds of observed playing time, or half its duration, whichever is shorter**.
- Count time only while connected and playing. Do not credit paused time, buffering, disconnected time or a forward seek. Use a monotonic clock for elapsed time and UTC for saved timestamps.
- Record one event when a listening session qualifies; later progress updates do not append rows. Store the time the session was first observed, without claiming it is the true start time if observation began mid-track.
- Pause/resume and ordinary reconnects continue the same session when continuity can be established. A confirmed new play or repeat starts a new event and must qualify again.
- A backward seek alone is not evidence of a new play. For indistinguishable repeat/reconnect cases, prefer avoiding a speculative duplicate and document the limitation.
- Observe grouped playback once per Roon zone. Preserve separate plays in independent zones, even when they play the same song. Carry a session across a zone transfer only when the available evidence establishes continuity.
- Exclude live radio and unknown-duration streams from the first release; station titles and changing radio metadata cannot reliably identify album tracks.

This is House Remote's counting rule and may differ from Roon's own history. Historical plays and activity during connection gaps cannot be reconstructed.

**3. Add bounded, persistent storage on the bridge**

Introduce a playback-history recorder and store, separate from client connections. Feed it initial zone snapshots, zone changes, seek updates, zone removals and connection lifecycle events. Recording continues when every native app is closed and includes observable playback started from the official Roon app.

Each retained event contains:

| Field | Purpose |
| --- | --- |
| Event ID | Stable row identity and idempotent writes |
| Core ID | Keep records associated with the correct Roon server |
| Observed-at and qualified-at times | Ordering, retention and honest timing |
| Zone ID, room name and available output IDs | Room display and continuity evidence |
| Track title, displayed artist, album and duration | History display and resolution hints |
| Artwork key, when available | Reuse the existing artwork path |
| Optional verified album/recording reference | Resolve a later browse or playback request |

Do not interpret the displayed artist as a guaranteed album artist; classical and compilation metadata need explicit handling. Missing album information is valid for a track event.

Use a versioned JSON snapshot in the bridge's existing persistent configuration volume. With a 10,000-event ceiling this avoids a new database dependency. Serialize mutations and commit with a temporary file plus atomic replacement. Persist newly qualified events promptly; do not rewrite the file for every progress tick. Save a small, bounded continuity checkpoint with committed sessions to help avoid duplicates after restart.

Retention applies to the entire store, including records from previously paired cores:

- Remove events whose observed-at time is more than 14 × 24 hours old.
- After expiry, trim the oldest events until at most 10,000 remain.
- Run cleanup on startup, before every write and hourly while idle. Filter expired entries from responses immediately, even between scheduled cleanups.
- Cap metadata field sizes and enforce a **16 MiB serialized-store ceiling**, trimming oldest events if necessary. Keep only one bounded replacement file; do not create an accumulating archive, backup series or event log.
- Bound and expire session checkpoints and any metadata-resolution cache too. Remove stale temporary files at startup.
- Store artwork references only. Use the existing image delivery and native artwork cache; a missing image gets a placeholder. Do not retain a separate permanent collection of history images.

Scope responses to the currently paired Core and clear native in-memory history when the bridge or Core changes. Keep disk writes off the playback-event handling path. A write failure must leave the previous committed snapshot intact, report recording as degraded and avoid an unbounded retry queue. Never silently present a failed load as a successfully restored empty history.

**4. Expose history through a small bridge API**

Add a dedicated history route group using the existing paired-client checks. Keep capability discovery independent of the Cinema-specific capabilities endpoint.

| Proposed endpoint under `/api/:client_id` | Response or behaviour |
| --- | --- |
| `GET /history/capabilities` | Version 1, retention days, event/byte limits, supported views and qualification rule |
| `GET /history/tracks?roomId=…&cursor=…&limit=…` | Retained events, newest first, plus next cursor and recording status |
| `GET /history/albums?roomId=…&cursor=…&limit=…` | Albums derived from the retained, filtered events, ordered by latest play |
| `POST /history/resolve` | Resolve a retained event or album into a fresh, read-only music destination; never start playback |

Use pages of 100 with a maximum requested size of 200. Use an opaque cursor anchored to the first page's ordering boundary, with event IDs as tie-breakers, so new plays do not duplicate or skip older rows during pagination. Handle expiry during paging gracefully. Include the store revision, recording start time and connection/recording status so clients can distinguish “nothing recorded” from “recording unavailable.”

Derive recent albums from track history rather than storing another growing history. Apply the room filter before grouping. Prefer verified album identity; when only display metadata is available, group conservatively and treat the result as provisional. Do not use artwork alone as identity or merge different known editions. Retain tracks with missing album data in Tracks, omitting them from Albums until identified. Metadata enrichment may combine provisional album groups later.

**5. Make reopening and replay reliable**

Reuse the existing isolated, read-only music browsing approach in [cinema-music.ts](/Users/david/Development/Projects/roon-web-stack/app/roon-web-api/src/service/cinema-music.ts:45). Extract shared resolution helpers where useful rather than making history depend on Cinema UI or generation.

- Save metadata and optional verified resolution information, never a raw browse key as a durable ID.
- Resolve on user selection, with bounded work, timeouts and an isolated browse session. Do not scan the library or resolve every history row during recording or list loading.
- When an exact recording or album can be established, obtain fresh session keys and hand off to the existing browse/playback flow.
- When several editions or recordings match, present a choice. When no match is available, preserve the historical row and explain that the music cannot currently be found.
- Never play the first title-only match automatically. Only an explicit playback action may change music or the queue.
- Treat expired artwork and removed streaming/library items as expected cases. History remains readable even when it can no longer be replayed.

The [Roon Browse API](https://roonlabs.github.io/node-roon-api/RoonApiBrowse.html) maintains server-side browsing sessions; the [Item contract](https://roonlabs.github.io/node-roon-api/Item.html) provides navigable keys without promising permanent recording identifiers. Exact resolution remains a feasibility item for metadata-only events.

**6. Integrate the native clients**

Add shared history response models, a small observable history store and client methods alongside [RoonAPIClient.swift](/Users/david/Development/Projects/roon-ios/RoonRemote/API/RoonAPIClient.swift:3). Keep history state separate from the main playback store and ordinary browse navigation.

Implement the destination in [LibraryViews.swift](/Users/david/Development/Projects/roon-ios/RoonRemote/LibraryViews.swift:4), the regular-width sidebar/detail shell and [TVLibraryView.swift](/Users/david/Development/Projects/roon-ios/RoonRemoteTV/TVLibraryView.swift:3). Share loading, pagination, room filtering and error handling; adapt the visual presentation and focus controls for each device.

Check history capabilities once per bridge connection. A missing endpoint means an update is required; authentication and connection failures retain their own error states. Existing older clients should continue working with an upgraded bridge.

Refresh on opening the screen and returning to the foreground. While visible, poll at most every 30 seconds and provide manual refresh; stop polling when hidden or backgrounded. Keep the existing list and scroll position during refresh. Ignore responses belonging to an earlier filter or bridge connection. Expire native rows locally as time advances, without keeping a second permanent history database.

Reuse [ArtworkCache.swift](/Users/david/Development/Projects/roon-ios/Shared/ArtworkCache.swift:10), fetching visible thumbnails rather than full-size art for every row. Add deterministic demo data for the normal, empty, disconnected, unsupported-bridge and ambiguous-resolution states. Check VoiceOver labels, Dynamic Type, iPad width changes, and predictable TV focus after paging or refresh.

**7. Deliver and verify in order**

1. **Event feasibility and contract:** collect representative event fixtures, settle session-continuity rules, validate metadata-only resolution and agree the response models. Record the remaining API limitations.
2. **Bridge recorder and retention:** implement the recorder, bounded atomic store, idle cleanup and paired-client history endpoints. Verify independently of native clients.
3. **Browsing and replay:** implement isolated resolution and explicit playback handoff, including ambiguous and unavailable results.
4. **Native experience:** add Recently played on iPhone, iPad and TV, capabilities handling, pagination, filters and demo states.
5. **End-to-end verification and release preparation:** run targeted bridge/native tests, existing relevant checks and simulator flows. Prepare matching bridge and native builds and update the user documentation. Deployment and device installation are separate from this planning task.

Required acceptance checks:

- Play through the official Roon app while House Remote is closed; a qualifying event subsequently appears on all three native platforms.
- A brief skip does not qualify; a normal play does. Pause/resume, seeking and duplicate transport messages do not create extra entries. Confirmed repeated plays remain separate.
- Reconnect and restart preserve committed history without duplicating a known continuing session. Offline time is never credited as observed listening.
- Grouped rooms yield one event, independent rooms retain separate events, and proven transfers preserve continuity. Record any unavoidable ambiguity.
- Advance a fake clock beyond 14 days without new playback: API results expire immediately and idle cleanup removes stored entries. Insert more than 10,000 events and oversized metadata: event, byte and ancillary-file limits remain enforced.
- Simulate interrupted writes, unreadable storage and disk failures: the previous committed snapshot survives where possible, errors are visible, and playback remains responsive.
- Apply room filters, paginate while new plays arrive and expire rows mid-session: no duplicated pages or incorrect album ordering. Different known album editions stay separate.
- Resolve an old row after browse sessions expire, with removed music and with multiple matching editions. Opening history and resolving rows send no playback commands; explicit replay uses the selected room.
- Verify old-bridge messaging, malformed/unauthorized API requests, device reconnection, accessibility and TV focus.

Success means useful shared recent listening with predictable storage limits, honest coverage and reliable explicit replay. Adjustable retention, statistics, exports, per-person history and Watch browsing can be considered after this initial release.

Original planning note: this plan was grounded in the current native and companion bridge source and the Roon API references reviewed in this chat. No code was implemented, live playback controlled, deployment performed or runtime behaviour verified while writing it.
