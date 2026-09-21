# Cinema from any music — experience and implementation plan

21 September 2026 · Implemented locally in the native app and companion bridge. See [implementation notes](../cinema-music.md) for delivered behavior and validation.

Make Cinema a saved, editable programme of music and pictures. Start with a Roon playlist, an album, the current room queue, or AI results; use the same editor to arrange the soundtrack and choose pictures. Reordering and adding music are available both during creation and later through **Edit → Music**.

The default is an independent copy of the selected music. Explain this once in setup: “Your Cinema copy can be edited separately.” Saving edits does not change the original Roon playlist or the room's current playback. The next explicit **Play music & pictures** uses the saved version.

**1. Put “Create Cinema” where the music already is**

| Starting point | Entry | Music included |
| --- | --- | --- |
| Album detail | Visible **Create Cinema** action beside the existing playback actions; also available in its menu | All tracks, in disc/track order |
| Roon playlist detail | The same action | Complete playlist, in its saved order, including deliberate repeats |
| Queue | **Create Cinema** in the queue header on phone, iPad and TV | Current track plus the upcoming queue, frozen at capture time |
| AI Search results | Rename **Set up Cinema** to **Create Cinema** | Current playable selection in its edited order; retain the original search context |
| Cinema library | **+ New Cinema**, including in the empty state | Choose Current queue, Playlists, Albums, or Find music; then enter the same editor |

Album and playlist creation must work directly from browsing without first playing or queuing the source. Actions must be visible without discovering a long press. Context menus are shortcuts.

Queue import shows the source room and “Current track + N upcoming tracks”, with an **Include current track** toggle initially on. It captures the full current song, not its remaining seconds. A queue with only a current track is still valid. With no music, offer **Choose music**. Already-played history and future automatic-radio recommendations are outside this snapshot; use the original playlist entry to import that playlist from its beginning.

After capture, incoming playback events and room changes do not alter the draft. Source provenance remains “From Living Room queue” even if a different playback room is selected later.

**2. Use one editor with three familiar sections**

Retain the current dark appearance, gold primary action, artwork summary and native navigation. The opening page shows an editable name, source, track count, and duration when complete duration data is available. Album/playlist names prefill the title; a queue gets a useful room/date title. Renaming never changes picture context or the original AI date anchor.

| Section | Summary and destination |
| --- | --- |
| **Music** | “12 tracks · 48 min”; opens the ordered soundtrack with **Add music** |
| **Pictures** | Current choice and preview; opens the existing content/context options |
| **Presentation** | Captions, movement, pace and **Picture order** |

Rename the existing presentation setting “Order” to **Picture order** so it cannot be confused with track order. Remove “soundtrack unchanged” from the editor.

Use **Save Cinema** for creation and **Save changes** for ordinary edits. If the user changes research topics or visual context, use **Save & update pictures** with a short explanation of the pending update. These actions return to the selected item in Cinema. Playback remains an explicit choice from the saved item.

On iPhone, section rows open focused pages instead of putting a long soundtrack inside the already-long picture form. iPad and TV retain their summary/detail arrangement, adding Music before Pictures and Presentation.

**3. Make arranging music direct and reversible**

The Music page shows numbered rows, artwork, title, artist and album, with a persistent **Add music** button and a visible **Reorder** action.

- Reorder exposes native drag handles on iPhone/iPad. Keep the resulting order when leaving and reopening the page.
- Track menus provide **Move up**, **Move down**, **Move to start**, **Move to end**, and **Remove**. These also provide accessible alternatives to dragging. Disable moves at the relevant boundary.
- On TV, selecting **Move** keeps focus on the track while Up/Down changes its position; Select finishes and Back cancels that move. Provide explicit move actions as a fallback.
- Remove supports Undo. Reordering and adding also participate in draft undo, without touching live playback.
- **Done** returns from Music to the editor and retains the draft. Saving commits the whole draft. Cancelling a changed editor asks whether to discard the changes; an unchanged editor closes directly.
- Allow an empty draft while editing, with a prominent Add music action. Saving requires at least one track. Preserve the draft across a failed save or temporary disconnection.

Track repeats are valid. Each occurrence has its own identity, so moving or deleting the second occurrence affects only that row.

**4. Add tracks, albums and playlists through a dedicated picker**

**Add music** opens a picker headed “Add to [Cinema name]”, with search and browse destinations for Tracks, Albums and Playlists. Reuse familiar library presentation, but give this picker explicit selection behavior: tapping a track selects it; opening an album or playlist browses its contents. No row tap starts music.

Provide **Add album**, **Add playlist**, and individual track selection. A sticky **Add N tracks** button confirms the selection and returns to Music, scrolled to the first added row. Search and navigation retain the current selection basket; Cancel discards only that basket.

Append to the end by default. Preserve album/playlist order within a selected collection and selection order between collections or individual tracks. Users can immediately reposition the new rows. Import a collection as one unit: if loading fails, retain the existing draft and offer Retry instead of silently appending half an album.

Mark matching tracks **Already included** and offer **Add again**. Preserve repeats in imported playlists; do not deduplicate them automatically. A second tap on an already-selected picker result deselects it rather than adding another occurrence.

AI remains an optional source. Existing AI results use the same draft editor; adding newly requested AI suggestions can follow the same selection-basket contract without changing the app's global search results. Direct Roon search, albums and playlists are required for the initial release.

**5. Make sensible picture choices without requiring an AI prompt**

Expose **Album artwork** as a first-class Pictures choice, using the existing covers-only path. Default new album, playlist and queue imports to it: the music's own covers are relevant, quick to prepare, and require no invented subject. A single-album Cinema item can show its cover with the chosen movement and pace.

Offer About the artist or About the work as suggestions when the music metadata supports them. Keep Around this time and My photos available, and preserve the current contextual defaults for AI-created items. A playlist name such as “Evening” must not automatically become a historical research request. A recording year must not automatically become a composition date.

Once a visual subject is chosen, adding another artist does not silently change it. The user can explicitly change Pictures. Personal-photo items keep their existing device-local behavior and imported image copies.

| Change | Save behavior |
| --- | --- |
| Rename or reorder tracks | Save immediately; retain pictures and montage position |
| Add/remove tracks with researched or personal pictures | Save music immediately; retain chosen visual subject and existing pictures |
| Add/remove albums with Album artwork selected | Save music, then refresh the relevant covers without AI research |
| Change captions, movement, pace or picture ordering | Update presentation from saved material without new research |
| Change visual subject, dates or topics | Prepare new pictures; retain the available montage until replacement succeeds |

Reordering music does not reorder photographs. Existing independent picture timing continues. Preserve or remap any track-to-scene references when the soundtrack changes.

When saving while this item is playing, explain: “Saved. Your changes will play next time.” **Play music & pictures** deliberately starts the saved order in the selected room; **Watch pictures** retains its current behavior. Music-only saves must not restart playback, clear the room queue, or incur picture-generation calls.

**6. Address the current implementation constraints**

The existing app is a good foundation, but this needs a shared editing model and bridge support beyond adding entry buttons.

| Observed implementation | Required change |
| --- | --- |
| `CapsuleLibrary.create` takes AI search context and suggested tracks | Add a source-independent `CinemaDraft`, with adapters for AI results, queue snapshots and browsed collections |
| `CapsuleTrack` contains only artist/title/album | Add stable per-occurrence IDs and optional duration/artwork/resolution metadata; do not use the track title as row identity |
| `CapsuleRequest.query` drives source context and initial naming | Separate editable display title, source provenance, soundtrack, and chosen visual context; preserve historical AI anchors |
| Browse rows expose session-dependent item keys and presentation text | Resolve a read-only music snapshot with verified metadata and replay information; do not persist raw browse keys as durable IDs |
| Normal native browsing loads a single page of at most 500 items | Paginate collection imports to completion and preserve source order; do not import only visible rows |
| The bridge subscribes to 150 queue items | Capture a complete bounded snapshot with source count/revision and explicit completeness information |
| Cinema request validation permits only 1–100 tracks | Replace the AI-era limit with a measured soundtrack limit, advertised through capabilities; bound picture research separately |
| Shared editing accepts only `{options}` and always starts generation | Add versioned title/music/presentation updates that can save without generation; retain compatibility for older clients |
| Personal-photo update changes only options | Save edited music/title atomically with the existing personal manifest and reuse its photos |
| Playback searches track titles before album fallback | Add a source-aware replay resolver that preserves the selected recording wherever the available metadata permits it |
| Artist/work research may derive its subject again from tracks | Distinguish initial suggestions from an explicitly saved subject so later music edits cannot override the user's choice |

Roon supports separate browse sessions and paged loading, which are the right basis for collection import and the picker. [Roon Browse API](https://roonlabs.github.io/node-roon-api/RoonApiBrowse.html). The queue API accepts a maximum item count, while zone state can report the number of queue items; verify completeness using both before advertising a full queue capture. [Roon transport source](https://github.com/RoonLabs/node-roon-api-transport/blob/master/lib.js), [Roon Zone API](https://roonlabs.github.io/node-roon-api/Zone.html).

The public browse item describes a navigable UI item, not a guaranteed permanent recording identifier. Exact recording recovery across sessions, multi-disc metadata and queue capture beyond 150 items need a read-only feasibility check on the connected Core before implementation promises are finalized. [Roon Item API](https://roonlabs.github.io/node-roon-api/Item.html). Store reliable source metadata and a resolution recipe, then re-resolve keys when necessary. If the original version cannot be identified, surface that track for replacement or removal; do not silently substitute a different recording.

For over-limit or incomplete sources, show the actual available count and a way to choose tracks. Never label a partial import as the whole playlist or queue. Do not infer that increasing `max_item_count` guarantees unbounded retrieval. Keep finite music snapshots as the supported scope; live radio streams cannot become a reusable list of future songs.

Use an isolated, serialized browse session for imports and the picker, following the existing artwork lookup pattern. Loading and selection must not execute Roon action rows, change the normal browse position, or call the playback resolver as a way of discovering tracks.

**7. Protect saved edits and background picture updates**

Keep Cinema item identity independent of mutable soundtrack content. Legacy items retain their existing IDs; new per-track occurrence IDs are persisted on migration/save. Existing requests, saved pictures, room associations and personal manifests remain readable.

Add a persisted revision and require a base revision for updates. If another device has edited the item, preserve the local draft and offer to reload or save it as a new Cinema item. Do not overwrite silently.

A picture job must commit only its picture result against the expected visual-input revision, rather than writing back an older complete manifest. This allows music-only saves while unrelated pictures are being prepared. If changed music invalidates an album-cover job, discard its stale result and refresh from the latest album set. Recoverable failures retain the saved music and available pictures. Update native retry/completion checks to compare the requested revision and relevant music/visual inputs, rather than only options.

Use an idempotency token when creating/saving so retrying after a lost response cannot create duplicate Cinema items. Preserve dates and the saved programme's identity during ordinary edits. Explicit picture refresh remains available independently of soundtrack editing.

**8. Deliver as four connected steps**

1. **Prove import and replay fidelity.** Read-only checks for a Roon playlist, multi-disc album, live queue with repeats, and a queue longer than 150 tracks. Verify complete counts, metadata and session isolation. Establish the supported soundtrack size and document any Core limitation.
2. **Build the common draft and save contract.** Source adapters, stable track occurrences, migration, capability checks, atomic music/title saves, revision handling, and isolated selection browsing. Keep the existing AI creation path working through the new draft.
3. **Ship the complete editing journey.** Create Cinema on all required entry points, Music editor, Add music picker, removal/undo, Album artwork default, and reopening saved music for further edits. Implement the same behavior on iPhone, iPad and TV with appropriate input controls.
4. **Verify the whole flow.** Exercise import → reorder → add → save → reopen → replay, plus slow/failing imports, background picture work, concurrent edits and playback independence. Update the Cinema documentation with the resulting behavior and measured limits.

Required acceptance examples:

- Create Cinema directly from an album and a Roon playlist without changing currently playing music.
- Capture the selected room's queue, including the current track exactly once and preserving intentional repeats. Queue events arriving during editing cannot replace the draft.
- Import a collection beyond the current page/track limits completely, or clearly identify the supported selection before saving.
- Move the final track to the beginning, add two tracks and an album, remove one occurrence of a repeat, save, restart the app, and see exactly the same list.
- Replay preserves the edited order and chosen recordings; ensure the room's shuffle state cannot silently defeat an explicit play of the saved order. Use isolated playback fixtures, followed by a separately controlled hardware check.
- A music-only edit performs no picture research and sends no playback/queue mutation commands. Pictures and their position remain available.
- Saved personal photos survive music edits; no photo reimport or new sharing behavior is introduced.
- Network failure retains the draft; a retry does not duplicate the item; a stale picture job or another device cannot overwrite newer music.
- VoiceOver users can add, move and remove tracks without dragging; TV users can complete the same flow with the remote and predictable focus.

Planning was grounded in the current native source, companion bridge source, existing Cinema screenshots and the Roon API references above. No simulator, live playback, generation or implementation tests were run for this planning task.
