# Cinema / Time Capsules

Implemented locally on 17 September 2026 in this app and the companion `roon-web-stack` repository. Runtime deployment is separate from the tagged source release.

## Request-driven content

**Create Time Capsule** uses the successful AI Search's original text, submission timestamp, locale, time zone and current playable result list. Editing the query invalidates its old context. A capsule snapshots the selected tracks and retains the original time anchor: “this week” does not change when replayed later.

The bridge researches the supplied subject. A chart-week request produces dated historical context; an artist, genre or mood request produces relevant music and cultural context without assigning an arbitrary historical year. There is no fixed year, week, country, artist list or historical content pack in the app. The selected design mockup is illustrative and is not shipped as archive content.

## Use

1. Run an AI Search and remove unwanted results as usual.
2. Choose **Create Time Capsule**. Research continues on the bridge while music remains available. During preparation, **Play now** opens a preparation player with previous track, play/pause and next track controls. It starts the requested tracks unless they already match the room's current music and queue; an already playing playlist is not restarted. The viewer automatically switches to photographs when preparation succeeds. A failure remains visible without replacing it with an older montage.
3. **Cinema** on Now Playing returns to an active preparation first. Otherwise it selects a saved capsule matching the current music, using upcoming tracks to distinguish playlists sharing a song. A room's old association is not enough. This does not restart music or change the queue. It resumes the last photograph and remaining hold time on this device while the app remains open. A rebuilt capsule starts fresh. If no capsule matches, Cinema opens the saved library. The stack icon in the viewer also opens that library.
   In the library, **Play music & montage** immediately opens the pictures, sends the saved selection to the selected Roon room and associates the capsule with that room. Loading or unavailable-track messages appear in the montage. **Watch pictures** opens the visuals without changing the music.
4. On another paired device, select the same Roon room, open Cinema and choose **Join [room]**. This joins without restarting music. The phone need not remain open for the native Apple TV app to follow Roon.
5. Photographs change every eight seconds, including while music is paused. The viewer's previous track, play/pause and next track buttons control the selected Roon room. There are no manual picture controls. The information button holds the photo while showing its sources. Closing Cinema leaves music playing.
6. Choose **Rebuild montage** to replace an older capsule’s visuals using the same original search, dates and tracks. The existing capsule remains available if rebuilding fails.

All clients connected to the same bridge share its saved library. The bridge retains the most recent capsule association for each room. Choosing another programme with **Watch pictures** does not replace that shared association. **Done** dismisses the library without cancelling preparation on the bridge.

## Bridge setup

The companion implementation is in `app/roon-web-api/src/ai-service/time-capsule.ts` and `src/route/time-capsule-route.ts` in `roon-web-stack`. Build and release that API alongside this app.

| Setting | Behaviour |
| --- | --- |
| Settings API key / `OPENAI_API_KEY` | Uses the key saved on the bridge config volume; environment variable is the operator fallback |
| `TIME_CAPSULE_MODEL` | Defaults to `gpt-4.1`; selected model must support Responses web search, image input and JSON output |
| `TIME_CAPSULE_CACHE_DIR` | Defaults to `cache/time-capsules` relative to the API process; mount persistent storage here in Docker |

The bridge needs outbound access to OpenAI and Wikimedia Commons. Cached programmes and downloaded images can replay without fresh internet research. Keep the bridge available on the LAN. Do not expose this LAN service publicly as part of this feature.

## Content preparation

For a dated music search, the bridge first resolves and validates its calendar interval. Only the resolved dates and home-country perspective reach the news researchers and fact-checker: the original chart-search wording is not their assignment. Independent searches cover news/politics/economy, sport, and television/culture/everyday life. A separate web-backed source audit checks the draft before compilation. The tracks supply the soundtrack and are excluded from research and image-selection inputs. Rebuilds retain the saved date range. Each headline has retrieved source URLs and event dates inside that window. Model-extracted claims and dates can still be wrong; source links are available for inspection.

Commons searches target each story's named subjects. A web-backed subject lookup identifies period-appropriate presenters, cast members, politicians and sportspeople with retrieved source URLs. Searches include these names directly; full archive descriptions are preserved for identity matching, including surname-first catalogue entries. Candidates require an allowed licence, credit, source page, an original width of at least 500 pixels, and an approved HTTPS Wikimedia host. Relevant illustrative photographs may come from twenty years before through ten years after the requested period's end year, preferring the closest dates. Their actual archive date remains visible; later pictures are explicitly labelled as illustrative. Story dates remain inside the original requested window. A known out-of-range photographic date cannot be overridden by a historical date in its description.

Images are associated with headlines by explicit IDs. The selector rejects unrelated subjects, commemorations, misleading different events, materially changed places, wrong team affiliations and alternate crops of the same photograph. The bridge deduplicates file references and caches successful downloads. A separate AI review inspects the actual images for obvious blur, pixelation and subject relevance before including them; it is a best-effort check, not a guarantee of archival quality. If a thumbnail fails, it tries the approved original image, with the same timeout and size limits.

Each scene can contain several photographs. Only available photos enter the montage: no text-only slides, repeated context backdrop, blurred album artwork or synthetic archive pictures. Dated montages require at least six distinct downloaded photos and illustrated non-music stories across three topics, including at least three domestic stories. Non-dated requests require three photos. Insufficient content fails preparation rather than replacing an existing capsule. Archive coverage remains a constraint. The saved library shows its actual photo count before playback.

The first version uses Commons, not a licensed newspaper archive. It can use eligible scans discovered there, but does not promise automatic access to specific newspaper editions.

## API contract

All paths begin `/api/:client_id/time-capsules`; the existing registered-client check protects every route.

| Method / suffix | Result |
| --- | --- |
| GET `/` | Up to 50 saved manifests, newest first |
| POST `/` | Request snapshot → 202 preparation job, or 200 cached result |
| GET `/jobs/:id` | `researching`, `images`, `ready` or `failed` |
| GET `/:id` | Saved manifest |
| POST `/:id/rebuild` | Rebuild from the saved request; preserve its ID and room association |
| GET `/images/:hash` | Cached JPEG, PNG or WebP |
| GET `/zone/:zoneId` | Associated manifest, or 204 |
| PUT `/zone/:zoneId` | `{capsuleId}` associates a saved manifest; 204 |

Request: `{query, requestedAt, locale, timeZone, tracks:[{artist,track,album}]}`. IDs hash this snapshot plus a format version. Manifests and zone associations use atomic file writes; image paths accept only hashes. Two concurrent generation jobs are allowed. Research calls and media downloads have time and size bounds. Jobs run on the bridge; completed manifests survive restart, in-progress jobs do not.

The UI polls for up to 15 minutes. If it loses the connection or the app closes, the server can still finish; refresh the saved library later. Verified research is checkpointed separately from saved montages so an image-stage retry with the same request can reuse it. Drafts are not shown as finished capsules and are removed after successful publication. There is no job cancellation, deletion UI or automatic retention policy in this version.

## Playback and limits

The viewer has an independent eight-second photo clock. Music playback, pauses, song changes and seeks do not restart or hold it. The sources sheet holds it while open. A new image gets its full hold after loading; failed images are skipped and the next photograph is preloaded. Images fit the screen without an artificial blur effect, with a subtle zoom and dissolve. Reduce Motion disables both. Source photographs can still vary in sharpness despite automated review.

Joining a room selects a montage matching its current music without restarting it. Screens share the content and room’s music state but do not have frame-exact synchronisation: each starts its own montage clock. Music remains entirely in the selected Roon zone; this does not make Apple TV a Roon audio endpoint. In-progress preparation is tracked by the app that started it; other clients can discover the saved result after completion.

Native iPhone, iPad and tvOS viewers are included. AirPlay video rendering, remote TV wake/launch, exported movies, licensed newspaper providers, a chart-date editor and content preferences are not included.

## Verification

The native playback tests cover eight-second progression, pause/resume, manual navigation, arbitrary request preservation and deduplication. Bridge tests cover date boundaries, photo chronology, explicit photo/headline IDs, rebuild failure preserving existing content, cached replay and paired route access. The viewer is checked with externally generated archive content rather than bundled historical examples.

iPhone/iPad simulator checks and tvOS SDK type checking are available locally. A tvOS simulator runtime is not installed, so real remote focus, multi-device Roon playback and Apple TV presentation need device validation. Source release does not deploy the running bridge or update installed apps.

For local renderer checks, a Debug build accepts `ROON_CINEMA_PREVIEW_MANIFEST` pointing to an external JSON manifest with `-roon-demo-store`. Optional `ROON_CINEMA_PREVIEW_ASSETS` points to a local server serving `<hash>.image` files. `ROON_CINEMA_PREVIEW_PREPARING=1` presents a deterministic 45-second preparation followed by that manifest, isolating incoming room events for this preview. These are developer inputs, not bundled historical fixtures.
