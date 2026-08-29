# Roon Remote

Native iPhone client for [roon-web-stack](https://github.com/djehring/roon-web-stack).
The signed-off SwiftUI screens talk to the Docker/extension API over HTTP
on the LAN. There is no Watch companion, Live Activity, or share
extension in this version.

Open `RoonRemote.xcodeproj` and run the **Roon Remote** scheme on a
physical iPhone. Simulator can pair if you type the bridge `host:port`
during onboarding.

## Pairing

1. Start roon-web-stack so the API is on HTTP (not the 3443 HTTPS port).
2. In the web Settings dialog, read the six-digit PIN.
3. On the phone, allow Local Network, pick the advertised
   `_roon-web-stack._tcp` service (or enter `host:port`), and type that PIN.
4. Enable the extension in Roon if it is not already paired, wait until
   the bridge reports `SYNC`, then pick a zone.

`client_id` is stored in the Keychain. Unpair from Settings.

## Search

AI search, cover recognition, and track story call the bridge. Those
routes return HTTP 503 when `OPENAI_API_KEY` is missing.
