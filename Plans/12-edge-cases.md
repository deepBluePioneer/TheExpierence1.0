# Edge Cases

## Edge cases (comprehensive)

### UI state edge cases

#### Hub UI state

- **Replica not yet available when HUD mounts**: `HubHUDController` might initialize before the profile Replica exists. Use a "wait for Replica" pattern (e.g. `ReplicaService.OnReplicaCreated`) so Fusion state objects never read nil. Show the loading overlay until the Replica is confirmed.
- **Multiple panels open at once**: Define a UI priority/exclusivity rule: only one major panel (shop, garage, leaderboard) open at a time. Opening one force-closes the other. Managed by a shared `activePanel` Fusion state in the controller layer.
- **Shop/garage open when teleport starts**: When the queue transitions to `TELEPORTING`, force-close all hub panels and disable UI interaction. The teleporting overlay takes full priority.
- **Currency changes while shop is open**: Shop UI must react to Replica changes live (buttons re-evaluate affordability immediately on every Replica update, not just on panel open).
- **Queue UI flicker on rapid zone entry/exit**: Queue UI mount/dismiss should use a small debounce or transition delay so it does not flash on every rapid `ZoneRoot` event.
- **Profile load failure after partial HUD mount**: If profile load fails partway (timeout), any partially mounted Fusion components must be torn down cleanly via Trove and replaced with the error screen.

#### CityTrial UI state

- **Match phase transition flicker**: Use a single Fusion `Computed` or state value that drives which HUD "mode" is shown (`LOBBY`, `COUNTDOWN`, `IN_PROGRESS`, `ENDED`, `RESULTS`). Transitions between modes are atomic so there is never a frame where two overlays are visible simultaneously.
- **Death overlay + event warning overlap**: Define UI layer priorities: event banners always render in the top bar, respawn overlay renders in the center. Neither blocks the other. Optionally dim the event banner during the death state for clarity.
- **Match ends while player is dead/respawning**: If match phase transitions to `ENDED` during the respawn timer, cancel the respawn flow immediately and skip straight to the results overlay. Do not show "Respawning in X..." when the match is already over.
- **Boost meter desync (client-predicted mode)**: Client drains the boost meter locally, but the server may reject or correct. Add a small smoothing/lerp on the boost meter bar so server corrections do not look jarring (e.g. lerp toward the authoritative value over 0.1-0.2s).
- **Event banner stacking**: When multiple events are active simultaneously (e.g. rain + meteor shower), either stack banners vertically (max 2-3 visible) or show the most dangerous one prominently with a secondary indicator for the other.
- **HUD visibility during results screen**: When the results overlay appears, hide or fade out gameplay HUD elements (patch counts, health bar, boost meter, event banners) via a Fusion state flag tied to match phase. Do not destroy them; just toggle visibility so they can be re-shown if needed.
- **Countdown UI for late joiners**: A player joining during the match start countdown must immediately read the current `countdownEndTime` from Replica and render the correct remaining time, not start from the full countdown duration.
- **Teleport failure after results**: If the teleport-back fails after the results timer finishes, replace the stale results screen with a clear "Return to Hub" button state rather than leaving a finished timer on screen.

#### Cross-cutting UI state

- **Fusion state cleanup on teleport/disconnect**: When controllers are destroyed (player teleports or leaves), all Fusion `Value`, `Computed`, and `Observer` objects must be cleaned up via the player/match Trove. Orphaned Fusion objects cause errors or memory leaks.
- **Replica observer cleanup**: If a Replica is destroyed (match ends, player leaves) but a Fusion observer is still listening, it will error. All observers must be added to a Trove and destroyed before or alongside the Replica they observe.
- **Screen safe area**: All HUD elements (especially on mobile) must respect Roblox `ScreenInsets` / safe area so they are not hidden behind device notches or system UI.
- **Input focus conflicts**: When a text input is focused (e.g. Roblox chat), machine input and UI buttons should not respond. `MachineController` and `Input.lua` bindings should check `UserInputService:GetFocusedTextBox()` before processing machine controls.

### Hub / profile edge cases

- **Profile fails to load** (DataStore outage, session lock conflict):
  - Gate all profile-dependent features (shop, queue, leaderboard submission) behind a "profile loaded" check.
  - Show a Fusion "Loading data..." or "Data unavailable, please rejoin" state in the HUD until the profile is ready.
  - Do not allow the player to enter a teleporter queue or open the shop until the profile is confirmed loaded.
- **Double-spend / concurrent purchases**:
  - `HubShopService:Purchase` uses a per-player lock (simple flag or promise-based mutex) so two rapid requests cannot both pass the `CanAfford` check before currency is deducted.
- **Player in multiple queues**:
  - If a player enters a second teleporter zone while already queued at another, auto-dequeue them from the first teleporter before adding to the new one.
- **Player leaves mid-shop-transaction**:
  - `ProfileService` release-on-leave ensures the profile is saved. Purchase logic must deduct currency before granting the item (or use an atomic write) so partial states are impossible.

### Hub / server lifecycle edge cases

- **Server shutdown while players are queued**:
  - `game:BindToClose` handler cancels all active queue countdowns, releases all profiles via `ProfileService`, and prevents new teleport batches from starting.
  - Players see a brief "Server shutting down" message via Fusion HUD.
- **Roblox DataStore throttling**:
  - Both `ProfileService` and `OrderedDataStore` leaderboard writes must respect rate limits. Batch or debounce leaderboard updates rather than writing per-player per-match immediately.

### CityTrial join edge cases

- **Malformed or outdated TeleportData**:
  - `CityTrialMatchService:InitFromTeleportData` validates the schema version and handles missing/corrupt fields gracefully (use fallback defaults or teleport the player back to hub with an error message).
- **Stale arrivals** (player arrives at a CityTrial server that already has a match `IN_PROGRESS` or `ENDED`):
  - Either allow spectating, hold the player for a potential next session, or teleport them back to the hub immediately.
  - Do not crash or leave the player in limbo.

### CityTrial gameplay edge cases

- **Patch pickup race condition** (two players touch the same patch on the same server tick):
  - Server uses a simple "first claim wins" lock per pickup instance. Once claimed, the pickup is marked consumed and subsequent touch events for it are ignored.
- **Machine stuck in geometry**:
  - Detect if a machine has not moved for N seconds despite receiving input. Offer a respawn/unstick option or auto-respawn at the nearest safe point after a timeout.
- **Overlapping hazard events**:
  - Define rules in `CityTrialEventService`: max concurrent active events, minimum cooldown between events, or allow stacking with combined (but capped) damage.
- **Event spawns on player (unfair instant damage)**:
  - Meteors and area hazards must have a brief warning indicator before impact (ground shadow, audio cue, screen flash) so players have a chance to react.
  - On respawn, grant a short invulnerability grace window (e.g. 2-3 seconds) so the player is not immediately killed again.
- **Exploit mitigation**:
  - Server validates patch collection (player must be within proximity of the pickup).
  - Server performs sanity checks on machine speed against `effectiveStats.topSpeed` (reject impossible values).
  - All damage application is server-authoritative; clients only display effects.

### CityTrial end-of-session edge cases

- **ProfileService save fails during reward grant**:
  - Wrap reward writes in a promise with retry. If still failing after retries, queue pending rewards in a secondary DataStore key so they can be applied on the player's next session load.
  - Never lose earned rewards due to a transient DataStore error.
- **Player disconnects before results screen**:
  - Rewards are written to `ProfileService` **before** the results Replica is pushed and before the teleport is initiated. Even if the player leaves early, their profile is already updated.
- **Results Replica not received before teleport**:
  - The results countdown must be long enough for Replica replication to complete. Server should not trigger TeleportService until it confirms the results Replica update has been sent.

### Cross-cutting edge cases

- `**game:BindToClose` handling (both hub and CityTrial)**:
  - Save all profiles, cancel active timers/queues, and destroy all Troves cleanly within the ~30-second shutdown window.
  - In CityTrial, attempt to grant pending rewards before releasing profiles.
- **Memory / instance leaks**:
  - Per-match and per-player Troves must be destroyed even in unexpected flows (errors in match logic, unexpected disconnects).
  - Wrap critical service paths in `pcall` or promise `:finally` blocks so Trove cleanup always runs.
- **Decorator chain integrity**:
  - When rebuilding the stat decorator chain after patch/event changes, always start from a fresh `BaseMachineStats` to avoid stale decorator references accumulating.
