# Audio and SFX

## Audio / SFX

Sound is managed via a combination of Roblox `Sound` instances (parented to parts or `SoundService`) and client-side controllers that play/stop/crossfade audio in response to game state.

### Machine audio

- **Engine loop**: a looping `Sound` parented to the machine's `RootPart`. Pitch and volume scale with current speed (e.g. `PlaybackSpeed = 0.8 + (currentSpeed / topSpeed) * 0.6`). When idle, a low hum plays at base pitch.
- **Boost activation**: a short, punchy burst sound on boost start. While boost is active, layer a secondary high-frequency whine loop that fades in/out with boost state.
- **Boost depletion**: a brief descending tone when the boost meter empties.
- **Drift**: a tire-screech or skid loop that plays while in the `DRIFTING` state; volume scales with steering intensity.
- **Collision -- machine-to-machine**: a metallic crunch/impact sound. Volume and pitch scale with relative speed at impact. Heavier machines produce a deeper tone.
- **Collision -- machine-to-wall**: a shorter, harder impact sound. Volume scales with speed.
- **Death / destruction**: an explosion or shatter sound layered with particles.
- **Respawn**: a soft "whoosh" or chime when the machine reappears.
- **Landing**: a thud on ground contact after airborne; intensity scales with fall speed.

### Patch and pickup audio

- **Patch collect**: a bright, short chime. Optionally pitch-shifted or tinted per patch type so the player can audibly distinguish pickups (e.g. speed = high ping, defense = low thump).
- **Patch spawn (falling)**: a faint sparkle or whistle as the patch descends; audible only at close range.
- **Repair pickup**: a distinct healing/restore sound (e.g. a gentle harp strum).

### Hazard and event audio

- **Meteor warning**: a rising whistle that increases in volume and pitch as the meteor approaches. Directional (3D sound positioned at impact point).
- **Meteor impact**: a deep explosion boom + debris scatter sound.
- **Shockwave**: a rumbling bass sweep that pans across the stereo field.
- **Area hazard activation**: a crackling/electric hum for the zone boundary, with a warning chime 1-2 seconds before damage starts.
- **Rain / weather**: ambient rain loop that crossfades in when the rain event starts and out when it ends. Optional thunder cracks at random intervals.

### UI audio

- **Countdown beeps**: three short beeps (3, 2, 1) followed by a longer "GO" tone at match start.
- **Button click / hover**: subtle click for presses, faint hover sound. Consistent across all Fusion UIs.
- **Purchase confirmation**: a satisfying "cha-ching" or coin sound.
- **Queue join / leave**: a soft chime on join, a gentle dismiss sound on leave.
- **Toast / notification**: a brief pop or slide-in sound when a toast appears.
- **Results screen reveal**: a fanfare or score tally sound as rewards are displayed.

### Background music

- **Hub**: a relaxed, upbeat loop that plays continuously while in the hub. Low volume so it doesn't compete with conversations or UI.
- **CityTrial lobby/countdown**: a building, anticipatory track that ramps up during the countdown.
- **CityTrial in-progress**: an energetic, fast-paced track. Consider 2-3 variations that crossfade randomly to avoid repetition across matches.
- **CityTrial results**: a calmer, celebratory track during the results screen.
- **Crossfading**: use `TweenService` or Fusion Spring to crossfade between music tracks over 1-2 seconds on phase transitions. Never cut abruptly.

### Implementation notes

- All audio assets are stored in `SoundService` or `ReplicatedStorage` and cloned/referenced as needed.
- Machine engine sounds are 3D (`RollOffMode = InverseTapered`) so nearby machines are audible but distant ones fade out.
- UI sounds are 2D (parented to `SoundService` or a ScreenGui).
- A global `SFXVolume` and `MusicVolume` setting (stored in the player profile or local `UserSettings`) allows players to independently control sound levels. Exposed in the settings menu.
- `Packages/Trove.lua` manages sound lifecycle: per-machine sounds are added to the machine's Trove, per-match sounds to the match Trove, ensuring cleanup on death/match end/teleport.
