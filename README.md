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

1. Start roon-web-stack so the API is on HTTP (not the 3443 HTTPS port).
2. In the web Settings dialog, read the six-digit PIN.
3. On the device, allow Local Network, pick the advertised
   `_roon-web-stack._tcp` service (or enter `host:port`), and type that PIN.
4. Enable the extension in Roon if it is not already paired, wait until
   the bridge reports `SYNC`, then pick a zone.

`client_id` is stored in the Keychain. Unpair from Settings.

## Apple Watch

Companion of the iPhone app (the Watch does not talk to the bridge). Keep Roon
open on the phone. Now Playing is full-bleed cover:

- Tap: play / pause
- Swipe left / right: next / previous
- Swipe up: queue (tap a row to play from here)
- Swipe down, or the speaker button: rooms
- Digital Crown: volume
- Long-press: stop, mute, transfer to another room

## Siri

On iPhone, after the app has connected once:

> Hey Siri, play Radio 3 in the Kitchen with Roon

Room names are your Roon zones. "with Roon" (or "with Roon Remote") is how Siri
picks this app instead of Music. The same action is in Shortcuts as **Play in a room**.

## Apple TV

Roon on Apple TV is an independent app (same pairing flow as iPhone). Tabs:
**Now Playing**, **Library**, **Search**, **Rooms**, **Settings**. Focus-first
layout inspired by Apple Music on TV. Camera / cover recognition is iPhone-only.

## Search & Story

AI search and cover recognition live under Search on iPhone. Track story opens
from Now Playing (Story chip) and also calls the bridge. Those routes
return HTTP 503 when `OPENAI_API_KEY` is missing.

Regenerate the Xcode project after editing `project.yml`:

```bash
xcodegen generate
```

## Tests

`RoonRemoteTests` is a logic-only bundle (no host app), so it covers the pure
types rather than views or the store. Run it with the **Roon Remote** scheme:

```bash
xcodebuild test -project RoonRemote.xcodeproj -scheme RoonRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Files under test are listed explicitly in the target's `sources`, so add new
ones there when they need coverage.
