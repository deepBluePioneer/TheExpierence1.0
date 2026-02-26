# Packages and Cleanup

## Use of existing packages (summary)

- `**CustomPackages`**
  - `ProfileService`: Persistent data for both hub and CityTrial.
  - `Replica`: Shared replicated state (stats, inventory, queue status, match state).
  - `ZoneRoot`: Zones for queues, shops, triggers, checkpoints.
  - `TeleportQueue`: Batched, reliable teleportation to CityTrial.
  - `FusionRoot`: All major HUD and menu UIs (leaderboards, shop, queue HUD, match HUD).
  - `BehaviorTree`, `FastCastFolder`, `Particles`, `Splines`, `CustomCamera`: Used where appropriate for AI, projectiles, visual polish, and camera work.
- `**Packages` (Wally)**
  - `Knit.lua`: Core pattern for services/controllers in both hub and CityTrial.
  - `Signal.lua` + `Trove.lua`: Events and cleanup.
  - `Input.lua`: Player input abstraction for all machine controls (throttle, steer, boost, drift) across keyboard, gamepad, and mobile.
  - `promise.lua` + `timer.lua`: Async flows, delays, and scheduling (e.g. queue timers, match countdowns).
  - `TableUtil.lua`, `Shake.lua`, `partcache.lua`: Utility, camera feedback, performant part reuse.
  - `Sequent.lua`: Priority-ordered, serial, cancellable signal. Use for the damage pipeline (defense decorators/invulnerability can cancel or reduce damage at high priority before it reaches health), input action priority (boost vs drift overlap resolution), and event announcements where listeners can react or cancel in priority order.
  - `iris.lua`: ImGui-style debug UI. Use for real-time tuning panels (machine stats, event frequency, patch deltas) during Studio playtesting. Not shipped to production; gated behind `RunService:IsStudio()`. See **Iris real-time vehicle debug panel** section below for full implementation details.
  - `imgizmo.lua`: 3D gizmo rendering. Use for visualizing spawn points, zone boundaries, raycasts, and collision shapes in Studio. Not shipped to production.
- **Quenty `node_modules`**
  - `@quenty/remoting` and `@quenty/promise` if we need more structured remote APIs or promise operators beyond Knit/Replica.
  - `@quenty/rx` / `@quenty/rxsignal` for complex reactive flows (e.g. derived UI signals).
  - `@quenty/timesyncservice` for tight time synchronization between hub/CityTrial and clients (important for trials and races).

### Promises and Trove/Maid usage

- **Promises (`Packages/promise.lua` and/or `@quenty/promise`)**
  - Use to structure multi-step async flows without callback nesting, for example:
    - Teleport pipeline: `startCountdown -> teleport -> handleResult` as a promise chain with retry/backoff logic.
    - Match setup: `loadConfig -> preloadSmallAssetSet -> beginCountdown`.
    - Reward + leaderboard updates: `applyRewards -> updateOrderedDataStore -> notifyClient`.
  - Prefer a single promise implementation per flow (either Sleitnick or Quenty) to avoid mixing types in the same chain.
- **Trove / Maid-style cleanup**
  - Use `Trove` (and, where appropriate, any Maid-style utility available in the dependencies) to group resources that must be cleaned up together:
    - **Per-player Trove/Maid** in hub and CityTrial:
      - Replica observers, input bindings, ZoneRoot connections, temporary UI instances tied to that player.
      - Destroy on `PlayerRemoving` or when the player leaves a mode/queue.
    - **Per-teleporter Trove/Maid**:
      - Owns queue timers (`timer.lua` handles), ZoneRoot events, and any analytics/log connections for that teleporter.
      - Destroy when the teleporter is disabled or on server shutdown, ensuring no stray timers or connections remain.
    - **Per-match Trove/Maid** in CityTrial:
      - Owns match timers (join/ready/countdown/match duration), match Replica instances, and player/zone connections.
      - Destroy when the match ends to fully clean up the session before starting a new one.
  - This ensures lifecycle management is explicit and avoids leaks from long-lived services keeping old connections around.
