# Verified AI music search

The iPhone/iPad AI Search screen uses the bridge's `POST /api/:client_id/music-discovery` endpoint. Deploy the matching bridge before installing the app. An older bridge produces an explicit update message; the app does not silently return to unverified suggestions.

## Search behaviour

- Auto interprets the request; Tracks and Albums explicitly override the result type.
- Complete classical works such as Elgar's Enigma Variations return albums. A named movement such as Nimrod returns track recordings.
- AI supplies structured intent and candidate descriptions. Roon supplies the recording names, artwork, contents and playback paths. An unavailable suggestion has no active Play control.
- Album results contain the whole album plus a separately verified complete-work subset. Play album includes companion works. Play work only queues the selected work's sections in album order.
- All album searches look up release dates for the exact playable albums found in the Roon catalogue, including their performers and companion works. Matching dates include a source link. Ordinary album searches keep their catalogue order; latest searches sort new releases first, then reissues, then unknown dates. Missing or failed date research leaves the albums playable and explains the unverified dates. Latest searches explicitly say when results could not be ranked as the latest. This ranks verified catalogue results, not every release worldwide.
- Ordinary album searches first use the UK Apple catalogue when album title and performer credits match. Full dates require matching track counts and consistent dates; a consistent year remains useful when editions differ or the catalogue gives a potentially year-only January 1 date. Conflicting years and future dates are rejected. Artist queries are shared and bounded to five requests with an eight-second timeout. Latest searches continue researching original dates and reissue status before ranking.
- Web date research returns structured records directly. Remaining result sets use parallel groups of five albums (at most four groups), so failed research for one group preserves dates from the others. Exact album/performer matching, cited source URLs and full valid release dates remain required for web evidence; partial or future dates are rejected. Source titles may include artist credits and physical formats, but videos, different editions or a parent album cannot provide a separately titled audio release's date.
- Completeness requires the known movement/section count. If completeness cannot be established, the album is not labelled as a complete recording. Catalogue availability and release-date coverage can limit the results.
- A lost network connection during search retries once after a short pause. Timeouts and server errors are returned without retrying. Playback is never retried after a connection loss, because the room's queue may already have changed.

## Playback

Results have server-generated IDs scoped to the paired client, expire after 30 minutes, and are lost on bridge restart. Playback refreshes and validates the saved Roon paths, metadata and ordered contents before modifying the selected room's queue. Roon browse item keys are not persisted. A changed or expired recording asks the user to search again.

Whole albums use Roon's album action; work-only and track selections use their verified track paths. Shuffle is disabled to preserve section order. Concurrent discovery play requests in the same room are rejected. The iOS screen waits for a fresh Roon playing event matching the selected music before navigating to Now Playing. Errors leave the search results visible.

Create Cinema preserves the verified recording paths and artwork for the chosen tracks or album.

The existing Siri and Apple TV search contracts remain supported. They receive the shared matching fixes, while the new typed discovery screen is an iPhone/iPad feature.

## Verification

Backend tests cover the original Petrenko album-title mismatch, reordered conductor/orchestra credits, wrong-performer rejection, complete versus excerpt selection, date provenance, expired/cross-client selections, catalogue changes and album/work queue actions. iOS tests cover decoding, unavailable selections and the album screen, details and mode control. Search and browsing themselves never invoke playback actions.

On 22 November 2026, the reported `Milos Karadaglic` / Albums request returned 10 verified albums (110 tracks) from the local bridge in 22.7 seconds. The screenshot reported a lost network connection; the original interruption was not reproduced. Added a single retry for that transport error on discovery searches only. All nine targeted discovery and recovery tests passed on the iPhone simulator, covering repeated failures, non-retryable errors, cancellation and no playback retry. The signed build was installed and launched on the connected iPhone Duo. Device inspection confirmed the search loading screen, but the phone returned to ChatGPT before final results could be observed; successful completion on the phone remains unverified.

The release-date follow-up was deployed to the local bridge on 22 November 2026. The same Albums request then completed with HTTP 200 in 46.8 seconds: all 10 albums remained playable, five had sourced full dates and three had sourced release years. Guitar Covers and Sour Times remained unverified. All 53 targeted discovery, routing, catalogue metadata and research tests passed, along with lint, TypeScript checking and the production build. The existing iOS date label supports both full dates and years, so this change needs no app reinstall. Live validation used a temporary paired client, removed it afterwards and issued no playback requests.
