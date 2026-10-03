# Roblox Air Ride Machine System

Luau modules ready to copy into a Roblox place. Behavior mirrors the KAR decomp maps under `NA/docs/`.

## Install in Studio

1. Create folders / instances to match this tree:

```text
ReplicatedStorage
  MachineSystem          (Folder)
    MachineTypes         (ModuleScript)  ← MachineTypes.lua
    MachineStates        (ModuleScript)
    MachineStats         (ModuleScript)
    GroundProbe          (ModuleScript)
    Physics              (ModuleScript)
    StateMachine         (ModuleScript)
    MachineController    (ModuleScript)
    HitboxKnockback      (ModuleScript)
    Mount                (ModuleScript)
    CameraChase          (ModuleScript)
  MachineRemotes         (Folder — auto-created by MachineService if missing)

ServerScriptService
  MachineService         (Script)  ← MachineService.lua

StarterPlayer
  StarterPlayerScripts
    MachineClient        (LocalScript)
    MachineCameraClient  (LocalScript)
```

2. Paste each `.lua` file’s contents into the matching Script/ModuleScript (name without `.lua`).

3. Build a machine `Model` in Workspace:
   - **PrimaryPart = Seat** (or `VehicleSeat`) named e.g. `Seat`
   - Tag with CollectionService: **`AirRideMachine`**
   - Attribute `MachineId` (string, optional)
   - Unanchor the seat; weld other visual parts to it
   - Touch-sit or ProximityPrompt both work — mount is detected via **`Seat.Occupant`**

4. Play: walk onto the seat (or use **Ride** prompt). Standing/jumping off dismounts automatically.

## Controls

| Input | Action |
|-------|--------|
| W/S or Left Stick Y | Forward / brake-ish |
| A/D or Left Stick X | Steer |
| Hold Space / A / LMB | Charge (scrub speed) |
| Release charge | Boost |
| F / B / X (or jump off seat) | Dismount |
| Mouse / Right Stick | Orbit camera while riding |

## Notes

- Server owns physics (`AssemblyLinearVelocity` on the Seat PrimaryPart); client sends input + runs chase cam.
- **`VehicleSeat` throttle is disabled** (`MaxSpeed/Torque/TurnSpeed = 0`) — custom KAR-style state machine still drives motion.
- Tune feel in `MachineStats.Default`.
- Knockback uses invisible `HeadOnHitbox` when speed ≥ `HeadOnSpeedMin`.

## Decomp references

- `NA/docs/MachineRiderMovementMap.md`
- `NA/docs/MachineMountCameraAndStates.md`
- `NA/docs/RobloxMachineImplementationPlan.md`
