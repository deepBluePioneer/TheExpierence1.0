# Events and Hazards

## CityTrial place design (flexible core)

- **Core loop (flexible)**
  - CityTrial is primarily a **free-roam environment** where a group of teleported players ride their machines around a shared city map.
  - Players collect **stat patches**, experience **random hazards**, and explore while the environment changes dynamically over time.
- **Services**
  - `CityTrialMatchService` (server): manages match lifecycle, objectives, timers, completion, and rewards.
  - `CityTrialStateService` + `Replica`: mirrors match state (timer, current objective, team scores) to clients.
  - `CityTrialRewardService`: grants post-match rewards by invoking `ProfileService` on the hub profile.
- **Controllers**
  - `CityTrialHUDController`: Fusion HUD with timer, objectives, team scores, minimap/waypoints.
  - `CityTrialInputController`: built on `Packages/Input.lua` for movement abilities, interactions, and any mode-specific controls.
- **World logic**
  - Use `CustomPackages/ZoneRoot` for checkpoints, event trigger regions, safe zones.
  - Use `CustomPackages/BehaviorTree` for any **NPCs or AI-driven vehicles** in the city.
  - Use `CustomPackages/FastCastFolder` and `Packages/partcache.lua` for projectiles/effects if the mode involves shooting or skillshots.
  - Use `CustomPackages/Particles` and `CustomPackages/Splines` for **visual feedback and motion paths**.

### Random events and dynamic environment

- **Event types**
  - Environmental changes: rain, fog, wind, time-of-day shifts, or lighting changes that affect visibility/feel but not necessarily stats.
  - Hazard events: falling meteors, shockwaves, temporary hazards on the track, or damaging zones that players must avoid.
- **Event scheduler**
  - A `CityTrialEventService` manages a pool of event types and schedules them at random or semi-random intervals during a session, using `Packages/timer.lua` and optionally promises for sequencing.
  - Events are announced to clients via a Replica or Knit events (e.g. current event name, time remaining, any special rules).
- **Damage and safety**
  - Hazards apply damage to machines/players through `CityTrialMachineService`:
    - Meteors and projectiles use `FastCastFolder` + `partcache.lua` and call into the machine service on hit.
    - Area hazards use `ZoneRoot` to detect players and tick damage over time while they remain in the zone.
  - On death:
    - Player loses health to zero and is respawned at a safe point on their current machine, usually **keeping their patches and stats** unless a different rule is chosen.
- **Visuals and feedback**
  - Use `CustomPackages/Particles` heavily for meteor trails, impact explosions, rain, and ambient effects.
  - Use `Shake.lua` for small camera shakes on impacts, nearby explosions, or large environmental events.
  - Fusion HUD (CityTrial) shows active event name/icon and any temporary modifiers (e.g. Meteor Shower, Heavy Rain).
