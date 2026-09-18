# Cinema / Time Capsules

Implemented locally on 17 September 2026 in this app and the companion `roon-web-stack` repository. Runtime deployment is separate from the tagged source release.

## Adaptive Cinema setup (18 September 2026)

**Set up Cinema** opens a native setup sheet before any research. It snapshots the original
search and selected tracks, suggests **Around this time**, **About the artist**, or
**About the work**, and allows an override. **My photos** is always available on iOS.
The visual subject can be edited without changing the soundtrack or original time anchor.
**More topics** allows combinations beyond the suggested set, such as headlines with artist photographs.
**Album covers** is a separate option and uses only cover images available under the bridge's reusable-image licence gate.

- Period: headlines, sports, TV/film/culture and everyday life; country perspective and optional exact dates.
- Artist: photographs, career, collaborators, places and optional wider historical context.
- Work: composer, programme notes, artwork, manuscripts/scores, places, performers and optional history;
  explicit composition-versus-recording focus. No automatic use of a recording year as the work's era.
- Personal: the system Photos picker or a PhotoKit album chooser. Album browsing needs full Photos access;
  limited/denied access retains individual selection. Up to 200 images are copied to app storage, resized
  to 2560 pixels, with no location metadata. Albums are snapshots, not live subscriptions.

All modes support still, gentle zoom or Ken Burns pan/zoom and a 5-, 8- or 16-second hold.
Captions can be hidden, brief or detailed (personal photos offer hidden or date captions).
Ordering is selected/curated, chronological or shuffled at creation; saved replay preserves it.
Topic and presentation preferences are remembered per mode on this device. Subjects and date ranges are not.

The bridge's authenticated **GET `/capabilities`** must return `{optionsVersion:2}` before a configured
request is submitted. Older bridges get an actionable update message rather than silently ignoring options.
The optional request `options` object includes `mode`, `topics`, `subject`, `region`, optional
`periodStart`/`periodEnd`, `workContext`, `captions`, `motion`, `pace` and `order`.
These values participate in cache identity and survive saved replay/rebuild. Requests without options remain compatible.

Artist setup derives its canonical subject from the selected tracks, so “Bowie greatest hits” researches
David Bowie rather than the search wording. Work setup combines the selected artist/composer and parent
work title, collapsing concerto or symphony movements where their metadata permits it.

Configured research only commissions selected topics, audits sources and dates, and filters unselected topic IDs.
It does not impose the legacy news/sport/culture quota. At least three distinct accepted images are required;
missing topics are reported in the saved library while available material can play. Work imagery can include
genuine artwork and manuscripts; no synthetic archive imagery is generated. Caption-free viewing retains credits.

Personal montages bypass the bridge and AI entirely, save in Application Support/PersonalCinema, and merge
into the on-device Cinema library. They support a single photo, offline picture playback and normal Roon music
controls, but are not associated with shared rooms or sent to Apple TV. Photo downloads may require iCloud
connectivity during import. Partial imports are cleaned up after errors/cancellation.

The earlier behavior below describes capsules created without setup options, except for the renamed entry point.

## Request-driven content

**Create Time Capsule** uses the successful AI Search's original text, submission timestamp, locale, time zone and current playable result list. Editing the query invalidates its old context. A capsule snapshots the selected tracks and retains the original time anchor: “this week” does not change when replayed later.

The bridge researches the supplied subject. A chart-week request produces dated historical context; an artist, genre or mood request produces relevant music and cultural context without assigning an arbitrary historical year. There is no fixed year, week, country, artist list or historical content pack in the app. The selected design mockup is illustrative and is not shipped as archive content.

## Saved Cinema playlists (18 September 2026)

Cinema opens the saved playlist library on iPhone, iPad and Apple TV. Playlists belong to
House Remote and its bridge; they do not depend on Roon playlist support. Each item holds
a soundtrack, visual options and saved photographs.

1. Use **Set up Cinema** from AI Search to create an item from the selected tracks.
2. Open **Cinema** on Now Playing to browse all saved items. iPhone expands actions beneath
   the selected row. iPad and TV show the library beside a preview and actions.
3. **Play music & pictures** sends the saved tracks to the selected Roon room and opens the
   pictures. **Watch pictures** opens only the visuals and leaves the room's music and queue
   untouched. The room selector makes the audio destination explicit.
4. **Edit** restores that item's saved options. Change visual context, topics or presentation,
   then choose **Save & regenerate**. The saved ID and soundtrack stay the same; the bridge
   replaces the manifest atomically only when generation succeeds. Existing pictures remain
   available on failure, with a retry action. Personal-photo edits reuse the imported copies.
5. While updating, the library keeps the item visible. Playing or watching it opens a fitted
   current album cover when available, otherwise a saved picture, plus progress and music
   controls. The viewer changes to the finished montage automatically. Music need not wait
   for new pictures; a soundtrack already playing is not restarted by the preparation action.
6. **Delete** asks for confirmation, then removes the saved Cinema item. Shared deletion
   clears its room associations and research draft, retaining image files that other items
   may use. Personal deletion removes this app's imported copies. Original music and Photos
   library assets are unaffected. An item cannot be deleted while it is regenerating.

All devices paired to a bridge share the saved library; refresh discovers changes made on
another device. To watch on TV while music plays elsewhere, select the same Roon room and
use **Watch pictures**. TV has its own remote focus controls and editor. Personal photos
remain on their source device.

Photographs have an independent clock. Music previous/play/pause/next control the selected
Roon room; photograph previous/hold/next control the visuals. Closing Cinema leaves music
playing. Dismissing the library does not cancel a bridge generation job.

## Bridge setup

The companion implementation is in `app/roon-web-api/src/ai-service/time-capsule.ts` and `src/route/time-capsule-route.ts` in `roon-web-stack`. Build and release that API alongside this app.

| Setting | Behaviour |
| --- | --- |
| Settings API key / `OPENAI_API_KEY` | Uses the key saved on the bridge config volume; environment variable is the operator fallback |
| `TIME_CAPSULE_MODEL` | Defaults to `gpt-4.1`; selected model must support Responses web search, image input and JSON output |
| `TIME_CAPSULE_CACHE_DIR` | Defaults to `cache/time-capsules` relative to the API process; mount persistent storage here in Docker |

The bridge needs outbound access to OpenAI and Wikimedia Commons. Cached programmes and downloaded images can replay without fresh internet research. Keep the bridge available on the LAN. Do not expose this LAN service publicly as part of this feature.

## Content preparation

For a generic dated chart search, the bridge first resolves and validates its calendar interval. Only the resolved dates and home-country perspective reach the news researchers and fact-checker: the original chart-search wording is not their assignment. Independent searches cover news/politics/economy, sport, and television/culture/everyday life. A named subject, artist, place or theme is instead preserved through research, audit and compilation, including when it has dates. Such capsules follow their subject's actual geography and have no home-country or mandatory news/sport/culture quota. For dated requests a separate web-backed source audit checks the draft before compilation. The tracks supply the soundtrack and are excluded from research and image-selection inputs. Rebuilds retain the saved date range. Each headline has retrieved source URLs and event dates inside that window. Model-extracted claims and dates can still be wrong; source links are available for inspection.

Commons searches target each story's named subjects. A web-backed subject lookup identifies period-appropriate presenters, cast members, politicians and sportspeople with retrieved source URLs. Searches include these names directly; full archive descriptions are preserved for identity matching, including surname-first catalogue entries. Candidates require an allowed licence, credit, source page, an original width of at least 500 pixels, and an approved HTTPS Wikimedia host. Relevant illustrative photographs may come from twenty years before through ten years after the requested period's end year, preferring the closest dates. Their actual archive date remains visible; later pictures are explicitly labelled as illustrative. Story dates remain inside the original requested window. A known out-of-range photographic date cannot be overridden by a historical date in its description.

Event-specific archive queries are scheduled across all scenes before generic subject/portrait fallbacks consume the bounded search budget. Searches use each story's event year rather than only the end year of a multi-year capsule, and can use local-language event names.

Images are associated with headlines by explicit IDs. The selector rejects unrelated subjects, commemorations, misleading different events, materially changed places, wrong team affiliations and alternate crops of the same photograph. The bridge deduplicates file references and caches successful downloads. A separate AI review inspects the actual images for obvious blur, pixelation and subject relevance before including them; it is a best-effort check, not a guarantee of archival quality. If a thumbnail fails, it tries the approved original image, with the same timeout and size limits.

For a single-artist montage, artist-picture scenes use the available archive photograph's own date and attribution. They do not claim to depict an unrelated named studio session. Each accepted portrait gets its own scene after the normal subject, licence and quality checks. Repeated archive queries within a build share their results.

Simple galleries for a fully named artist, with only artist pictures, career photos and album covers selected, fetch archive images directly. Career captions use the actual photo description and date. These requests do not wait for biography research or AI search planning; candidates still undergo licence, subject and pixel checks. Rebuilding prefers unused archive sources. Date ranges, additional subject context, ambiguous short names and wider contextual topics use the researched workflow. This speed improvement is entirely on the bridge and requires no new native protocol.

Each scene can contain several photographs. Only available photos enter the montage: no text-only slides, repeated context backdrop, blurred album artwork or synthetic archive pictures. Explicitly dated requests require at least six distinct downloaded photos; other requests require three. All require at least three illustrated stories. Only generic dated chart montages additionally require illustrated non-music stories across three topics, including at least three domestic stories. Subject-focused history does not inherit those quotas. Insufficient content fails preparation rather than replacing an existing capsule. Archive coverage remains a constraint. The saved library shows its actual photo count before playback. Research drafts are versioned so retries cannot reuse drafts produced under obsolete subject-selection rules.

The first version uses Commons, not a licensed newspaper archive. It can use eligible scans discovered there, but does not promise automatic access to specific newspaper editions.

## API contract

All paths begin `/api/:client_id/time-capsules`; the existing registered-client check protects every route.

| Method / suffix | Result |
| --- | --- |
| GET `/` | Up to 50 saved manifests, newest first |
| GET `/capabilities` | `{optionsVersion:2, managementVersion:1}` |
| POST `/` | Request snapshot → 202 preparation job, or 200 cached result |
| GET `/jobs/:id?generation=…` | Status for this build; interrupted/superseded builds fail instead of returning an old manifest |
| POST `/artwork` | `{zoneId,tracks}` → `{imageKey}` for a playlist album, using an isolated browse session |
| GET `/:id` | Saved manifest |
| POST `/:id/rebuild` | Rebuild from the saved request; preserve its ID and room association |
| PUT `/:id` | `{options}` → 202 job; preserve ID and soundtrack; 409 if already updating |
| DELETE `/:id` | 204, idempotent; remove manifest/draft/associations; 409 if updating |
| GET `/images/:hash` | Cached JPEG, PNG or WebP |
| GET `/zone/:zoneId` | Associated manifest, or 204 |
| PUT `/zone/:zoneId` | `{capsuleId}` associates a saved manifest; 204 |

Request: `{query, requestedAt, locale, timeZone, tracks:[{artist,track,album}]}`. IDs hash this snapshot plus a format version. Manifests and zone associations use atomic file writes; image paths accept only hashes. Two concurrent generation jobs are allowed. Research calls and media downloads have time and size bounds. Jobs run on the bridge. A persisted generation marker distinguishes an interrupted job from a previously saved montage. Finished manifests carry the completed generation and a fresh timestamp; active work cannot resume after restart and reports a retryable failure.

The UI polls using a dedicated Cinema HTTP session. Its 15-minute watchdog measures time without reported progress, rather than total generation time; a build progressing through research and pictures stays connected. Transient status-request timeouts, network drops and 408/502/503/504 responses reconnect to the same generation rather than fail the montage or submit it again. Bridge messages describe the current research or image stage. If it loses the connection or the app closes, the server can still finish; refresh the saved library later. Verified research is checkpointed separately from saved montages so an image-stage retry with the same request can reuse it. Drafts are not shown as finished capsules and are removed after successful publication. There is no job cancellation or automatic retention policy. Edit and delete require `managementVersion >= 1`; older bridges show an update message before either operation is attempted.

## Playback and limits

The viewer has an independent eight-second photo clock. Music playback, pauses, song changes and seeks do not restart or hold it. The sources sheet and the hold button stop it while they apply; manual navigation gives the chosen photograph a full hold. A new image gets its full hold after loading; failed images are skipped and the next photograph is preloaded. Images fit the screen without an artificial blur effect, with a subtle zoom and dissolve. Reduce Motion disables both. Source photographs can still vary in sharpness despite automated review.

Watching a saved item on another device does not restart its soundtrack. Screens share the content and room’s music state but do not have frame-exact synchronisation: each starts its own montage clock. Music remains entirely in the selected Roon zone; this does not make Apple TV a Roon audio endpoint. In-progress preparation is tracked by the app that started it; other clients can discover the saved result after completion.

Native iPhone, iPad and tvOS viewers, content preferences and optional exact date ranges are included. AirPlay video rendering, remote TV wake/launch, exported movies, licensed newspaper providers and personal-photo sharing to Apple TV are not included.

## Verification

The native playback tests cover eight-second progression, pause/resume, manual navigation, arbitrary request preservation and deduplication. Bridge tests cover date boundaries, photo chronology, explicit photo/headline IDs, rebuild failure preserving existing content, cached replay and paired route access. The viewer is checked with externally generated archive content rather than bundled historical examples.

iPhone/iPad and tvOS simulators are available locally. See [Cinema implementation validation](design/cinema-playlists-validation.md) for the current checks. Physical remote behavior and live multi-device Roon playback still need device validation. The local `yarn dev` bridge automatically reloads source changes; installed native apps still need rebuilding/reinstalling.

For local renderer checks, a Debug build accepts `ROON_CINEMA_PREVIEW_MANIFEST` pointing to an external JSON manifest with `-roon-demo-store`. The input can be one manifest or an array; `ROON_CINEMA_PREVIEW_JSON` also accepts inline JSON. Optional `ROON_CINEMA_PREVIEW_ASSETS` points to a local server serving `<hash>.image` files. `ROON_CINEMA_PREVIEW_LIBRARY=1` opens the library with an isolated in-memory client for edit/delete/play testing. `ROON_CINEMA_PREVIEW_DELAY` controls mocked generation time and `ROON_CINEMA_PREVIEW_FAIL=1` exercises failure recovery. `ROON_CINEMA_PREVIEW_PREPARING=1` opens the library during a deterministic 45-second preparation followed by that manifest, isolating incoming room events for this preview. These are developer inputs, not bundled historical fixtures.

Album artwork is prefetched during setup without altering playback or the main Roon browse session. While waiting, the player can immediately display the loaded room cover even when its song is outside the playlist, then replace it with a playlist cover. Debug artwork tests use `ROON_CINEMA_PREVIEW_NEW=1`, a PNG encoded in `ROON_CINEMA_PREVIEW_COVER`, and `ROON_CINEMA_PREVIEW_COVER_SOURCE=current` or `playlist`.

Web-research calls have a 300-second budget from the first attempt; structured-output calls use 150 seconds. Both allow one 300-second retry for a timeout, connection failure or transient service error. Completed web research is checkpointed per exact request and reused by Retry picture update. Structured model output is not cached before validation; validated research drafts retain their existing checkpoint. Successful publication and deletion clean up step checkpoints. Failed jobs persist their stage and error across bridge restarts.
