# Roon Remote

Native iPhone client for [roon-web-stack](https://github.com/djehring/roon-web-stack).
The signed-off SwiftUI screens talk to the Docker/extension API over HTTP
on the LAN. The Watch app is a companion: it does not talk to the bridge.
It shows the phone's selected zone, transport, Digital Crown volume, and
a room list over `WCSession`.

Open `RoonRemote.xcodeproj` and run the **Roon Remote** scheme on a
physical iPhone (that installs the Watch app when a paired watch is
present). Simulator can pair if you type the bridge `host:port`
during onboarding. To debug Watch UI, run the **RoonRemoteWatch** scheme
with the iPhone app already paired.

## Pairing

## Pairing

1. Start roon-web-stack so the API is on HTTP (not the 3443 HTTPS port).
2. In the web Settings dialog, read the six-digit PIN.
3. On the phone, allow Local Network, pick the advertised
   `_roon-web-stack._tcp` service (or enter `host:port`), and type that PIN.
4. Enable the extension in Roon if it is not already paired, wait until
   the bridge reports `SYNC`, then pick a zone.

`client_id` is stored in the Keychain. Unpair from Settings.

## Watch

Install Roon Remote on the iPhone first and finish pairing. The Watch
app follows that session: play/pause, skip, Digital Crown volume on the
zone's first output, and a second page to pick a room. Complications
show art or the current title. Open the iPhone app if the Watch says it
cannot reach the phone.

## Search

AI search, cover recognition, and track story call the bridge. Those
routes return HTTP 503 when `OPENAI_API_KEY` is missing.
