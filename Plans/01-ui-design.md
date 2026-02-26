# UI Design

### UI design language

- **Visual style: stylized / cartoony** (to match the Kirby Air Ride-inspired gameplay)
  - **Colors**: bold, saturated primary palette. Each stat/patch type has a distinct color (e.g. speed = blue, accel = orange, handling = green, boost = yellow, defense = red, glide = purple). Backgrounds use soft gradients or semi-transparent dark panels.
  - **Shapes**: rounded corners on all panels and buttons (UICornerRadius via Scale, e.g. `UDim.new(0.05, 0)` relative to element size). Pill-shaped bars for health/boost/stats. Circular icons for patches.
  - **Typography**: a single bold, rounded sans-serif font (e.g. GothamBold or a custom thick font). Large numbers for timers and countdowns. Smaller but still bold text for labels and descriptions. Font sizes use `TextScaled = true` or Scale-based `TextSize` relative to parent height.
  - **Iconography**: simple, chunky icons with thick outlines for patches, events, and machine stats. Readable at small sizes on mobile.
  - **Animations**: Fusion `Spring` or `Tween` for smooth transitions on bar fills, panel open/close, patch pickup popups, and countdown number changes. Nothing should snap; everything eases in/out.
  - **Transparency and layering**: gameplay HUD panels are semi-transparent (0.3-0.5 background transparency) so they don't fully obscure the 3D world. Full-screen overlays (results, loading, death) use a darker backdrop (0.6-0.8 transparency).
- **Sizing rule: Scale, not Offset**
  - All UI sizing and positioning must use `UDim2.fromScale()` (proportional 0-1 values) rather than `UDim2.fromOffset()` (fixed pixels). This ensures the UI scales correctly across all screen resolutions and aspect ratios (mobile, tablet, 1080p, 4K).
  - **Exception**: `UIPadding` and `UIListLayout.Padding` may use small Offset values only where a fixed gap is needed regardless of screen size (e.g. 4-8px padding between tightly packed icons). Even these should prefer Scale where possible.
  - Anchor points (`AnchorPoint`) and positions should be Scale-based (e.g. `AnchorPoint = Vector2.new(0.5, 0.5)` with `Position = UDim2.fromScale(0.5, 0.5)` for centering).
  - `UIAspectRatioConstraint` should be used on elements that must maintain a fixed aspect ratio (icons, circular buttons, machine preview viewports) so they don't stretch on different screens.
  - Use `SizeConstraint = Enum.SizeConstraint.RelativeYY` on elements that should scale uniformly based on screen height (e.g. HUD bars, buttons).
- **Hub UI layout**
  - **Always-on HUD** (top-left or top-center): currency icon + count, XP bar, machine name/icon.
  - **Panel UIs** (shop, garage, leaderboard): centered modal panels that dim the background. One panel open at a time (managed by `activePanel` state). Close button and/or click-outside-to-close.
  - **Queue UI**: appears near the bottom of the screen when in a teleporter zone. Compact bar showing queue size, countdown, and status. Slides in/out with a Fusion transition.
  - **Toasts/notifications**: small rounded banners that slide in from the top-right, auto-dismiss after 3-5 seconds (e.g. "Last CityTrial run" summary, "Machine unlocked!", purchase confirmation).
- **CityTrial HUD layout**
  - **Top bar**: match timer (center), active event banner (left of timer or below it).
  - **Bottom-left**: patch grid (icons + counts for each collected patch type, arranged in a compact grid).
  - **Bottom-right**: machine stat bars (speed, health, boost meter) stacked vertically.
  - **Center**: used only for overlays (countdown 3-2-1, "Respawning in X...", results screen). Empty during normal gameplay.
  - **Top-right**: optional minimap or directional indicators.
- **CityTrial HUD density toggle**
  - A `HUDLayout` setting stored in the player's profile (or local, via `UserSettings`) with three modes:
    - **Minimal**: only health bar, boost meter, and match timer visible. Patch counts and event banners are hidden and only flash briefly on change.
    - **Moderate** (default): health, boost, timer, patch grid, and event banner always visible. Stat bars for individual stats are hidden but can be viewed by holding a key.
    - **Full**: everything visible at once, including individual stat bars per stat, patch grid, event banner, and optional minimap/waypoints.
  - Toggle is accessible from a small gear icon on the CityTrial HUD or from a settings menu.
  - `CityTrialHUDController` reads `HUDLayout` as a Fusion state value and conditionally mounts/hides elements based on the current mode.
  - Layout changes are instant (Fusion reactivity) with a brief fade transition on toggled elements.

### Mobile UI specifics

- **Touch target sizing**
  - All interactive elements (buttons, toggles, list items) must have a minimum hit area of approximately **0.06 x 0.06 of screen height** (Scale-based, roughly equivalent to 44pt on a standard device). Smaller visual elements should have an invisible expanded hit region using a transparent outer frame sized via Scale.
  - Patch grid icons in the CityTrial HUD: `UDim2.fromScale(0.04, 0.04)` per icon with `SizeConstraint = RelativeYY` and `UIAspectRatioConstraint` (1:1), with `UIListLayout.Padding = UDim.new(0.005, 0)` between them.
- **Virtual joystick (steering)**
  - Left side of the screen: a circular virtual joystick zone sized at approximately `UDim2.fromScale(0.2, 0.2)` with `SizeConstraint = RelativeYY` for consistent sizing across resolutions.
  - Joystick appears on touch-down at the finger position (floating origin) rather than being fixed in one spot, so the player can start steering from anywhere on the left half.
  - Joystick thumb indicator tracks the finger within the radius; beyond the radius it clamps and outputs max steer.
  - `MachineInputMap` provides a `"Mobile"` binding set that reads from the virtual joystick module and maps it to `steer` (-1 to 1).
- **Right-side action buttons**
  - Right side of the screen: stacked circular buttons for **Boost** and **Drift** (and optionally **Brake**).
  - Buttons sized at `UDim2.fromScale(0.08, 0.08)` with `SizeConstraint = RelativeYY` and `UIAspectRatioConstraint` (1:1), semi-transparent, with bold icons. Positioned in the bottom-right quadrant with Scale-based spacing (`UDim.new(0.02, 0)` between buttons and from screen edges / safe area insets).
  - Throttle is automatic on mobile (always-on forward drive) to reduce the number of simultaneous touches required. Braking is an explicit button press.
- **HUD density auto-adjust**
  - On mobile devices (detected via `UserInputService.TouchEnabled` and screen size), default `HUDLayout` to **Minimal** instead of Moderate.
  - The patch grid compacts to a single row of icons with counts (no stat bar labels) to save vertical space.
  - Event banners shrink to a single-line notification bar at the top rather than a multi-line overlay.
  - The match timer and health/boost bars are repositioned to avoid overlapping with the virtual joystick and action buttons.
- **Safe area and notch handling**
  - All HUD elements are inset by `ScreenInsets` on all edges. On devices with notches or dynamic islands, the top bar shifts down and side elements shift inward.
  - The virtual joystick dead zone avoids the bottom-left system gesture area on iOS.
- **Hub mobile layout**
  - Hub panels (shop, garage, leaderboard) render as full-screen overlays on mobile (`UDim2.fromScale(1, 1)`) rather than centered modals with a dimmed background, since screen real estate is limited.
  - Scrollable lists use `ScrollingFrame` with momentum scrolling enabled for natural mobile feel.
  - Close button positioned at `UDim2.fromScale(0.92, 0.02)` with size `UDim2.fromScale(0.06, 0.06)` (`SizeConstraint = RelativeYY`, 1:1 aspect ratio) for easy dismissal.
- **Performance on low-end mobile**
  - Reduce particle counts for patch spawn/collect effects on mobile (check `UserSettings():GetService("UserGameSettings").SavedQualityLevel` or similar).
  - Consider reducing `targetPatchCount` slightly on mobile servers if the server detects a majority of mobile players (or leave this as a server-wide config and tune conservatively).

### Fusion-based UI overview

- **Hub HUD**
  - A `HubHUDController` (Knit + Fusion) renders always-on elements:
    - Currency / XP from the profile Replica.
    - Optional small status indicators (e.g. currently in queue, recent rewards).
- **Hub shop UI**
  - `HubShopController` uses Fusion to:
    - Render item lists from a `ShopConfig` module.
    - Bind buttons to `HubShopService:Purchase(itemId)` calls.
    - React to Replica updates for currency and owned items (disable/enable buttons, show Owned).
- **Hub leaderboard UI**
  - `HubLeaderboardController` (Fusion) renders list entries from `HubLeaderboardService` data:
    - Top players, values, and optionally highlighting the local player.
    - Can be opened via proximity prompts or always-visible boards.
- **Teleporter / queue UI**
  - `HubQueueController` (Fusion) observes the queue Replica:
    - Shows **waiting state** (e.g. Waiting for players: X / minPlayers).
    - Shows **countdown UI** driven by `countdownEndTime` and client-side time.
    - Shows **teleporting state** and any `lastError` messages in a non-intrusive toast or modal.
    - Optionally provides a clear Leave queue button when allowed.
- **CityTrial HUD and readiness**
  - `CityTrialHUDController` (Fusion) renders:
    - Match timer, objective text, scores, and other match state from the match Replica.
    - A pre-match **ready/loading overlay** that is shown until the client sends its Ready signal.
    - The **match start countdown** UI (e.g. 3-2-1) synchronized with the server's countdown via Replica or time sync.
  - A `CityTrialReadyController` can be a thin wrapper around Fusion state that:
    - Tracks when the client considers itself ready (game loaded, character spawned, HUD mounted).
    - Triggers the server Ready remote once Fusion UI is fully constructed.

## Loading screen during teleport

### Hub-to-CityTrial teleport screen

- When the queue transitions to `TELEPORTING`, `HubQueueController` mounts a full-screen Fusion overlay:
  - Dark semi-transparent background (`BackgroundTransparency = 0.3`).
  - Centered text: "Teleporting to City Trial..." with a spinning or pulsing loading indicator.
  - Optionally: a gameplay tip or machine silhouette rotates beneath the text.
  - The overlay persists until the client is fully teleported (Roblox handles the actual transition).
- On the CityTrial side, the client shows a similar loading overlay managed by `CityTrialReadyController` until the readiness conditions are met (game loaded, character spawned, HUD mounted). This is the same "Loading" overlay that gates the Ready signal.

### CityTrial-to-Hub return screen

- After the results countdown, `CityTrialHUDController` transitions the results overlay into a "Returning to Hub..." state with a loading indicator.
- If the teleport fails, this overlay switches to a "Return to Hub" button state (already defined in edge cases).

### Roblox default loading screen

- Consider using `ReplicatedFirst` to mount a custom loading screen that matches the game's visual style (bold, rounded, cartoony) to replace the default Roblox loading screen on initial join. This is optional but adds polish.

## Gamepad UI navigation

### Menu navigation without cursor

- When a gamepad is connected (`UserInputService.GamepadEnabled`), hub panels (shop, garage, leaderboard) switch to **focus-based navigation**:
  - D-pad or left stick moves focus between items/buttons.
  - A button confirms / selects.
  - B button closes the panel or goes back.
  - Bumpers (LB/RB) switch between tabs or categories (e.g. shop categories).
- Fusion components should support a `selected` / `focused` state that highlights the currently focused item with a border glow or scale-up animation.

### Button prompts

- When gamepad input is detected, UI buttons show gamepad glyphs instead of text labels (e.g. "A" icon instead of "Select", "B" icon instead of "Back").
- `MachineInputMap` already defines gamepad bindings for in-game controls. The same detection logic (`UserInputService:GetLastInputType()`) switches between keyboard and gamepad prompts dynamically.

### CityTrial HUD on gamepad

- The CityTrial HUD is non-interactive during gameplay (no buttons to press), so gamepad navigation is not needed during matches.
- The settings gear icon (for HUD density toggle) should be accessible via the Start/Menu button on gamepad, opening a small overlay navigable with D-pad.
