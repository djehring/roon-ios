# Roon Remote

Native SwiftUI clients for [roon-web-stack](https://github.com/djehring/roon-web-stack).
The apps talk to the Docker/extension API over HTTP on the LAN.

Open `RoonRemote.xcodeproj` (generated from `project.yml` via XcodeGen) and
pick a scheme:

| Scheme | Platform |
|--------|----------|
| **Roon Remote** | iPhone / iPad |
| **RoonRemoteWatch** | Apple Watch (companion) |
| **RoonRemoteTV** | Apple TV |

Simulator can pair if you type the bridge `host:port` during onboarding.

## Pairing

1. Run [`djehring/roon-web-stack`](https://hub.docker.com/r/djehring/roon-web-stack)
   so the API is on HTTP port `3000` (not 3443). See the stack
   [deploy guide](https://github.com/djehring/roon-web-stack/blob/main/doc/deploy.md).
2. In the web Settings dialog, read the six-digit PIN.
3. On the device, allow Local Network, pick the advertised
   `_roon-web-stack._tcp` service (or enter `192.168.0.14:3000`), and
   type that PIN.
4. Enable the extension in Roon if it is not already paired, wait until
   the bridge reports `SYNC`, then pick a zone.

`client_id` is stored in the Keychain. Unpair from Settings.

Playing a track, album, or playlist from Library shows a playback confirmation
with the selected room, then opens Now Playing on iPhone, iPad, and Apple TV.
Queue and Play Next keep the browse screen open. Failed actions show an error
without navigating away.

## Apple Watch

Companion of the iPhone app (the Watch does not talk to the bridge). Keep Roon
open on the phone. When a zone is playing, a Live Activity appears on the Watch
Smart Stack. Tap it to open the Watch app.

Now Playing is full-bleed cover:

- Tap: play / pause
- Swipe left / right: next / previous
- Swipe up: queue (tap a row to play from here)
- Swipe down, or the speaker button: rooms
- Digital Crown: volume
- Long-press: stop, mute, transfer to another room

## Siri

In Shortcuts, open **Roon Remote** and turn on Siri for each shortcut you want
(Play in a room, Increase volume, Decrease volume, Stop, Play or pause, Next
track, Previous track, Mute, Unmute). After that:

> Hey Siri, play Radio 3 in the Kitchen with Roon Remote
> Hey Siri, turn it up with Roon Remote
> Hey Siri, stop with Roon Remote
> Hey Siri, skip with Roon Remote

Add a room for a different zone than the phone, for example "turn it up in the
Kitchen with Roon Remote". Volume moves about 10% of that output's range.

The phone needs to be unlocked on the same Wi-Fi as the bridge. "with Roon"
can hit the official Roon app or the Watch instead.

## Apple TV

Roon on Apple TV is an independent app (same pairing flow as iPhone). Tabs:
**Now Playing**, **Library**, **Search**, **Rooms**, **Settings**. Focus-first
layout inspired by Apple Music on TV. Camera / cover recognition is iPhone-only.

Leave the remote alone on Now Playing for eight seconds while music plays and the
cover art takes the whole screen with a slow Ken Burns drift, naming the track and
artist along the bottom and following each change of track. The remote's back
button returns the controls; so does pausing.
It waits for the full-size cover, stays away while the volume, queue, or Cinema
is up, and holds still under Reduce Motion or VoiceOver.

## Search & Story

AI search and cover recognition live under Search on iPhone. Track story opens
from Now Playing (Story chip) and also calls the bridge. Paste the OpenAI
API key once in the web Settings. Those routes return HTTP 503 until a
key is set on the sidecar.

## Cinema / Time Capsules

Choose **Create Cinema** from an album, Roon playlist, room queue or AI Search,
or **+ New Cinema** in the Cinema library. **Music** lets you reorder tracks,
remove them with Undo, and add tracks, albums, playlists or the current queue.
Each Cinema owns an independent soundtrack; saving never alters the source or
starts room playback. Saved items use **Edit → Music** for the same controls.
Albums, playlists and queues start with **Album artwork**, which needs no AI key.
AI searches suggest a period, artist or musical-work companion with relevant topics. On iPhone and iPad,
**My photos** also supports selected photos or an album snapshot kept on that device.
The album browser shows Photos album names, folder paths, cover thumbnails, and a
photo preview before selection. Albums larger than 200 photos remain browsable;
choose up to 200 pictures from the preview to save with the montage.
In **Presentation**, enable **Show track title** to keep the current song and artist
visible after controls fade. **Picture motion** offers Still, Gentle motion and
Ken Burns pan and zoom, including continuous movement for a single album cover.
Choose picture captions, order, and a 5-, 8- or 16-second pace. Presentation changes
save without rebuilding pictures; Reduce Motion keeps them still.
The selected tracks remain the soundtrack. Pictures continue across songs. Swipe or use the
photograph controls to move between pictures, or hold the montage while the music keeps playing.
No historical programme is bundled.
Open **Cinema** from Now Playing to replay saved programmes. On Apple TV, select
the same Roon room and choose **Join** to follow its programme without restarting music.

Music importing and editing require the accompanying bridge update (`musicVersion: 1`).
Research-based pictures require an OpenAI API key on the bridge; album artwork and
personal photos do not. Music snapshots support up to 1,000 tracks. See [implementation and setup](docs/time-capsule.md) and the
[Cinema design](docs/design/time-capsule.md). Native viewing is implemented;
AirPlay video export and licensed newspaper archive integration are future work.

Regenerate the Xcode project after editing `project.yml`:

```bash
xcodegen generate
```

## Tests

`RoonRemoteTests` is a logic-only bundle (no host app), so it covers the pure
types and local photo storage. `RoonRemoteUITests` checks the adaptive Cinema setup
on iPhone and iPad with deterministic demo content. Run the **Roon Remote** scheme:

```bash
xcodebuild test -project RoonRemote.xcodeproj -scheme RoonRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

`CinemaPhotoAlbumUITests` creates real sample albums in the simulator's Photos
library and checks permission handling, album previews, folder search, cancellation,
large-album subsets, saving, playback, and reopening after launch. These tests need
no bridge or iCloud account; Photos authorization is handled by the UI test.

Files under test are listed explicitly in the target's `sources`, so add new
ones there when they need coverage.

### Checking layouts without a bridge

With no bridge on the network the app never leaves onboarding, so Debug builds
accept `-roon-demo-store` to fill the store with stand-in zones, a track, and a
queue, then skip to the main session:

```bash
xcrun simctl launch <device> com.djehring.roonremote -roon-demo-store
```

Demo content includes sample browse pages, artwork, and simulated playback;
these actions do not control a real room. `BrowsePlaybackUITests` and
`BrowsePlaybackRemoteUITests` exercise browse feedback and navigation with this
content on iPhone/iPad and Apple TV respectively.
