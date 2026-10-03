# Project status

**Prepared source snapshot:** `0.1.0-alpha.1`, 2026-10-03.

This is a playable experimental client connected to the real game. It is suitable for technical enthusiasts who can follow the source setup instructions and help test supported versions. A broad public release and a portable compiled installer are still future work.

## Implemented

| Area | Current behavior |
| --- | --- |
| Campaign | FTL runs its normal campaign, events, difficulty, combat rules, audio and saves |
| Ships | Dynamic local layouts, extruded hull presentation, rooms, weapon mounts, opposing bows in combat and stable movable encounter placement |
| HUD | Original native HUD follows the headset; native enemy HUD region is removed in gameplay; hand screen and pointer draw above it |
| Navigation | Available actions only; actual sector map appears above/ahead of the pilot room and faces the viewer |
| Menus/dialogs | Main menus remain 2D; native shop/ship windows and event choices float in the encounter; BUY/SELL panels are retained |
| Crew | Native positions/tasks/selection, animated procedural race models, grab preview and native move orders; occupied crew face the viewer |
| Targeting | Weapon and beam room targeting, plus native mind-control, teleporter and hacking target routing |
| Systems | Installed-system shortcuts, modifier support and a System Power page using native allocation rules |
| Doors | Open/closed, locked, damaged/hacked state and thin tier-dependent armor driven by native strength |
| Combat visuals | Shields/super shields, weapon charge strips/pips, native firing/impact/projectile paths and enemy hull bar using locally imported vanilla art |
| Drones | Distinct procedural space/interior families with deployment/power state and placement by native render space |
| Hazards | Room fire/breach tiles and surrounding asteroid, sun, nebula/storm and pulsar presentations |
| Input | Steam Frame actions, generic fallback profiles, controller infographic, action wheel and QWERTY rename keyboard |
| Lifecycle | Isolated game copy, fingerprinted hooks, separate `hs_ftlvr_` saves, pre-launch backup and graceful save/exit |

## Verification recorded during development

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
| Automated tests | Latest source revision passed 27 Python tests and seven Godot suites before this packaging task |
| Desktop graphics | Vulkan rendering and model/UI inspection checked on RTX 4060 Ti 8 GB |
| Save handling | Normal combined launch/exit and preservation of backed-up campaign data checked |
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
- A source setup is supplied; compiled client distribution, export packaging and an end-user installer are not yet validated.
- Python uses pinned Frida/Capstone and minimum Pillow/NumPy versions. Other combinations need testing.

## Useful next tests

Start with the supported setup. Report the exact game/loader/client versions, controller interaction profile, whether the problem occurs in VR or desktop, and steps to reproduce. For performance, distinguish stale Tactical textures from low headset frame rate. Use the [issue forms](../.github/ISSUE_TEMPLATE/) and follow [CONTRIBUTING.md](../CONTRIBUTING.md).
