# Data and Progression

## Data, progression, and economy

- **Profile structure**
  - Hub and CityTrial share a **single profile schema** (currencies, XP/levels, owned items, cosmetics, best scores/records).
  - Schema lives in a `ProfileConfig` module under `CustomPackages/ProfileService` or `src/ReplicatedStorage`.
- **Earning and spending**
  - CityTrial matches award **currency and/or XP** based on performance.
  - Hub shop spends those currencies on items/cosmetics that reflect both in hub and CityTrial (e.g. skins, titles, trails).
- **Replication**
  - `Replica` instances hold **player-facing state** (current currency, equipped items, rank) so all UIs (hub and CityTrial) can render instantly.

### DataStore strategy

- **Profiles via ProfileService wrapper**
  - All persistent player data uses the existing `CustomPackages/ProfileService` wrapper on top of Roblox `DataStoreService`, rather than raw DataStore calls scattered through the codebase.
  - One primary profile store (e.g. `"PlayerProfile"`) keyed by `userId` contains the shared schema used by both hub and CityTrial.
  - ProfileService handles retries, session locking, and release-on-leave, reducing the risk of data loss or race conditions.
- **Leaderboards and aggregate stats**
  - Long-term leaderboards (e.g. best CityTrial time/score) use an `OrderedDataStore` separate from the main profile store, updated only at safe points (like match end) from `CityTrialMatchService` / `CityTrialRewardService`.
  - `HubLeaderboardService` reads from this ordered store with caching and rate limiting to respect DataStore budgets.
- **Direct DataStore access policy**
  - Game services should not call `DataStoreService` directly; they should go through:
    - `ProfileService` for per-player data.
    - A small, well-defined leaderboard/data aggregation module for global stats.
  - This keeps all persistence logic centralized, easier to audit, and safer to evolve.

### Core data & architecture APIs

- **Profile service (hub + CityTrial, via `CustomPackages/ProfileService`)**
  - `HubProfileService:GetProfile(player) -> profileTable | nil`
  - `HubProfileService:GetCurrency(player) -> number`
  - `HubProfileService:AddCurrency(player, amount: number) -> ()`
  - `HubProfileService:CanAfford(player, cost: number) -> boolean`
  - `HubProfileService:ApplyPurchase(player, itemId: string) -> (success: boolean, reason: string?)`
- **Replica wrappers**
  - Server:
    - `ReplicaService.CreatePlayerReplica(player, initialStateTable) -> replica`
    - `replica:Set(key: string, value: any)`
    - `replica:Write(function(state) ... end)`
  - Client:
    - `ReplicaService.OnReplicaCreated(kind: string, callback(replica))`
    - `replica:Get(key: string) -> any`
    - `replica:Observe(key: string, callback(newValue))`

## Profile schema versioning and migration

### Version field

- The profile schema includes a top-level `schemaVersion: number` field (e.g. starting at `1`).
- `ProfileConfig.lua` exports both the current schema version and a `DEFAULT_PROFILE` template used for new players.

### Migration functions

- `ProfileConfig.lua` also exports a `Migrations` table: an ordered list of functions that transform a profile from version N to version N+1.
- Example:

```lua
ProfileConfig.Migrations = {
    [1] = function(profile)
        profile.ownedTrails = profile.ownedTrails or {}
        profile.schemaVersion = 2
    end,
    [2] = function(profile)
        profile.matchHistory = profile.matchHistory or {}
        profile.schemaVersion = 3
    end,
}
```

### Migration flow

- When `HubProfileService` (or `CityTrialPlayerService`) loads a profile via `ProfileService`, it immediately checks `profile.schemaVersion` against `ProfileConfig.CURRENT_VERSION`.
- If the profile version is behind, it runs each migration function in order until the version matches current.
- Migrations run synchronously before the Replica is created, so the client never sees stale schema.
- If `schemaVersion` is missing (very old profile or first-time player), treat as version 0 and run all migrations.
- After migration, the profile is marked dirty so `ProfileService` saves the updated schema on the next save cycle.

### Safety

- Migrations must be **additive only** (add fields, set defaults) -- never remove fields in a migration since old servers might still be running the previous version during a rolling deploy.
- Each migration is idempotent: running it twice produces the same result.
- If a migration fails (unexpected data), log an error and do not proceed -- show the player an error screen rather than corrupting their data.

## XP and leveling system

### XP earning

- XP is awarded at the end of each CityTrial match via `CityTrialRewardService`, based on the reward formula (see below).
- XP is also awarded for specific in-hub actions (future): daily login bonus, first match of the day, achievement completion.

### XP-to-level curve

- Levels start at 1 with 0 XP. The XP required for each level follows a gentle exponential curve:
  - `xpForLevel(n) = floor(100 * n ^ 1.5)`
  - Level 2 = 283 XP, Level 5 = 1,118 XP, Level 10 = 3,162 XP, Level 20 = 8,944 XP, Level 50 = 35,355 XP.
- Stored in `ProfileConfig.lua` as a function or lookup table.
- No level cap initially (soft cap at a very high level where XP requirements become impractical).

### What levels unlock

- Machine unlocks: certain machines require a minimum level (e.g. Falcon at level 5, Titan at level 10).
- Shop items: some items are level-gated (shown as locked with "Requires Level X" in the shop UI).
- Cosmetic tiers: trail effects, titles, or color variants unlock at milestone levels (10, 20, 50, etc.).
- Leaderboard eligibility: players below a minimum level (e.g. level 3) are excluded from the global leaderboard to prevent smurf accounts.

### Profile fields

- `xp: number` -- total accumulated XP.
- `level: number` -- current level (derived from XP, but cached for quick reads).
- On XP grant, `HubProfileService:AddXP(player, amount)` recalculates the level and fires a level-up event if it changed. The Replica updates and `HubHUDController` shows a level-up toast.

## Reward formulas

### CityTrial match rewards

`CityTrialRewardService` computes rewards at match end using the following factors:

- **Base reward**: every player who completes a match earns a flat base amount (e.g. 50 currency, 100 XP) regardless of performance. This prevents zero-reward matches and encourages participation.
- **Patch bonus**: `patchReward = totalPatchesCollected * 2` (currency) and `totalPatchesCollected * 5` (XP). Encourages active exploration.
- **Survival bonus**: `survivalReward = (timeAliveSeconds / matchDurationSeconds) * 30` (currency) and `* 80` (XP). Rewards staying alive and avoiding hazards.
- **Event survival bonus**: `eventBonus = eventsSurvived * 10` (currency) and `* 25` (XP). Extra reward for being present during hazard events and not dying.
- **Death penalty**: each death reduces the survival bonus by a percentage (e.g. -15% per death, floored at 0). Does not reduce base or patch rewards.
- **Total**: `totalCurrency = base + patchReward + survivalReward + eventBonus`, `totalXP = baseXP + patchXP + survivalXP + eventXP`.

### Formulas are config-driven

- All multipliers and base values live in `GameConfig.lua` (e.g. `GameConfig.rewards.baseCurrency`, `GameConfig.rewards.patchCurrencyMultiplier`, etc.) so they can be tuned without code changes.
- The iris debug panel can optionally include a "Reward Preview" section for testing reward calculations with mock inputs during Studio playtesting.

### Leaderboard scoring

- The primary leaderboard metric is **total XP** (career progression).
- Secondary leaderboards can track: best single-match patch count, best survival time, total matches completed.
- Written to `OrderedDataStore` via `CityTrialRewardService` at match end, respecting DataStore rate limits.
