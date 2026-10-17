# Drone Yard VR

A native VR wave shooter for Meta Quest, rebuilt from the WebXR *Drone Yard* prototype in
Godot 4.4 with OpenXR. All drones, guns, props and maps are real 3D models, and the drones play
their own skeletal and keyframed animations.

**Install:** sideload `release/DroneYardVR.apk` (Quest 2, Quest 3, Quest Pro) with SideQuest or
`adb install -r release/DroneYardVR.apk`. It shows up under *Library → Unknown Sources*.
Without a headset the same project runs on desktop with mouse and keyboard.

## What's in it

- **3 maps**: *Drone Yard* (concrete depot), *Red Outpost* (Mars colony), *Lunar Hangar*
  (moon base under a starfield). You pick one by shooting its panel in the menu.
- **6 drone types**, each with its own model and animation set:

  | Drone | Model | Animations it uses | Behaviour |
  |---|---|---|---|
  | Seeker | Sci-Fi Essentials *EyeDrone* | Idle, Look, Charging, Attack, Hit, **BackFlip** | Fast skirmisher; back-flips out of your line of fire |
  | Rotor Bomb | *BiCopter* (rotor animations authored in Blender) | Hover, Arm, Dash, Hit | Revs up, then dives along a curved path and explodes; sometimes pulls out of the dive as a feint |
  | Stinger | GDQuest *BeeBot* | Idle, spit_attack, head_movement, power_off | Zig-zags and spits fans of acid |
  | Sentinel | *Recon drone* (animations authored in Blender) | Idle, Charge, Fire, Hit | Sniper. Its laser trails you, so step off the line before it fires. Moves to a new perch after every shot |
  | Carrier | Sci-Fi Essentials *Trilobite* | Hanging, AttackAuto, Look, Hit, TurnOff | Slow tank whose heavy orbs you can shoot down |
  | Warden (boss, every 5th wave) | *Trilobite*, scaled up | same | Bursts, ring volleys, summons bombers |

- **Unpredictable AI**: every drone rolls its own personality (aggression, jitter, range, dodge
  skill), drifts on a noise field, picks its next move by weighted chance (flank, strafe, hold,
  attack, feint), comes in from behind you more often than from the front, and dodges when it
  notices your gun pointed at it. Some drones spawn as elites: swift, shielded or volatile.
- **Upgrades**: between waves an armory terminal offers random upgrades bought with credits from
  kills: damage, fire rate, magazine, reload speed, armor, regen, weak-point crits, barrier cells,
  pickup magnet and **Overclock** (slow time). It also sells 3 extra guns: the Hammer .50
  revolver, the VK Carbine (full auto) and the Longshot rail sniper, which pierces drones.
- Dual-wielded guns with keyframed recoil and reload animations, a laser sight, haptics,
  a wrist HUD, positional audio, weak-point crits and drops (health, credits, overclock charge).

## Controls

| Quest | Action |
|---|---|
| Trigger | Fire (hold for auto) |
| Left stick | Move |
| Right stick | Snap turn 30° |
| A / X | Reload (or point the gun at the floor) |
| B / Y | Swap weapon |
| Grip | Overclock, once you've bought it |
| Menu | Pause |
| Your body | Duck and lean behind cover |

Desktop: mouse aim, click to fire, WASD, Shift sprint, C crouch, R reload, Q swap, E overclock,
P/Esc pause.

## Building the APK

Requirements: Godot 4.4.1 with export templates, JDK 17, the Android SDK (platform 34,
build-tools 34.0.0) and a keystore.

```sh
# one time: point Godot at the SDK/JDK (Editor Settings → Export → Android) and install the
# Android build template (creates ./android, ignored by git)
godot --headless --install-android-build-template --export-release Quest build/DroneYardVR.apk

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=<alias>
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<password>
godot --headless --export-release Quest build/DroneYardVR.apk
```

The Quest export preset uses a Gradle build with the bundled
[Godot OpenXR Vendors](https://github.com/GodotVR/godot_openxr_vendors) plugin (Meta loader,
VR intent category, Quest 2/3/Pro support).

### Dev tools

`tools/` is excluded from exports. Run a scripted desktop playthrough that saves screenshots to
`build/shots/`:

```sh
godot --path . --xr-mode off -- --tool=autotest
```

## Project layout

```
scripts/main.gd          game loop, menus, waves, armory, XR session
scripts/player.gd        XR rig, locomotion, health, wrist HUD, desktop fallback
scripts/gun.gd           weapons: hitscan, pierce, recoil/reload animations, laser
scripts/drone.gd         drone models, animation driving, AI
scripts/map_builder.gd   the three arenas, built from kit models
scripts/game_data.gd     tables for weapons, drones, upgrades and maps; save file
scripts/projectiles.gd   pooled drone rounds
scripts/fx.gd, sfx.gd    particles and audio pools
assets/                  models, textures, sounds, fonts (see CREDITS.md)
```
