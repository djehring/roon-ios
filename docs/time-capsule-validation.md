# Cinema montage revision — validation

## Adaptive setup (18 September 2026)

- Full iOS logic suite: 158 tests passed, including legacy capsule decoding, request/option round trips,
  per-mode preferences without stale dates/subjects, chosen photo pacing, and personal image storage/reload/order/cleanup.
- Native iPhone and iPad interface tests exercise period/artist/work/photo mode changes, Beethoven's relaxed
  default, Photos/album entry points and the disabled empty-selection action. The iPhone regression also checks
  selecting artist photographs through More topics. Screenshots were exported and visually inspected.
- Bridge: 60 tests passed across request validation, capabilities/paired access, cache identity, saved rebuilds,
  archive handling and the new period/Django/Beethoven research handoffs. TypeScript checking passes.
- iOS and tvOS simulator builds pass. The options schema also passes its focused ESLint check.
- Research handoff tests use mocked source responses and stop before paid image generation. A live production
  capsule and physical-device Photos permissions/iCloud album downloads have not been exercised for this change.
  Source changes are local and have not been deployed to the running bridge or installed on physical devices.

Screenshots: [iPhone](design/assets/cinema-setup-iphone.png),
[Beethoven](design/assets/cinema-setup-beethoven.png),
[personal photos](design/assets/cinema-setup-photos.png),
[iPad](design/assets/cinema-setup-ipad.png).

## Paris Subject Failure (17 September 2026)

- The phone's `Top django Reinhardt hits 1939 to 1945` request lost its named subject after date resolution. It researched Britain and then failed a domestic/topic quota despite 21 photographs passing visual review. This was an intent-handling bug, not evidence that Paris lacked wartime photographs.
- Subject-focused requests now retain their artist/place/theme through research, audit and compilation, without the generic chart montage's home-country or topic quotas. Versioned drafts prevent reuse of old off-topic research. Date, source, licence, minimum-photo and visual-review requirements remain.
- A new request clarified the user's desired Paris/World War II context while preserving the original tracks and timestamp. Two image passes still failed (five and three accepted photos). Diagnostics showed generic subject searches exhausting the query budget and useful archive results below the first 20 entries. Targeted searches now get priority across all stories, use event years, and retrieve up to 50 results per query.
- The final live run completed as **Paris in World War II and Django Reinhardt, 1939–1945**, with six accepted photos across six illustrated scenes. It searched 72 queries, retained 73 candidates, and accepted six of 12 reviewed images. This is a short montage, not complete illustration of the 25 researched scenes.
- Visually inspected all six saved image files, including the occupation parade, Django portrait and liberation photographs. They show recognizable subjects with period grain/print wear. Simulator verification was blocked by the locked Mac; no claim of fresh simulator or Apple TV playback verification is made.
- All 377 bridge tests across 32 suites and the production build passed. The rebuilt bridge is deployed; no native code or iPhone installation was changed.

## Main Integration (17 September 2026)

- Integrated upstream iOS `895ae21` and bridge `6f32429` (shared bridge track matching and requested-artist verification) before committing the Time Capsule updates. No merge conflicts.
- The combined bridge passed 364 tests across 32 suites and its production build. The combined iOS simulator build/test run passed 151 tests across 19 suites.
- Restarted the rebuilt bridge and restored the existing phone/simulator registrations. The saved nine-photo October 1978 capsule remained available; library and cached-photo requests returned HTTP 200. No new iPhone installation or Apple TV hardware check was performed for this integration.

## Wider-Date Illustrations (17 September 2026)

- With the user's agreement, illustrative photographs may now date from 20 years before through 10 years after the story's year. Story dates remain within the requested week. Later photographs retain their real date and display `(later illustrative photo)`; subject, licence and visual-quality checks remain in place.
- All 336 bridge tests across 31 suites passed, the production build passed, and the deployed bridge was verified listening on port 3000. Known modern photographic dates cannot be backdated using historical dates from descriptions.
- The live retry of the saved 1-7 October 1978 research completed successfully as **Great Britain week in pictures**, with nine accepted photographs across eight illustrated stories covering politics, television and sport. The 72-query search collected 58 candidates, selected 12 for visual review and retained nine. This is an improvement, not comprehensive coverage of the week; sport still dominates the illustrated stories.
- Opened the new saved capsule using **Watch pictures** in the paired iPhone 17 simulator. Observed a clear James Callaghan portrait, then an automatic change to Penelope Keith without user input while music remained paused. The Good Life slide showed the 1978 story date separately from the visible 1984 illustrative-photo label. Did not inspect every photograph on the simulator or verify Apple TV hardware.
- No native code changed for this policy update, so no iPhone rebuild was needed. Earlier failed attempts below describe the previous, stricter date rule.

## Failed October 1978 Generation (17 September 2026)

- Investigated the live failure for `Top 10 hits October 1, 1978`. The source auditor had interpreted the original chart query as its assignment and discarded non-music stories. Calendar resolution is now separate, and dated news research, audit and image selection no longer receive the chart wording or soundtrack tracks.
- A live retry researched 17 stories for 1-7 October 1978 and passed the UK/topic coverage checks. Verified research is now checkpointed as a private draft, so image-stage retries do not repeat all research.
- Expanded archive searches to verified people associated with stories, retained longer archive metadata, supported surname-first catalogue names and prevented disconnected words matching unrelated subjects. Added safeguards against modern statues and biographical dates being mistaken for period photographs.
- The final live image pass searched 72 queries, collected 33 candidates and submitted eight images for visual review. Only three passed; the montage failed illustrated coverage. No replacement capsule was published. This remains an unresolved live content failure, not a successful generation or simulator validation.
- The bridge changes do not require a new iPhone build. Apple TV hardware playback remains unverified.
- Final bridge validation: all 335 tests across 31 suites passed, production build passed, and `git diff --check` passed. These checks do not establish successful live generation.

## Preparation Player and Capsule Selection (17 September 2026)

- Replaced manual picture navigation with previous track, music play/pause and next track. Verified live simulator pause/resume and next changed the room state/title; photographs continued cycling. Previous uses the existing Roon previous command; returning to a prior song was not established in that live check.
- Reproduced Cinema opening the old October 1982 capsule during an unrelated playlist. After the fix, the same live scenario opened the saved library rather than the old viewer. Pending preparation takes priority over saved associations. Matching uses current title/artist and upcoming tracks, accepting remastered title variants.
- Added Play now while preparing. Verified in a paired iPhone 17 simulator using the external cached manifest and the deterministic delayed-preparation preview: the button opened a preparation player with all three music controls; closing and tapping Cinema returned to preparation; completion automatically replaced it with photographs. No new play-tracks request was issued when the preview's requested playlist already matched.
- Preparation errors survive library refresh. The preparation task belongs to the library, not the viewer, so dismissing either presentation does not cancel it.
- Full native suite passed: 153 tests (162 executions including parameterized cases), including 13 focused Time Capsule tests. Signed iPhone and tvOS SDK builds passed. Apple TV hardware playback remains unverified.
- Installed the combined update on David's connected iPhone; devicectl confirmed installation. Physical-phone interaction was not inspected. Restored the simulator to normal live mode after the preview check.
- This validates selection and presentation, not fresh historical research. The older content-quality failure described below remains unresolved.

## Playback and UK content follow-up (17 September 2026)

- Reproduced the October 1982 capsule containing five artist photographs and no domestic news. One Survivor photograph was an unrelated 2003 ceremony; new metadata and pixel checks reject this namesake.
- Play now dismisses the library and opens the montage before awaiting Roon. Verified on the live paired iPhone 17 simulator: the viewer displayed Starting music while Eye of the Tiger began in Office.
- Watch pictures advanced automatically between real cached photographs while Office remained paused. Music and picture pause are independent.
- Now Playing's Cinema opened the Office-associated capsule directly. Closing at photograph 3 and reopening restored photograph 3 while Who Can It Be Now continued playing. Bridge play-tracks request count stayed at 8 and capsule-assignment count stayed at 6 across both opens. The stack icon successfully returned to the saved library.
- Updated app built and installed on David's connected iPhone. Installation was verified with devicectl; physical phone interaction was not inspected.
- Seven focused native Time Capsule tests passed, including resuming the photograph/hold and resetting after a rebuild. iOS simulator, signed iPhone and tvOS device SDK builds passed. The direct-open update was also installed on the connected iPhone. Apple TV hardware playback remains unverified.
- All 328 bridge API tests passed. Added regression coverage for domestic/topic coverage, separate research and source audit, namesake rejection and named image subjects.
- New automated research attempts correctly failed quality gates rather than overwriting the old capsule, including a runtime trial with TIME_CAPSULE_MODEL=gpt-5.4. The latest attempt lacked news/topic diversity after source audit. The old five-photo October capsule remains unchanged; the requested replacement content is not delivered. Passing tests alone do not establish acceptable historical content or sharp photographs.

## Earlier release checks

The following records the earlier review from `cinema-v0.1.0` to `cinema-v0.2.0`, not the current content-quality result.

## Result

The earlier release was cleared for source release. Subsequent live use exposed content and playback failures, documented above; the earlier checks did not establish reliable coverage of arbitrary historical weeks.

## Checks

- Native iOS simulator build and full test run passed (146 tests reported); the six Time Capsule tests also passed in an explicit focused run.
- Shared native/tvOS sources passed tvOS SDK type checking. No tvOS simulator runtime is installed here.
- iPhone and iPad simulators displayed real archive photographs and advanced between headlines. Music pause held the current photograph; the model tests cover resume timing, wraparound and continuity independent of song identity.
- Bridge: all 451 configured tests, workspace lint and production builds passed. The 12 focused capsule tests cover request anchoring, evidence links, event/photo dates, explicit image IDs, duplicate references, visual-review rejection, failed rebuild preservation and HTTP access.
- Each configured TypeScript workspace passed its own installed compiler with its own project configuration.
- A live external request for 24–30 June 2007 was researched and illustrated. The final visual review retained six photographs and rejected an obviously blurred original. This checks retrieval and playback, not comprehensive coverage of every event that week. No example content is bundled in the product.
- Changed interface copy, source links, rebuild route and request preservation were manually reviewed. Existing manifests can be rebuilt without changing their original request or room association.

## Generic content-gate findings

The pre-main script ran against `origin/main...HEAD` in both repositories. Its native check passed; native build/tests above supplement its lack of Xcode detection. The bridge script reported two tooling false positives, resolved by the checks below:

1. It treated the Fastify integration-test URL `/paired/time-capsules/saved/rebuild` as a missing static website file. The registered `/:id/rebuild` handler is exercised by the passing route test; this is not a document link.
2. Root `npx tsc --noEmit` resolved the unrelated npm package named `tsc`, rather than the workspace TypeScript compiler. Explicit calls to the installed TypeScript compiler passed for API, Angular app, model and client workspaces. Full production builds passed too.

The reported external 404s are deliberate mock/example image URLs in tests, never production asset sources. The existing Angular initial-bundle size warning (947.50 kB against an 870.40 kB budget) remains unchanged. The generic script's failure is therefore not reported as a clean automated gate; the relevant route and compiler checks were resolved manually.
