# Project status

**Prepared source snapshot:** `0.1.0-alpha.1`, with source refinements through 2026-10-05 described below.

This is a playable experimental client connected to the real game. It is suitable for technical enthusiasts who can follow the source setup instructions and help test supported versions. A broad public release and a portable compiled installer are still future work.

## Implemented

| Area | Current behavior |
| --- | --- |
| Campaign | FTL runs its normal campaign, events, difficulty, combat rules, audio and saves |
| Ships | Dynamic local layouts, extruded hull presentation, rooms, weapon mounts, opposing bows in combat and stable movable encounter placement |
| HUD | Compact original status/crew panel follows the headset first at a fixed readable size; lower strip removed; clamps 5 cm above the transformed hull/shield only when its movement would intersect the ship; full main menus and results remain head-relative |
| Navigation | Available actions only; actual sector map appears above/ahead of the pilot room and faces the viewer |
| Menus/dialogs | Main menus and defeat/victory results retain the complete native 2D view; results clear the tabletop presentation; in-run shop/ship, pause-menu and Options windows appear only above the ship; event choices float in the encounter; BUY/SELL panels are retained |
| Crew | Native positions/tasks/selection, animated procedural race models, grab preview and native move orders; occupied crew face the viewer |
| Targeting | Native weapon room targeting and freely placed beam endpoints across the enemy deck/gaps; persistent player-owned numbered locks with red/yellow autofire colors, actual beam direction and flak spread radius; native mind-control, teleporter and hacking target routing |
| Systems | Dpad Up and a Navigation button open System Power; native capped reactor availability, storm loss and battery availability remain separate |
| Doors | Open/closed, locked, damaged/hacked state and thin tier-dependent armor driven by native strength |
| Combat visuals | Native charged/super shields and shutdown, native cloaking flag, separate artillery mounts, weapon charge strips/pips, native firing/impact paths, forward-moving missed shots and one hit point per enemy hull pip |
| Drones | Distinct procedural space/interior families and Combat/Beam/Defense Mk II hardware; deployment/power state, native render-space placement and visible muzzle shots with native progress/outcomes |
| Hazards | Room fire and cross-shaped breach tiles, oxygen-dependent air wisps, surrounding asteroid/sun/nebula/storm/pulsar presentations and native jump star stretch along the ship bow with arrival reset |
| Room feedback | Native role icons and permission-aware condition colors; no floor health/status bars or counters; normal sensor fog still applies |
| Input | Steam Frame right Pause/Menu pauses and left View hides/shows the controller panel; generic fallback profiles, illustrated Help, equipment-name/family/ammo wheel defaulting to weapons/drones, and QWERTY rename keyboard |
| Lifecycle | Isolated game copy, fingerprinted hooks, separate `hs_ftlvr_` saves, pre-launch backup and graceful save/exit |

## Verification recorded during development

### Latest combat, results and controller corrections — 2026-10-05

This batch corrects the enemy hull scale to one pip per native hit point; snapshots and renders artillery factories separately from regular weapon slots; uses native shield charge/shutdown and ship cloaking state; keeps missed shots progressing forward; and accepts beam endpoints on the enemy deck plane, including gaps between rooms. The native GameOver window selects the complete 2D result screen and clears tabletop ships, effects and interaction surfaces. The HUD collision clearance is 5 cm. Right Pause/Menu pauses; left View hides or restores the controller panel.

The supplemental HUD pass also suppresses `CombatControl::RenderTarget`, while the normal capture retains original target graphics. Native result-window detection is read-only and comes from fingerprint-validated `CommandGui`/`GameOver`/`FocusWindow` structure probes. Existing installations must refresh hooks as described in [Installation step 4](INSTALLATION.md#4-resolve-the-local-executable-hooks).

Current source passes **46 Python tests and twelve Godot suites**: eight headless suites plus graphical Vulkan UI, controller UI, frame transport and ship-status rendering. Five recorded native ship layouts keep every tested hull/keel corner inside the shield volume. GPU hull fixtures show exactly eight lit pips for both 8/15 and 8/22 hull. A five-frame missed-shot fixture progresses forward and clears with zero invented impacts.

Fresh copied-profile native checks find 4/3/2 artillery factories across the Flagship phases, with powered/firing state and enemy-owned first-phase shot origins. Actual first-phase native cloaking is observed. Every phase's snapshot shield center/radii exactly matches `Ship::GetBaseEllipse`; no geometry-center change is required. The shield correction propagates native shutdown and includes shutdown in the cached presentation state. A private call to the real native Victory function produces complete credits/result state with `end_screen=true`, `capture_full_screen=true`, `blocking=true` and no stale floating panel. The native result PNG was inspected; this is controlled integration evidence, not a completed campaign.

Native beam placement passes through the production release sequence: button-up followed by FTL's native confirmation click. The factory retains both freely placed off-center/gap points, in its reversed native endpoint order, with at most 0.00003 native-pixel error. Its native charge transition then consumes those targets into a queued shot. The newly equipped private fixture did not release a live beam projectile, so native beam sweep/damage campaign coverage remains open.

The Vulkan native-Victory presentation was inspected and passed with the full result screen and tabletop cleanup. A fresh native defeat check also passed: the full capture remained opaque, its Vulkan presentation was inspected, and the actual main-menu reset reported `ready=false`, `ui_mode=menu`, `end_screen=false`, `panel_open=false`. The native bridge exited with code 0 and no errors.

Live native beam projectile/sweep/damage and missed-shot outcomes remain unverified. Newly equipped private factories and the original saved missile/burst factories accumulated queued shots without emitting live projectiles in this QA session. The accepted aim/queue and rendered forward-miss fixtures establish their specific behavior; they do not establish those live outcomes.

Production archive/settings and the `ftlvr` save prefix are restored. Development and both standalone folders pass setup, SteamVR readiness and desktop Vulkan wrapper launch/exit with code 0, clean logs and disconnected error-free bridges. All four campaign hashes remain unchanged after final launches; both executable fingerprints, active/source Lua, regenerated hooks and absence of private QA events are verified. The matching 127-file source-only package passes publication checks with zero failures/warnings. Local source folders are updated; the verified source snapshot is recorded in Git history. Game assets/runtime/saves remain excluded and license notices are unchanged.

No physical Steam Frame test has been performed for this revision. These desktop/preflight checks do not establish physical controller coverage or stereo performance. Earlier checks below establish their recorded revisions only; complete campaign coverage and actual native beam/miss outcomes remain open.

### Preceding targeting, jump and drone refinements

The source now renders the player's native placed target state as numbered room locks, retaining autofire color, both beam endpoints and native flak radius. Marks remain attached through pause and encounter placement changes; missing targets, destroyed receivers and ended encounters remove them. Only player-owned weapon targets supply these marks. Jump stretch follows the transformed player ship bow and the native `jumping` flag; map opening/FTL charging do not start it. Arrival dialogs reset the sky even while a native jump flag is still clearing. Every wheel opening defaults to weapons/drones, with event choices retaining their separate context.

Procedural drone geometry has distinct family silhouettes and Combat/Beam/Defense Mk II variants. Positive native drone IDs attach shots to the visible muzzle in the drone's current render space; an ambiguous negative ID falls back to its native point at drone height. Bullets preserve their launch point while the drone continues orbiting, and continuing beam sweeps remain attached to the emitter. Native projectile presence, progress, pause and outcomes remain authoritative. The HUD's intruder-warning mask is scoped to its warning region and preserves glyphs, faint shadow/fringe coverage and neighboring controls while making the backdrop transparent.

The combined Python suite passed **44 tests** and **eleven Godot suites** passed, including graphical Vulkan UI/controller/frame checks. Target-lock, jump-star and drone gallery/laser/beam fixtures were rendered and inspected on the RTX 4060 Ti. Drone fixtures produced no invented impacts. Twelve actual native intruder-warning blink captures retained all 1,458 glyph pixels while correcting faint shadow coverage; the normal native HUD frame was unchanged.

A fresh disposable copied profile verified actual normal targeting, native target clearing and autofire. An ordinary click on a connected beacon produced native `jumping=true` through snapshot sequences 96–134, then the arrival dialog at sequence 135; fuel decreased by one. The bridge exited cleanly with no errors. Production archive/settings were restored, and all four campaign hashes plus both executable fingerprints remain unchanged. These are native/desktop checks. Physical Steam Frame comfort and stereo performance remain to test; earlier native evidence below belongs to its recorded revision.

Both standalone folders pass setup checks and their desktop Vulkan launch/exit wrappers; VR preflight passes. The development copy also passes its desktop launch/exit after refreshing an older local extraction manifest. The matching 125-file source-only package passes publication checks with zero failures or warnings. Runtime dependencies, game assets, saves and private QA fixtures remain excluded, and license notices are unchanged.

Existing installations must rerun [Installation step 5](INSTALLATION.md#5-extract-local-presentation-assets) with the current `tools/extract_ftl.py` against their original owned archive. It imports the eight normal/yellow placed reticle PNGs for weapon slots 1–4 into ignored local data. Game artwork is not included in this source release.

### Preceding HUD clearance and menu correction

HUD collision clearance is **8 cm**, reduced by 6 cm while preserving headset-following priority and the ship/shield intersection guard. Separate native pause-menu and Options draw methods are suppressed only during the supplemental HUD pass; the original capture still supplies their complete floating panels. In-run panel ownership also takes priority over a simultaneous native menu flag. Initial and hangar menus keep their full headset screen.

That revision passed **40 Python tests** and focused **Vulkan HUD-layout/input checks** on the RTX 4060 Ti. Native before/after captures from a separate QA profile verified Ship, pause-menu and Options panels: duplicate HUD pixels were absent after the fix and world-panel content was retained. These are desktop/native capture checks; physical Steam Frame comfort and stereo performance still need the maintainer's playtest.

The updated prepared folder passed `RUN-VR.cmd --smoke`, and the GitHub Desktop checkout passed `RUN-FTL-VR.cmd --smoke`: Vulkan desktop rendering, clean client logs, no bridge errors and disconnected bridges after graceful exit. Both folders passed `CHECK-SETUP.cmd`; VR launch `--check` passed separately. Production archive/settings were restored, hooks refreshed and all four campaign hashes verified again after both launches. Private QA fixtures are absent. The matching 120-file source package passed publication checks with no failures or warnings. These checks do not exercise the physical headset.

Existing installations must rerun [Installation step 4](INSTALLATION.md#4-resolve-the-local-executable-hooks), which now also resolves neighboring `MenuScreen.zhl` and `OptionsScreen.zhl` signatures. The launcher rejects older hook files before starting the game.

### Preceding HUD, wheel and launch corrections

The gameplay HUD uses a headset-relative pose whenever it has room. Collision checks include the transformed hull/shield envelope and the panel's swept movement, so looking down cannot carry it through the ship. The wheel now handles empty native drone lists without losing equipped weapon entries. Room-floor bars and counters are removed. Launcher corrections expose failures and keep runtime files local.

That revision passed **38 Python tests and nine Godot suites** in the prepared `FTL-Tabletop-VR` folder. The suites include native empty-drone-list normalization, defensive wheel parsing, headset-relative HUD placement/collision checks and removal of room-floor bars. UI, controller and frame-transport suites used actual GPU rendering on the RTX 4060 Ti.

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
| Automated tests | Current 46 Python tests and twelve Godot suites pass; eight headless plus four graphical Vulkan suites |
| Desktop graphics | Vulkan rendering and model/UI inspection checked on RTX 4060 Ti 8 GB |
| Save handling | October 5 production restoration and final standalone launch/exit checks preserve all four campaign hashes and both executable fingerprints |
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
