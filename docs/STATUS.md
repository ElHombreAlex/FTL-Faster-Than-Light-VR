# Project status

**Prepared source snapshot:** `0.1.0-alpha.1`, 2026-10-03, with subsequent gameplay refinements described below.

This is a playable experimental client connected to the real game. It is suitable for technical enthusiasts who can follow the source setup instructions and help test supported versions. A broad public release and a portable compiled installer are still future work.

## Implemented

| Area | Current behavior |
| --- | --- |
| Campaign | FTL runs its normal campaign, events, difficulty, combat rules, audio and saves |
| Ships | Dynamic local layouts, extruded hull presentation, rooms, weapon mounts, opposing bows in combat and stable movable encounter placement |
| HUD | Compact original status/crew panel follows the headset first at a fixed readable size; lower strip removed; clamps above the transformed hull/shield only when its movement would intersect the ship; full main menus remain head-relative |
| Navigation | Available actions only; actual sector map appears above/ahead of the pilot room and faces the viewer |
| Menus/dialogs | Main menus remain 2D; native shop/ship windows and event choices float in the encounter; BUY/SELL panels are retained |
| Crew | Native positions/tasks/selection, animated procedural race models, grab preview and native move orders; occupied crew face the viewer |
| Targeting | Weapon and beam room targeting, plus native mind-control, teleporter and hacking target routing |
| Systems | Dpad Up and a Navigation button open System Power; native capped reactor availability, storm loss and battery availability remain separate |
| Doors | Open/closed, locked, damaged/hacked state and thin tier-dependent armor driven by native strength |
| Combat visuals | Shields/super shields, weapon charge strips/pips, native firing/impact/projectile paths, native miss cues/pass-by presentation and enemy hull bar using locally imported vanilla art |
| Drones | Distinct procedural space/interior families with deployment/power state and placement by native render space |
| Hazards | Room fire and cross-shaped breach tiles, oxygen-dependent air wisps and surrounding asteroid, sun, nebula/storm and pulsar presentations |
| Room feedback | Native role icons and permission-aware condition colors; no floor health/status bars or counters; normal sensor fog still applies |
| Input | Steam Frame actions, generic fallback profiles, controller infographic, equipment-name/family/ammo action wheel and QWERTY rename keyboard |
| Lifecycle | Isolated game copy, fingerprinted hooks, separate `hs_ftlvr_` saves, pre-launch backup and graceful save/exit |

## Verification recorded during development

### Latest HUD, wheel and launch corrections

The gameplay HUD uses a headset-relative pose whenever it has room. Collision checks include the transformed hull/shield envelope and the panel's swept movement, so looking down cannot carry it through the ship. The wheel now handles empty native drone lists without losing equipped weapon entries. Room-floor bars and counters are removed. Launcher corrections expose failures and keep runtime files local.

The current source passed **38 Python tests and nine Godot suites** in the prepared `FTL-Tabletop-VR` folder. The suites include native empty-drone-list normalization, defensive wheel parsing, headset-relative HUD placement/collision checks and removal of room-floor bars. UI, controller and frame-transport suites used actual GPU rendering on the RTX 4060 Ti.

Actual `RUN-DESKTOP.cmd --smoke` and `RUN-VR.cmd --smoke` launched the isolated FTL process and Godot client, then exited successfully with clean client logs and no bridge errors. The GitHub Desktop checkout's `RUN-FTL-VR.cmd --smoke` alias passed the same combined launch/exit check. These smoke tests use desktop rendering; VR preflight passed separately. A copied save profile opened the current campaign, paused it and supplied actual Artemis Missiles and Burst Laser Mark II entries to a GPU-rendered wheel check; the drone-equipment collection was normalized to a list and bridge errors remained empty.

All four original campaign hashes remained unchanged; the original save prefix/settings were restored and Steam/lab executable fingerprints remained unchanged. These checks establish the desktop-wrapper and native wheel paths. Physical Steam Frame comfort, stereo performance and clean-machine setup remain unverified for these changes.

### Preceding gameplay refinements

This revision introduced a compact spatial gameplay HUD retaining native status/crew controls, direct Power access, localized equipment wheel metadata, storm-aware free-power presentation, native miss feedback, cross-shaped breaches and per-room system condition presentation. Enemy system condition colors follow native information permissions. Detailed floor bars introduced in that revision have since been removed.

That revision passed **27 Python tests and nine Godot suites**, including HUD-layout and damage-visual checks. Headless and Vulkan HUD checks covered crop/picking, fixed-size placement and transformed-envelope clearance; damage checks covered condition visibility, misses and breaches. Controller UI checks included localized equipment/ammo, bounded names, unchanged-content redraws and capped power/battery separation.

Actual native ion-storm state was checked: **8 installed / 4 usable reactor bars, 4 raw available / 0 usable free**. Native equipped Burst Laser/Artemis titles and ammo metadata, enemy system damage/repair and breach tiles were checked. The real missed flag/event path was verified using a private native projectile and forced `Evasion.MISS`; this verifies integration, not random evasion rates.

Production combined Vulkan launch/save/exit smoke passed: exit 0, clean client log, no bridge errors and a disconnected bridge. All four campaign file hashes match the fresh pre-test backup; source and packed Lua match, QA fixtures are absent, both original/lab executable hashes remain unchanged and final process inventory shows no owned FTL/Godot processes. Physical Steam Frame comfort and complete campaigns remain open.

| Check | Evidence and limits |
| --- | --- |
| Real-game startup | Main menu, hangar, new game, event choices and combined client/bridge startup checked |
| Crew and doors | Native crew selection, room movement, station return, modifiers and upgraded door state checked |
| Navigation | Actual map opening, beacon selection, fuel consumption and new event checked |
| Weapons/combat | Player laser/missile targeting, enemy fire, shield/hull impact and native hull damage checked |
| Systems | Power operations for installed powerable systems, native mind control and teleportation effects checked |
| Hacking | Enemy room targeting accepted; attachment/effect completion remains unverified |
| UI | Native HUD during Tactical/map/store/event/ship modes; enemy-region transparency; BUY/SELL content; rename input and original fonts checked across development revisions |
| Drones | Native equipment/special/global lists deduplicated; actual combat and interior battle-drone state inspected |
| Automated tests | Current prepared source passed 38 Python tests and nine Godot suites; UI/controller/transport checks used actual GPU rendering |
| Desktop graphics | Vulkan rendering and model/UI inspection checked on RTX 4060 Ti 8 GB |
| Save handling | Current desktop-wrapper launch/exit and copied-profile native checks preserved all four original campaign hashes |
| Steam Frame play | Maintainer confirmed playability and substantial partial runs; latest changes need further hardware coverage |

The automated suite uses synthetic fixtures for many edge cases. A passing test does not establish that every race, layout, weapon, drone, hazard or boss encounter has been exercised in a campaign.

## Performance: what the measurements mean

- The old Tactical texture path delivered about 6.30 updates/second in its measured consumer case.
- The raw RGBA path reached 29.09 in the same consumer case and about 27.89–28.60 in complete desktop scene checks, including an asteroid scene.
- Tactical uses 960×540 capture with a 30 Hz target. Jump/maps and native windows keep 1280×720. The independent native HUD targets 10 Hz.
- These are capture/texture-delivery measurements. They are **not stereo headset FPS, motion-to-photon latency or SteamVR frame-time measurements**.

## Known limitations and remaining work

### Before a wider player release

1. Test setup from this standalone repository on a clean Windows machine.
2. Measure physical Steam Frame readability, hand-screen steadiness, pointer latency and stereo frame pacing after the latest changes.
3. Complete campaign coverage: Flagship phases, ship layouts/races, boarding, cloaking, beams/bombs, drones and hazard combinations.
4. Verify hacking-drone arrival, attachment and resulting effect end to end.
5. Check long-session transition/capture recovery and graceful shutdown under failure conditions.

### Compatibility and polish

- The preparer accepts only the fingerprinted Steam Windows 1.6.14 input and official rollback to 1.6.9. Unknown executables are rejected deliberately.
- GOG PKG extraction works; the complete GOG executable/loader route is not verified.
- Other headsets/controller profiles, Linux/macOS and FTL overhaul combinations are not verified.
- Native game rules remain authoritative. VR hazard animation and some projectile/drone presentations are approximations, rather than complete reproductions of their 2D appearance or timing.
- HUD follows the headset until a collision would occur; a raised or oversized table can then push the panel above the ship. Retest that transition physically when moving/resizing the encounter.
- A source setup is supplied; compiled client distribution, export packaging and an end-user installer are not yet validated.
- Python uses pinned Frida/Capstone and minimum Pillow/NumPy versions. Other combinations need testing.

## Useful next tests

Start with the supported setup. Report the exact game/loader/client versions, controller interaction profile, whether the problem occurs in VR or desktop, and steps to reproduce. For performance, distinguish stale Tactical textures from low headset frame rate. Use the [issue forms](../.github/ISSUE_TEMPLATE/) and follow [CONTRIBUTING.md](../CONTRIBUTING.md).
