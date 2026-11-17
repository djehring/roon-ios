# Now Playing updates

The iPhone Lock Screen/Dynamic Island card and its Apple Watch Smart Stack
presentation use a Live Activity. The small Watch-face complications use
WidgetKit and a snapshot saved on the Watch. These are separate update paths.

## Watch background delivery

The Watch activates Watch Connectivity at application launch, including launches
that never create a SwiftUI screen. Its receiver decodes and saves the incoming
snapshot and requests a widget reload before completing background work. A
background task remains retained until the session is activated, Watch
Connectivity has no pending content, and all callbacks queued for processing
have finished. This follows [Apple's background delivery guidance](https://developer.apple.com/documentation/watchkit/wkwatchconnectivityrefreshbackgroundtask).

The phone attaches an increasing publication timestamp to changed snapshots.
Immediate messages, application context and queued transfers share that same
timestamp. The Watch rejects older deliveries, including old application context
read when the screen opens. Existing untimestamped payloads still decode and work
until a timestamped publication has been received. The phone retains its last
publication time across launches so restarting or adjusting the clock does not
make a new snapshot look older.

Artwork and metadata are saved together. A new album without downloaded artwork
clears the old cover; later artwork reloads the widget. Identical deliveries and
volume/queue-only updates do not request unnecessary widget reloads. Playback
changes, including pause and stop, can enqueue background delivery to the Watch.

## Live Activity delivery

New Live Activities request an ActivityKit push token. The phone registers the
token and selected room with its paired bridge, updates the registration after
token/room changes, and removes it when ending the activity. Registrations are
ordered so a slow response cannot leave a previous token or room registered.
Failures back off from 30 seconds to five minutes; foreground activation retries
immediately. Opening the app migrates an older local-only card once fresh room
data arrives.

The bridge receives Roon events independently of the phone and sends metadata
changes through APNs. It persists registrations across restarts, coalesces
updates, backs off on failures, and waits for fresh Roon data after reconnecting.
Its private APNs signing key stays on the bridge. See the companion bridge
repository's `doc/live-activities.md` and `.env.example` for configuration.
Debug builds use sandbox APNs; distribution builds use production. The app is
signed with the corresponding push entitlement and enables frequent Live
Activity updates. It does not request notification-alert permission or include
alert payloads.

Local updates remain a fallback while the phone app runs. The publisher now
tracks what it submitted per activity instead of comparing each tick against
potentially stale ActivityKit content. Identical content is suppressed, with a
bounded freshness renewal and reset on foreground activation. Submissions carry
the room observation timestamp so delayed local data cannot supersede a newer
push merely because it was submitted later.

Stale dates reflect the expected end of the current track, with a ten-minute
maximum for unknown-length/paused content. Cached data does not extend freshness.
A stale Lock Screen or Watch card says **Open app to refresh** and disables its
playback button. Apple controls APNs delivery and rendering; a Live Activity does
not keep the phone app running. Native complications remain subject to WidgetKit
refresh scheduling.

Opening the phone app is still required to start a new activity after it ends,
is dismissed, or reaches Apple's lifetime limit. This implements update pushes,
not push-to-start.

## Diagnostics

Debug builds write a bounded, device-local trace to
`Library/Application Support/NowPlaying/diagnostics.json`. It contains at most
200 records for app lifecycle, received Now Playing changes, ActivityKit update
submissions, bridge reconnects/failures and audio interruptions. It excludes
credentials and is not uploaded. Progress ticks and suppressed duplicate
submissions are not logged. Registration logs never include the token or URL.

For a physical-device check, launch the app normally with music playing, then
lock the phone and allow a natural track transition. Collect the trace afterwards
without attaching a debugger, which can change background lifetime. Compare the
bridge's actual track, `nowPlaying.received`, `activity.submitted` and
`activity.observed`; a submission or observed content alone does not establish
that the card rendered it. Confirm that separately on both device displays.

## Validation — 4 October 2026

- All 301 native logic tests passed, including background delivery, snapshot
  ordering, duplicate suppression, freshness, migration and registration races.
- Signed iPhone and Watch builds passed, along with Watch and tvOS simulator
  builds.
- The updated app was installed and launched successfully on the iPhone. Watch
  installation subsequently succeeded after its connection became available;
  device app inventory confirmed the installation.
- The user reported that the Now Playing card remained on the first track.
  The phone trace received `Win (2016 Remaster)` at 17:56:19 BST while the app
  was in the background. It submitted that state repeatedly until the scene
  became active at 17:59:19. This supports a stalled Live Activity update path,
  rather than a missing Roon track event. A submission is not proof of rendering.
- With no app launch or playback command from the diagnostic tools, the next
  natural transition to `Fascination (2016 Remaster)` arrived at 18:01:06 BST.
  Read-only device screenshots then showed Fascination on both the iPhone Lock
  Screen and Watch Smart Stack. This demonstrates that the problem is
  intermittent; it does not establish that the earlier stall has been fixed.
- The displayed Watch Smart Stack card is the mirrored Live Activity, separate
  from Watch Connectivity and the native complication receiver changed above.
  The old publisher resubmitted identical content every tick when ActivityKit's
  reported content had not advanced. This retry loop is now removed; the earlier
  device evidence does not establish that it alone caused the stall.
- The push-enabled iPhone build was signed with the development push entitlement
  and installed; the matching Watch installation also succeeded on the replacement
  Watch. The updated local bridge was built and restarted, its health check
  passed, and its capabilities endpoint correctly reported push disabled before
  key configuration. A temporary validation client was removed afterwards.
- The full bridge suite passed (541 tests), followed by all 15 focused push
  tests, including the added Roon-event integration test. The delivery tests use
  a local HTTP/2 server and an ephemeral test key; automated tests do not send
  to Apple.
- A Sandbox APNs key restricted to the app's Bundle ID was configured on the
  local bridge. The key is stored outside the repository with owner-only access;
  its contents are excluded from source and diagnostic output. The initial key
  whose download failed was revoked; Apple's key list confirmed only the working
  House Remote replacement remains. The bridge's
  capabilities endpoint then reported push enabled, the phone registered its
  activity, and APNs accepted the first update at 19:01:15 BST. The phone trace
  observed the current track at the same time. APNs also accepted the natural
  transition from `Tonight the Heartache's on Me` to `Let 'Er Rip` at 19:03:16
  BST, after the phone app went into the background at 19:01:31. The phone trace
  received, submitted and observed the new title. Acceptance and observed
  content do not by themselves prove Lock Screen or Watch rendering; a
  locked-phone track-transition check remains to be completed.
