# Iris Real-Time Vehicle Debug Panel

An iris (ImGui-style) debug window for CityTrial that lets developers adjust all vehicle physics parameters and base stats in real time during Studio playtesting, without restarting the session.

### Architecture

- `MachinePhysicsConfig` (new shared module in `ReplicatedStorage`) holds all physics constants in a single table. Both `MachineController` (reads each frame) and the iris panel (writes on slider change) reference this table, so slider changes take effect instantly.
- `IrisDebugPanelController` (new Knit controller in `CityTrialControllers/`) builds the iris window. It gets the iris reference via `Knit.GetController("irisInitController"):GetIris()`.
- Entire panel is gated behind `RunService:IsStudio()` -- no-op in production.

### MachinePhysicsConfig module

New file: `src/ReplicatedStorage/MachinePhysicsConfig.lua`

Extracts the hardcoded locals from `MachineController:SetupMachine` (currently lines 80-103 of `DungeonControllers/MachineController.lua`) into a shared table:

```lua
local config = {
    maxSpeed       = 150,
    thrust         = 8000,
    dragFactor     = 8,
    turnSpeed      = 80,    -- degrees; converted to radians at use site
    pitchSpeed     = 60,
    rollSpeed      = 30,
    gravityTarget  = 196.2,
    gravityLerpTime = 2.5,
    maxBoostCharge = 3,
    boostThrust    = 30000,
    boostDecay     = 6,
    groundOffset   = 3,
    searchDistance  = 5,
}
return config
```

`MachineController:SetupMachine` is then refactored to read from this table each frame instead of local variables.

### IrisDebugPanelController

New file: `src/StarterPlayerScripts/ClientControllers/CityTrialControllers/IrisDebugPanelController.lua`

- In `KnitStart`, early-return if `not RunService:IsStudio()`.
- Gets iris via `Knit.GetController("irisInitController"):GetIris()`.
- Creates an `Iris.State` for every config key, initialized from `MachinePhysicsConfig`.
- Connects to the iris render loop (`Iris:Connect(function() ... end)`) and builds a window with collapsible sections:

**Window: "Vehicle Tuning"**

| Section | Widgets | Config keys |
|---------|---------|-------------|
| Movement | `SliderNum` (0-500) maxSpeed, `DragNum` (0-50000) thrust, `SliderNum` (0-50) dragFactor, `SliderNum` (0-180 deg) turnSpeed / pitchSpeed / rollSpeed | `maxSpeed`, `thrust`, `dragFactor`, `turnSpeed`, `pitchSpeed`, `rollSpeed` |
| Boost | `SliderNum` (0-10) maxBoostCharge, `DragNum` (0-100000) boostThrust, `SliderNum` (0-20) boostDecay | `maxBoostCharge`, `boostThrust`, `boostDecay` |
| Gravity / Ground | `SliderNum` (0-500) gravityTarget, `SliderNum` (0-10) gravityLerpTime, `SliderNum` (0-20) groundOffset, `SliderNum` (0-30) searchDistance | `gravityTarget`, `gravityLerpTime`, `groundOffset`, `searchDistance` |
| Base Stats | One `SliderNum` (0-200) per stat from `StatsModule.Abilities`: HP, TopSpeed, Boost, Charge, Turn, Offense, Defense, Weight, Glide | Writes to `StatsModule.Abilities[key].Default` |
| Actions | `Button` "Reset to Defaults" -- restores all states to original values | all |
|         | `Button` "Print Config" -- prints the current config table to Output so values can be copy-pasted back into code | all |

After each slider change, the controller writes the state value back into `MachinePhysicsConfig[key]` (and `StatsModule.Abilities[key].Default` for base stats). Since `MachineController` reads the config table every `RenderStepped`, changes are reflected on the next frame.

### Wiring into MachineController

In `MachineController:SetupMachine`, replace the hardcoded locals with reads from the shared config:

```lua
local PhysicsConfig = require(ReplicatedStorage.MachinePhysicsConfig)
-- inside RenderStepped callback:
local maxSpeed = PhysicsConfig.maxSpeed
local thrust   = PhysicsConfig.thrust
local dragFactor = PhysicsConfig.dragFactor
-- ... etc for all values
```

### Optional: imgizmo integration

Use `imgizmo.lua` alongside the panel to visualize the ground sensor raycast distance, collision bounds, and boost vector direction in 3D space. Also gated behind `RunService:IsStudio()`.
