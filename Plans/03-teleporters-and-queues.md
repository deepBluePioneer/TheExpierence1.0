# Teleporters and Queues

## Matchmaking and teleport flow

- **Queueing in the hub**
  - Player enters a teleporter zone (detected via `ZoneRoot`).
  - `HubQueueService` uses `CustomPackages/TeleportQueue` to add the player to a queue for CityTrial.
  - When enough players accumulate or a timer expires, the queue forms a session and calls TeleportService to the CityTrial place.
- **Session in CityTrial**
  - On join, a `CityTrialPlayerService` loads the player profile via `ProfileService` (or receives key info from teleport data) and binds to `Replica` state.
  - `CityTrialMatchService` starts the match when enough players are present or after a warmup timer.
  - At match end, rewards are calculated and written via `ProfileService`, and players are optionally teleported back to the hub.
- **Rejoining the hub**
  - After CityTrial, players return to the hub spawn region.
  - Hub UI updates automatically via `Replica` to show new currency, rank, and updated leaderboard results.

### Teleporter queue + countdown APIs

- **Server: `HubQueueService` (uses `TeleportQueue`, `ZoneRoot`, `timer.lua`)**
  - `HubQueueService:PlayerEnteredTeleporter(player, teleporterId: string) -> ()`
  - `HubQueueService:PlayerLeftTeleporter(player, teleporterId: string) -> ()`
  - `HubQueueService:GetTeleporterConfig(teleporterId: string) -> { placeId, minPlayers, maxPlayers, maxWaitTimeSeconds, countdownDuration }`
  - `HubQueueService:GetQueueState(teleporterId: string) -> { state, queueSize, countdownEndTime? }`
  - Events:
    - `HubQueueService.TeleporterStateChanged:Signal(teleporterId, newStateTable)`
    - `HubQueueService.PlayerQueued:Signal(player, teleporterId)`
    - `HubQueueService.PlayerDequeued:Signal(player, teleporterId)`
- **Queue Replica shape**
  - `state: "WAITING" | "COUNTDOWN" | "TELEPORTING"`
  - `queueSize: number`
  - `countdownEndTime: number | nil`
  - `lastError: string | nil`
- **Client: `HubQueueController`**
  - Observes queue Replica to render Fusion UI for:
    - Waiting state (`X / minPlayers`)
    - Countdown (`secondsRemaining` from `countdownEndTime`)
    - Teleporting / errors
  - Optional remotes:
    - `HubQueueController.JoinQueue(teleporterId: string):RemoteFunction() -> (success: boolean, reason: string?)`
    - `HubQueueController.LeaveQueue(teleporterId: string):RemoteFunction() -> ()`
- **Internal edge-case helpers on `HubQueueService`**
  - `HubQueueService:_StartCountdown(teleporterId: string) -> ()`
  - `HubQueueService:_CancelCountdown(teleporterId: string, reason: string?) -> ()`
  - `HubQueueService:_AttemptTeleport(teleporterId: string) -> ()`
  - `HubQueueService:_HandleTeleportFailure(teleporterId: string, players: {Player}, errorCode: string) -> ()`

#### Batching behaviour (fixed size + time-based) and zone edge cases

- **Fixed-size + time-based batching**
  - Each teleporter uses `minPlayers`, `maxPlayers`, and `maxWaitTimeSeconds`:
    - When a player first joins an empty queue, start a **max wait timer** using `Packages/timer.lua`.
    - If `queueSize` reaches `maxPlayers` before the timer ends, call `_AttemptTeleport` immediately.
    - If the timer expires and `queueSize >= minPlayers`, call `_AttemptTeleport`; otherwise call `_CancelCountdown` and keep players queued or reset to `WAITING`.
- **Zone entry/exit with edge cases**
  - `PlayerEnteredTeleporter` is fired from `ZoneRoot` when a player enters the teleporter zone:
    - Add the player to the queue (if not already queued) and possibly start the countdown/max wait timer.
  - `PlayerLeftTeleporter` is fired when a player exits the zone:
    - Remove them from the queue; if `state == "COUNTDOWN"` and `queueSize < minPlayers`, call `_CancelCountdown`.
  - On `Players.PlayerRemoving`, remove the player from all teleporter queues and recompute state (potentially cancelling countdowns).
  - On TeleportService failures, `_HandleTeleportFailure` re-queues affected players (if still present) and sets `lastError` in the queue Replica so clients can show a retry message.
  - Simple debouncing (per-player timestamp) is used to ignore extremely rapid enter/leave spam events from `ZoneRoot`.

#### Additional teleporter considerations

- **Teleport data schema**
  - Define a small, versioned `TeleportData` table passed to CityTrial:
    - `{ teleporterId, partyId, seed, modeSettings, profileSnapshotVersion }`
  - CityTrial services read this once on join to know which teleporter/mode spawned the session and to safely evolve the schema over time.
- **Rejoin and failure UX**
  - On teleport failure (per-player or whole batch), `_HandleTeleportFailure`:
    - Re-queues affected players (if still in hub) and sets a user-facing `lastError` in the Replica (e.g. Teleport failed, retrying soon).
    - Ensures profiles are not left in an intermediate state (no double rewards, no lost rewards).
  - Optionally add a simple flow for reconnecting players: if they rejoin the hub shortly after a CityTrial disconnect, they can be returned to a safe hub state and requeue.
- **AFK and griefing control**
  - Before teleporting, re-validate each queued player:
    - Still in the zone or still explicitly opted into the queue.
    - Passes any AFK checks or minimum requirements (level, progression) if implemented.
  - If a player is flagged AFK or fails validation, remove them from `batchPlayers` and keep them out of the teleport call; if this drops below `minPlayers`, cancel and restart logic as needed.
- **Spawn safety in CityTrial**
  - Standardize CityTrial spawn logic so all teleported players land in:
    - A `SpawnZone` (via `ZoneRoot`) or well-defined spawn points.
    - A safe area where they cannot immediately fall or die while assets are loading.
  - Optionally gate combat/interaction until players leave this spawn zone or a warmup timer completes.
- **Rate limiting and capacity/backoff**
  - Track recent teleport attempts per teleporter to avoid spamming TeleportService.
  - If a teleport fails due to capacity/throttling, `_HandleTeleportFailure`:
    - Applies a short cooldown before `_StartCountdown` or new batches are allowed.
    - Updates `lastError` so clients can show a CityTrial busy or similar message.
- **Party/friend grouping (future-proofing)**
  - Extend queue entries to optionally include a `partyId` so friends/parties can be kept together.
  - Ensure `_AttemptTeleport` and `TeleportData` preserve party grouping, even if players entered the teleporter at slightly different times.
- **Analytics and logging**
  - Add lightweight logging/metrics hooks inside `HubQueueService`:
    - Queue join/leave counts per teleporter.
    - Teleport success/failure counts and error codes.
    - Average wait time and fill rate for batches.
  - Use these metrics to tune `minPlayers`, `maxPlayers`, and `maxWaitTimeSeconds` without changing the high-level flow.

## Server allocation strategy

### Reserved servers (default)

- Each teleport batch from the hub gets its own **reserved server** via `TeleportService:ReserveServer(cityTrialPlaceId)`.
- The reserved server access code is passed to all players in the batch via `TeleportService:TeleportToPrivateServer()`.
- This guarantees match isolation: one batch = one match = one server.

### Server lifecycle

- The CityTrial server runs exactly **one match** per lifecycle:
  1. Players arrive, readiness handshake, match starts.
  2. Match plays out, results, rewards.
  3. Players teleport back to hub.
  4. Server cleans up all Troves and shuts down (no players remain, Roblox auto-closes the server).
- No sequential matches on the same server. This avoids state leakage between matches and simplifies cleanup.

### Failure handling

- **ReserveServer fails** (rare): `HubQueueService:_HandleTeleportFailure` catches the error, re-queues players, sets `lastError` in the queue Replica, and applies a short cooldown (e.g. 5-10s) before retrying.
- **TeleportToPrivateServer fails per-player**: Roblox may fail to teleport individual players. The CityTrial server handles this via the join grace timer -- if not all expected players arrive, the match starts with whoever is present (or cancels if below `minPlayers`).
- **Server capacity**: since each match gets a reserved server, capacity is not shared. The only limit is Roblox's global server creation rate, handled by the rate limiting / backoff logic in the teleporter considerations section.

### Future: multi-match servers (optional)

- If player volume grows large enough, consider allowing one server to host sequential matches (new batch arrives after the previous match ends + cleanup). This requires careful state reset and is deferred as a future optimization.
