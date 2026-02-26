# Patches and Pickups

### Machines and stat patches (Kirby-style)

- **Base machine stats (persistent unlocks)**
  - Extend `MachinesConfig` (shared, in `ReplicatedStorage`) so each `machineId` defines base stats:
    - `topSpeed`, `acceleration`, `handling`, `boostPower`, `boostChargeRate`, `weight`, `offroadPenalty`, etc.
  - Add `selectedMachineId` to the player profile schema via `ProfileService`, chosen in the hub (e.g. via a garage/loadout UI).
  - CityTrial reads `selectedMachineId` for each player and uses `MachinesConfig` to determine which machine to spawn.
- **Session stats per player (CityTrial only)**
  - On match start, `CityTrialMachineService` builds `currentStats` for each player:
    - `currentStats = deepCopy(baseStats)` stored in match session state and in a machine Replica field (e.g. `replica:Set("stats", currentStats)`).
  - All patch effects modify **only** these session stats; base stats in the profile remain unchanged.
- **Patch types and effects**
  - Define a `PatchesConfig` module enumerating patch types like:
    - Speed, acceleration, handling, boost, defense/weight, glide/offroad, etc.
  - Each patch type provides stat deltas or multipliers and optional per-stat caps to prevent machines from becoming uncontrollably strong.
  - A helper `RecalculateStats(baseStats, patchCounts, PatchesConfig) -> currentStats` computes current stats from base stats and the player's collected patches.
- **Patch pickups in the city map**
  - Patches are **physical parts** that spawn in the air above the map and fall to the ground under gravity, similar to Kirby Air Ride's item drops.
  - Use touch events on the patch part to detect machine overlap and call:
    - `CityTrialMachineService:OnPatchCollected(player, patchType) -> ()`
  - Server-side collection handler:
    - Validates the pickup (not already taken, match active, player within proximity).
    - Increments that player's `patchCounts[patchType]`.
    - Calls `RecalculateStats` and updates the machine Replica (`stats` and `patchCounts`).
    - Removes the patch part from the world (return to `partcache` pool).
    - Triggers respawn logic (see below).

#### Patch spawn mechanics

- **Spawn method**
  - `CityTrialMachineService` (or a dedicated `PatchSpawnService`) manages a pool of patch parts via `Packages/partcache.lua` for efficient reuse (no repeated `Instance.new` / `Destroy`).
  - On spawn, a patch part is retrieved from the cache, assigned a random `patchType` (weighted by `PatchesConfig.spawnWeights`), given a visual appearance (color/icon per type), and positioned at a random XZ location within the map bounds at a fixed height above the terrain (e.g. 80-120 studs above ground).
  - The part is unanchored and falls under gravity. It has `CanCollide = true` so it lands on surfaces naturally.
  - A small `BodyVelocity` or initial random horizontal velocity can be applied for slight lateral scatter.
- **Spawn position selection**
  - Define a **spawn bounds volume** (axis-aligned bounding box or a set of spawn regions) covering the playable CityTrial map area.
  - Pick a random XZ within bounds, then raycast downward from the sky to find the ground height. Spawn the patch at ground height + spawn altitude offset.
  - **Excluded zones**: maintain a list of excluded regions (out-of-bounds, kill zones, water, interior-only buildings). If the random position lands in an excluded zone, re-roll (up to a max retry count, then pick from a fallback list of known-safe positions).
- **Landing validation**
  - After a patch is spawned and falls, start a **landing timeout** (e.g. 8-10 seconds via `timer.lua`).
  - If the patch hasn't been collected and its Y position drops below the kill plane (or it leaves the map bounds), reclaim it to the cache and trigger a replacement spawn.
  - If the patch lands on a rooftop or elevated surface that is technically reachable (within the map bounds and above the kill plane), it stays -- players can reach it by using ramps, boost jumps, or glide.
  - If the patch lands on a surface flagged as unreachable (e.g. a CollisionGroup or tag `UnreachableSurface`), reclaim and respawn.
- **Visual and audio feedback on spawn**
  - When a patch appears in the sky, a brief glint/sparkle effect plays at the spawn point (visible from a distance).
  - As it falls, a faint trail (`Particles`) follows it so players can track incoming patches.
  - On landing, a small impact particle burst plays.
  - On collection, a satisfying pickup sound + particle pop + brief HUD flash for the collecting player.

#### Patch respawn rules

- **Global patch budget**
  - The map maintains a target number of active patches at all times: `PatchesConfig.targetPatchCount` (e.g. 30-50 depending on map size and player count).
  - At match start, an initial batch of patches spawns across the map (staggered over 2-3 seconds to avoid a single-frame spike).
- **Respawn on collection**
  - When a patch is collected, a **respawn timer** starts (e.g. 3-8 seconds, configurable per patch type in `PatchesConfig.respawnDelay`).
  - After the delay, a new patch spawns at a **new random position** (not the same location) to keep the map dynamic.
  - The replacement patch type is chosen by weighted random from `PatchesConfig.spawnWeights`, not necessarily the same type that was collected.
- **Respawn on loss (timeout / out-of-bounds)**
  - If a patch falls off the map or times out without being collected, it respawns immediately (no delay) since no player benefited.
- **Wave spawns (tied to events)**
  - `CityTrialEventService` can trigger bonus patch waves: e.g. "Patch Rain" event spawns 15-20 extra patches over 10 seconds on top of the normal budget, with a temporary budget increase that decays back to `targetPatchCount` as patches are collected.
- **Distribution balancing**
  - `PatchesConfig.spawnWeights` controls rarity: common patches (speed, handling) have higher weights; powerful patches (boost, defense) are rarer.
  - Optionally, a "pity" system: if a specific patch type hasn't spawned in N cycles, temporarily increase its weight.
- **Match phase rules**
  - Patches only spawn during `IN_PROGRESS` phase. During `LOBBY`/`COUNTDOWN`, no patches are on the map.
  - When the match transitions to `ENDED`, all remaining patches are reclaimed to the cache (no new spawns).

#### Patch spawn edge cases

- **Patch lands inside geometry** (clips through a thin floor or wall): use a slightly oversized collision box on the patch part so it rests reliably on surfaces. If after landing the patch's position is detected inside a solid (raycast upward hits a surface within 1 stud), reclaim and respawn.
- **Two patches land in the exact same spot**: acceptable but unlikely given random XZ distribution. No special handling needed; both are collectible.
- **Patch collected during fall (before landing)**: fully supported -- touch events fire while the part is falling, so a machine that jumps into a falling patch collects it mid-air.
- **Server performance with many patches**: `partcache.lua` avoids GC pressure. Patches are simple parts (no complex models). The budget cap (`targetPatchCount`) ensures a bounded number of active instances. If performance is a concern, reduce the budget or increase respawn delays.
- **Late joiner sees existing patches**: all patch parts exist in workspace and replicate normally. A late joiner sees all currently active patches as soon as their client loads the workspace.
- **Hazard destroys patches**: if a meteor or shockwave hits an area with patches, optionally destroy (reclaim) those patches and trigger immediate replacements, adding a risk/reward dynamic to hazard events.
- **Machine controller behavior**
  - `MachineController` (client) reads `stats` from the machine Replica to drive movement each frame:
    - Clamp velocity to `stats.topSpeed`, use `stats.acceleration` for throttle response, and `stats.handling` for turn rate.
    - Use `stats.boostPower` and `boostChargeRate` for boost mechanics (charging from drift/pickups, consuming during boosts).
  - Movement style aims to feel like Kirby Air Ride:
    - Player is always mounted on a machine during CityTrial; movement is vehicle-first.
    - Strong forward drive, steering-based turning, and simple but expressive physics that hug the track.

#### Example base stats per machine

Four starter machines with distinct playstyles (values are tunable via `MachinesConfig`):

- **Starter** (default, average): topSpeed=85, acceleration=6, handling=6, weight=5, boostPower=30, boostChargeRate=1.0, maxHealth=80, offroadPenalty=0.3
- **Falcon** (fast, fragile): topSpeed=120, acceleration=8, handling=5, weight=3, boostPower=40, boostChargeRate=1.5, maxHealth=60, offroadPenalty=0.4
- **Titan** (heavy, tanky): topSpeed=70, acceleration=4, handling=3, weight=10, boostPower=25, boostChargeRate=0.8, maxHealth=120, offroadPenalty=0.1
- **Nimble** (agile, balanced): topSpeed=90, acceleration=6, handling=9, weight=5, boostPower=30, boostChargeRate=1.2, maxHealth=80, offroadPenalty=0.3

Stat definitions:

- `topSpeed`: max studs/sec.
- `acceleration`: studs/sec^2 gain per frame of throttle.
- `handling`: degrees/sec turn rate.
- `weight`: knockback resistance (higher = less knockback received, more dealt).
- `boostPower`: speed bonus added during active boost.
- `boostChargeRate`: meter units gained per second (from drift or passive charge).
- `maxHealth`: starting and maximum health.
- `offroadPenalty`: speed multiplier penalty when off-road (0.0 = no penalty, 1.0 = full stop).

#### Example patch stat boosts

Each patch collected adds a fixed delta per type, with soft caps to prevent runaway stats (defined in `PatchesConfig`):

- **Speed patch**: topSpeed +5 per patch, soft cap +50 total from patches.
- **Acceleration patch**: acceleration +1 per patch, soft cap +8.
- **Handling patch**: handling +1 per patch, soft cap +8.
- **Boost patch**: boostPower +5 per patch, soft cap +40.
- **Charge patch**: boostChargeRate +0.2 per patch, soft cap +2.0.
- **Defense patch**: weight +1 and maxHealth +10 per patch, soft cap weight +8 / maxHealth +80.
- **Glide patch**: offroadPenalty -0.05 per patch, soft cap -0.3 (floor at 0.0).

Example: Starter machine + 10 Speed patches = topSpeed 85 + 50 = 135 (at cap). Falcon + 10 Speed patches = topSpeed 120 + 50 = 170 (at cap). These are starter values meant to be tuned via playtesting; the config-driven design means rebalancing only requires changing numbers in `MachinesConfig` / `PatchesConfig`.

#### HUD for patches, machine state, boost meter, and indicators

- `CityTrialHUDController` (Fusion) renders:
  - Patch icons and counts per type (mirroring Kirby City Trial's patch UI).
  - Machine bars/meters for speed and health based on Replica `stats`.
  - **Boost meter**: a gauge/bar showing current boost charge (0-100). Fills visually as `boostChargeRate` ticks; drains while boost is active. Changes color or pulses when full and ready to use. Driven by a `boostMeter` field in the machine Replica, updated by the server (or client in client-predicted mode).
  - **Invulnerability indicator**: when the player is in a post-respawn invulnerability window, show a shield icon or pulsing border on the HUD. The machine model also flashes/glows (semi-transparent blink) during this window so other players can see it too. Driven by an `invulnerable` boolean in the machine Replica, set by the server and cleared when the grace timer expires.
- Use `Particles` and `Shake.lua` when patches are picked up or boosts are activated for satisfying feedback.

#### Hazard warning indicators

- Before any hazard impacts a location, the server spawns a **warning marker** and replicates it to clients:
  - **Meteors**: a growing ground shadow (dark circle decal or part) at the impact point, appearing 1.5-2 seconds before impact. Shadow grows larger as the meteor approaches. Optional subtle audio cue (whistling/rumble) that increases in volume.
  - **Area hazards / damage zones**: a visible boundary outline or color-tinted region on the ground before it becomes active (e.g. red zone flashes for 1-2 seconds before damage starts ticking).
  - **Shockwaves / explosions**: a brief screen-edge flash or directional indicator pointing toward the source, shown ~1 second before the wave arrives.
- `CityTrialHUDController` shows a small **event warning banner** at the top of the screen (e.g. "Meteor Shower incoming!") when `CityTrialEventService` announces a new event via Replica.
- All warning visuals are managed by the match Trove so they are cleaned up when the event ends or the match ends.
- **Session-only vs persistent behavior**
  - Patches are **session-only**: they reset at the end of each match or on a new CityTrial session.
  - Base machine stats and unlocks remain purely governed by hub progression/profile data.
  - On respawn, players keep their collected patchCounts and derived stats (unless a different mode design is explicitly chosen).

#### Machine stats implementation pattern (Decorator)

- **Base component**
  - A `BaseMachineStats` provider reads immutable base stats from `MachinesConfig[machineId]`.
  - This acts as the core `IMachineStats` component with a single method: `getStats() -> statsTable`.
- **Decorators for patches and environment**
  - Each patch type (speed, accel, handling, etc.) and each temporary environment effect (e.g. rain debuff, event buff) is implemented as a **decorator** that wraps another `IMachineStats`:
    - Example: `SpeedPatchDecorator.new(innerProvider, count)` returns a provider whose `getStats()`:
      - calls `innerProvider:getStats()` to get base/effective stats,
      - applies additive/multiplicative adjustments for speed based on `count`,
      - clamps results into stat-specific min/max ranges,
      - returns the new stats table.
  - Similar decorators exist for handling, acceleration, boost, defense/weight, and environmental modifiers.
- **Composing the final stats**
  - For a given player/session, `CityTrialMachineService` builds a provider chain:
    - `provider = BaseMachineStats.new(selectedMachineId)`
    - Wrap in one decorator per active patch/effect (order chosen so the last decorator represents the most recent effect).
    - `effectiveStats = provider:getStats()` is then written into the machine Replica.
  - When patches or environment effects change, rebuild the decorator chain (or update decorator parameters) and recompute `effectiveStats`.
- **Client usage**
  - `MachineController` never mutates stats directly; it simply reads `effectiveStats` from the Replica and uses them to drive movement and boost logic.
  - This keeps machine behavior **data-driven**, easily extensible, and localized to a small set of stat/decorator modules.
