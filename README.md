# Roon Remote (iOS prototype)

Clickable SwiftUI screens with mock data. No network. Open
`RoonRemote.xcodeproj` in Xcode and run the **Roon Remote** scheme
on an iPhone simulator.

This is the design-sign-off gate for a native replacement of the
roon-web-stack Angular client, plus a Watch companion.

## Prototype shortcuts

- The app starts on **Now Playing**. Replay onboarding from Settings.
- PIN: any six digits except `000000`.
- Finding the bridge always succeeds after a short pause.
- Settings > Preview share sheet shows the Gramophone flow.

## Visual

Dark-first, near-black, warm gold accent. Four tabs: Now Playing,
Library, Search, Settings. Queue and volume are sheets.

Run the **Roon Remote** scheme on an iPhone simulator. The Watch
app is a separate **RoonRemoteWatch** scheme so this prototype
does not require a watchOS simulator runtime. Embed it later
when wiring WatchConnectivity.
