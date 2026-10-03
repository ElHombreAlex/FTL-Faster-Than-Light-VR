# Changelog

## HUD, wheel and launch corrections — source update, 2026-10-03

- Gameplay HUD follows the headset at a fixed readable size. It clamps above the transformed hull/shield only when its movement would intersect the ship; full menus remain head-relative.
- Weapon slots survive an empty native drone-equipment collection. The bridge normalizes optional lists and the wheel accepts empty/malformed collections safely.
- Remove all room-floor health/status bars and counters. Native room-role icons, permission-aware condition colors, fog, fire and breach effects remain.
- Launch wrappers retain failures on screen and forward command-line options. Setup finds a real Python interpreter, rejects the Windows Store alias and keeps runtime configuration, dependencies and extracted assets local and ignored by Git.

This source passed 38 Python tests and nine Godot suites in the prepared folder. The desktop and VR wrappers passed combined launch/exit in desktop smoke mode, including the GitHub Desktop checkout's FTL-VR alias. VR preflight passed; a copied campaign verified equipped weapon entries in the rendered wheel without changing the original campaign hashes. Physical headset comfort and stereo performance remain to test. See [Project status](docs/STATUS.md) for evidence and limits. Earlier test counts and native checks below refer to their respective revisions.

## Gameplay refinements — preceding source update, 2026-10-03

- Compact original status/crew HUD above the ship; the lower strip is replaced by dedicated Power/Shortcuts/wheel access while full native menus remain available.
- Dpad Up toggles System Power, with a direct System Power button on Navigation.
- Reactor free power excludes environmental cap loss; unavailable bars and battery availability are displayed separately.
- Wheel slots show localized equipped names, weapon-family silhouettes and actual ammo-cost hints, with bounded names and unchanged-content rendering.
- Native permission-aware room condition colors and detailed health bars supplement system role icons.
- Native evasion produces a short MISS cue and pass-by trajectory; breach holes use shallow black crosses with oxygen-dependent air wisps.

This revision passed 27 Python tests and nine Godot suites. Focused native storm power, localized equipment/ammo, enemy damage/repair, breach tiles and forced missed-event checks passed. Combined production Vulkan smoke passed with clean logs, no bridge errors, backed-up campaign hashes preserved and no remaining owned game/client processes; physical headset checks remained pending. Historical results below belong to previous revisions.

## 0.1.0-alpha.1 — prepared source snapshot, 2026-10-03

The first standalone community source package. This records the current prototype; it does not claim a completed public release.

### Core prototype

- Live FTL campaign connected to a Godot OpenXR tabletop presentation through Hyperspace and fingerprinted native hooks.
- Controller pointing, crew movement, weapon/system targeting, door controls, native HUD and contextual navigation.
- Floating events, complete shop/ship panels, an action wheel, illustrated controller Help and QWERTY renaming.
- A dedicated System Power page and native Shift/Ctrl support.
- Procedural crew/weapon/drone models, shields, weapon charging, room hazards and surrounding environments.
- Isolated Steam-derived lab, VR save prefix, pre-launch backups and coordinated save/exit.

### Latest gameplay revision included

- Faster Tactical delivery through reduced raw RGBA frames and independently captured native HUD.
- Full-resolution maps/windows, reused textures and crops synchronized to newly opened panels.
- Lighter FTL-style controller UI with locally imported native bitmap fonts.
- Viewer-facing occupied crew, thin upgraded doors and refined drone families.
- Original enemy hull-bar presentation lowered toward the ship.
- Jump projection anchored above/ahead of each ship's actual piloting room.

### Standalone packaging

- Portable environment/launch helpers and an example local configuration.
- Community installation, controls, architecture, troubleshooting, development and status guides.
- GitHub issue forms and Windows Python-test workflow.
- Generated assets, dependencies, configuration, game copies, captures and saves excluded from Git.
- MIT source license preserving the universal-modder notice, external dependency notices and versioned license-reference documents.

### Open verification

Clean-machine setup, latest physical headset ergonomics/frame pacing, full campaign/boss coverage, hacking attachment, the complete GOG route and additional hardware compatibility.
