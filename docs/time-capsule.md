# Cinema / Time Capsules

Implemented locally on 17 September 2026 in this app and the companion `roon-web-stack` repository. Runtime deployment is separate from the tagged source release.

## Request-driven content

**Create Time Capsule** uses the successful AI Search's original text, submission timestamp, locale, time zone and current playable result list. Editing the query invalidates its old context. A capsule snapshots the selected tracks and retains the original time anchor: “this week” does not change when replayed later.

The bridge researches the supplied subject. A chart-week request produces dated historical context; an artist, genre or mood request produces relevant music and cultural context without assigning an arbitrary historical year. There is no fixed year, week, country, artist list or historical content pack in the app. The selected design mockup is illustrative and is not shipped as archive content.

## Use

1. Run an AI Search and remove unwanted results as usual.
2. Choose **Create Time Capsule**. Research continues on the bridge while music remains available.
3. Open **Cinema** on Now Playing to see saved programmes. **Play with Cinema** sends the saved selection to the selected Roon room and associates the capsule with that room. **Watch** opens only the visuals.
4. On another paired device, select the same Roon room, open Cinema and choose **Join [room]**. This joins without restarting music. The phone need not remain open for the native Apple TV app to follow Roon.
5. Previous/next story and **Explore this story** browse locally. **Return to live** follows the current song and position again. Closing Cinema leaves music playing.

All clients connected to the same bridge share its saved library. The bridge retains the most recent capsule association for each room. Choosing another programme with **Watch** does not replace that shared association.

## Bridge setup

The companion implementation is in `app/roon-web-api/src/ai-service/time-capsule.ts` and `src/route/time-capsule-route.ts` in `roon-web-stack`. Build and release that API alongside this app.

| Setting | Behaviour |
| --- | --- |
| Settings API key / `OPENAI_API_KEY` | Uses the key saved on the bridge config volume; environment variable is the operator fallback |
| `TIME_CAPSULE_MODEL` | Defaults to `gpt-4.1`; selected model must support Responses web search and JSON output |
| `TIME_CAPSULE_CACHE_DIR` | Defaults to `cache/time-capsules` relative to the API process; mount persistent storage here in Docker |

The bridge needs outbound access to OpenAI and Wikimedia Commons. Cached programmes and downloaded images can replay without fresh internet research. Keep the bridge available on the LAN. Do not expose this LAN service publicly as part of this feature.

## Content preparation

The pipeline uses web search for research, then compiles short original summaries referencing URLs present in the research tool's output. It resolves requested date boundaries, excludes extracted later events, and labels dated earlier material as earlier context. Model-extracted dates and claim relevance can still be wrong; source links are available for inspection.

Commons image searches are generated from the actual programme. Candidate metadata must include an allowed licence, credit, source page, sufficient resolution and an approved Wikimedia download host. Photo dates come from original-date metadata, not upload dates. AI selects suitable scene subjects and a separate contextual photograph. Failed image retrieval leaves the sourced text programme usable. No newspaper scans or historical photographs are synthesised.

The app labels the shared contextual photograph, preserves credits and licences, and exposes its original caption and source. When no archive image is available, it uses blurred current artwork or a dark background. Image coverage depends on the archive; a programme may have few or no photographs.

The first version uses Commons, not a licensed newspaper archive. It can use eligible scans discovered there, but does not promise automatic access to specific newspaper editions.

## API contract

All paths begin `/api/:client_id/time-capsules`; the existing registered-client check protects every route.

| Method / suffix | Result |
| --- | --- |
| GET `/` | Up to 50 saved manifests, newest first |
| POST `/` | Request snapshot → 202 preparation job, or 200 cached result |
| GET `/jobs/:id` | `researching`, `images`, `ready` or `failed` |
| GET `/:id` | Saved manifest |
| GET `/images/:hash` | Cached JPEG, PNG or WebP |
| GET `/zone/:zoneId` | Associated manifest, or 204 |
| PUT `/zone/:zoneId` | `{capsuleId}` associates a saved manifest; 204 |

Request: `{query, requestedAt, locale, timeZone, tracks:[{artist,track,album}]}`. IDs hash this snapshot plus a format version. Manifests and zone associations use atomic file writes; image paths accept only hashes. Two concurrent generation jobs are allowed. Research calls and media downloads have time and size bounds. Jobs run on the bridge; completed manifests survive restart, in-progress jobs do not.

The UI polls for up to 15 minutes. If it loses the connection or the app closes, the server can still finish; refresh the saved library later. There is no job cancellation, deletion UI, regeneration UI or retention policy in this version.

## Playback and limits

The viewer uses Roon's existing current-track and seek events to choose a scene every 30 seconds. Clients calculate the same scene for the same capsule, song and position. Music remains entirely in the selected Roon zone; this does not make Apple TV a Roon audio endpoint.

Matching uses normalized artist/title and album disambiguation. Ambiguous duplicate recordings and unrelated music disable automatic following; users can still browse. It does not yet use queue-item IDs, preserve verified chart rank metadata or broadcast shared story-browsing commands. A different room association is picked up when a receiver chooses Join again.

Native iPhone, iPad and tvOS viewers are included. AirPlay video rendering, remote TV wake/launch, exported movies, licensed newspaper providers, a chart-date editor and content preferences are not included.

## Verification

- iOS simulator build succeeds; four Time Capsule model tests pass (arbitrary request, frozen date, seek mapping, ambiguity and invalid timecodes). The isolated release checkout’s 144 existing tests also pass.
- Nine bridge tests pass, covering request identity, source restrictions, image metadata, date boundaries, cached replay, room persistence, client checks and asynchronous route responses. TypeScript and ESLint pass for the new implementation.
- A live request for a different subject, “David Bowie in Berlin in 1977,” generated a 12-story programme with real source links and an attributed period context photograph. This manifest predates the final stricter date-boundary and scene-image selection rules, which are covered by code checks and date tests, not a second live generation.
- iPhone simulator: source sheet, next-story browsing, control reveal and image rendering checked. iPad rendering checked. Portrait captions can scroll; larger screens use the immersive composition.
- tvOS sources pass SDK type checking. A tvOS simulator runtime is not installed, so remote focus, late joining and real multi-device Roon playback still require device validation before release.

For local renderer checks, a Debug build accepts `ROON_CINEMA_PREVIEW_MANIFEST` pointing to an external JSON manifest with `-roon-demo-store`. Optional `ROON_CINEMA_PREVIEW_ASSETS` points to a local server serving `<hash>.image` files. These are developer inputs, not bundled historical fixtures.
