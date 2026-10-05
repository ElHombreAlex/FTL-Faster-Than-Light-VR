# FTL VR

**Command your ship from a floating tabletop in VR.**

An experimental OpenXR mod for **FTL: Faster Than Light**. Walk around a miniature ship, direct crew into rooms, target an opposing ship, and use FTL's original HUD and menus with tracked controllers.

> **Playable source alpha · Windows · SteamVR · Steam Frame tested**
>
> The real FTL process runs the campaign, combat, events, saves and soundtrack. The VR client presents that live game in Godot. Bring your own copy of FTL; game files and extracted assets are not included.

## What it does

- Floating player and enemy ships with opposing bows, room interiors, visible shields and movable encounter placement.
- Compact original HUD following the headset, with 5 cm clearance above the ship when needed; upper status and crew roster, controller navigation, Tactical, shortcuts, system power and illustrated Help.
- Crew selection and drag-to-room orders, door controls, free beam endpoint placement across rooms and gaps, persistent numbered native weapon locks with autofire colors/beam direction/flak spread, and native system targeting.
- Contextual Jump/Ship/Store actions, a cockpit-anchored sector map, floating event dialogs and complete native shop/ship/Options panels displayed only above the ship during a run; complete 2D native defeat/victory results.
- An eight-slot action wheel that opens on weapons/drones each time, with localized equipped names, family/ammo hints, Shift/Ctrl shortcuts and a QWERTY VR keyboard for renaming crew and ships.
- Original procedural voxel crew, weapons and distinct drone families/Mk II variants, separate native artillery mounts, native shield/cloak state, weapon charge indicators, room-condition feedback, cross-shaped breaches and forward-moving native miss cues. Enemy hull pips each represent one hit point.
- Surrounding stars that stretch along the ship's bow during an actual native jump, plus native-state-driven asteroid, sun, nebula/storm and pulsar environments.
- A separate game copy and VR save prefix, plus a backup before each normal launch.

## Start here

| Guide | Contents |
| --- | --- |
| [Installation](docs/INSTALLATION.md) | Required downloads, local environment, isolated game preparation and first launch |
| [Controls](docs/CONTROLS.md) | Steam Frame bindings, contextual controls, modifiers and desktop inspection |
| [Project status](docs/STATUS.md) | Implemented features, verification, limitations and remaining work |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Setup failures, tracking, capture, logs and save recovery |
| [Architecture](docs/ARCHITECTURE.md) | How FTL, Hyperspace, the bridge and Godot communicate |
| [Development](docs/DEVELOPMENT.md) | Source layout, tests and profiling |
| [Contributing](CONTRIBUTING.md) | Useful reports and changes |
| [GitHub setup](docs/GITHUB_SETUP.md) | Connect this folder to your own new GitHub repository |
| [Licenses and notices](THIRD_PARTY_NOTICES.md) | MIT project source, preserved upstream notices and external dependency terms |

### Prerequisites

These are the versions used for the verified setup, rather than a promise of compatibility with newer releases.

| Component | Verified setup |
| --- | --- |
| Operating system | Windows |
| Owned game | Steam Windows FTL 1.6.14, copied and rolled back to 1.6.9 |
| Loader | Hyperspace 1.23.2 |
| Rollback | Official FTL-Version-Rollback `Steam-1.6.14.bps` |
| Mod manager | ftlman 0.7.4 |
| VR client engine | Godot 4.7.2 standard build |
| Python | 3.10 or newer, with [requirements.txt](requirements.txt) |
| VR runtime | SteamVR selected as the active OpenXR runtime |
| Headset/controllers | Steam Frame; other OpenXR profiles are present but need hardware testing |

Development and desktop checks used an **RTX 4060 Ti 8 GB and 32 GB RAM**. This is a tested configuration, not a measured minimum specification. GOG asset extraction is supported; the complete GOG executable/loader route has not been verified.

### Setup and daily launch

This is a technical source release. **SETUP.cmd prepares Python and a local configuration template; it does not install the game loader or complete the game setup.** Follow the [installation guide](docs/INSTALLATION.md) to prepare your own isolated FTL copy, resolve hooks, import local assets and fill in the configuration.

After installation:

1. Run **CHECK-SETUP.cmd** to check the configured paths and prerequisites.
2. Start SteamVR and connect the headset/controllers.
3. Run **RUN-VR.cmd**. Use **RUN-DESKTOP.cmd** for desktop inspection.
4. Close the client normally to request FTL's save-and-exit operation.

The [controls guide](docs/CONTROLS.md) explains crew movement, room targeting, the action wheel and the System Power page. The in-VR Help page includes a controller infographic.

## Current state

The October 5 correction makes each enemy hull pip equal one actual hit point, gives native artillery its own mounts and shot origins, keeps misses moving forward, and allows beam endpoints anywhere on the enemy deck plane, including gaps between rooms. Shields follow native charge/shutdown state and cloaking follows the native ship flag. Native defeat/victory results use the complete 2D screen with tabletop combat presentation cleared. Steam Frame's right Pause/Menu button pauses; left View hides or restores the controller panel. The HUD collision gap is 5 cm.

Current checks pass **46 Python tests and twelve Godot suites**, including four graphical Vulkan suites. Native copied-profile checks verify the Flagship's 4/3/2 artillery factories, actual first-phase cloaking and unchanged native shield ellipse geometry through all three phases. Native beam placement accepts exact off-center and gap endpoints through the production release/confirmation sequence and reaches the native queued-shot state. Controlled native Victory/credits and defeat checks retain the full opaque 2D screen, with inspected Vulkan tabletop cleanup; returning from defeat restores the actual main menu. These checks verify result integration rather than campaign completion. Five recorded ship layouts retain hull/keel containment inside the shield volume. Rendered hull fixtures show exactly eight lit pips for both 8/15 and 8/22 hull, and a five-frame missed-shot fixture progresses forward and clears without an invented impact.

Live native beam/miss outcomes remain unverified: tested factories queued shots without emitting live projectiles. Production state is restored. Development and both standalone setup/readiness and desktop Vulkan launch/exit checks pass with clean logs, unchanged campaign hashes and preserved executable fingerprints. The 127-file source-only package passes publication checks with zero failures/warnings. Local source folders are updated; the verified source snapshot is recorded in Git history. Physical headset testing has not been performed for this revision.

The preceding refinement displays the player's real numbered weapon target marks, red for a single volley and yellow for native autofire. Beam locks retain both native endpoints and direction; flak shows its native spread radius. Locks stay attached while the encounter is moved or paused and clear when native targets or the encounter end. Jump stars follow the player's ship bow and return to normal on arrival. Each wheel opening defaults to weapons/drones. Drone models distinguish Combat, Beam and Defense Mk II hardware; native shots leave their visible muzzles. A scoped transparency mask preserves the native intruder warning's lettering and shadow/fringe while removing its backdrop.

**Existing installations must rerun [local asset extraction](docs/INSTALLATION.md#5-extract-local-presentation-assets) with the updated `tools/extract_ftl.py` against the original owned archive.** It now imports eight placed-target reticle PNGs: slots 1–4 in normal and yellow/autofire variants. These game assets remain local and are not distributed with the source.

The maintainer has played substantial portions of runs on Steam Frame and confirmed that earlier revisions are playable. The compact gameplay HUD follows the headset first and stops 5 cm above the ship only when it would intersect the hull or shield. In-run Ship, pause-menu and Options windows appear only above the ship, without a duplicate on the headset HUD. Equipped weapon entries remain available on the wheel when no drones are installed. Room floors retain role icons and condition colors; health/status bars and counters are removed. System Power, storm-aware free power, native miss feedback and cross-shaped breaches remain available.

Core game input, capture, native state and graceful launch/exit have been verified in an isolated game. **Complete campaign coverage and measured stereo headset performance remain open.** Hacking target acceptance is verified; drone attachment/effect completion still needs encounter testing. The renderer presents hazards and some effects approximately while the original game remains authoritative.

The preceding targeting/jump/drone source passed **44 Python tests and eleven Godot suites**, with inspected Vulkan captures. A disposable copied run verified actual normal/cleared/autofire targets and a real connected-beacon jump through its arrival dialog. Twelve native intruder-warning blink captures verified transparency without losing glyphs or ordinary HUD ink. Both prepared launch folders passed setup and desktop Vulkan launch/exit checks; all four original campaign hashes and both game executable fingerprints were preserved. These results belong to that revision and do not establish physical Steam Frame comfort or stereo performance.

**Existing installations must refresh their local hooks** using [Installation step 4](docs/INSTALLATION.md#4-resolve-the-local-executable-hooks). The current resolver also needs the matching `CombatControl.zhl`, `GameOver.zhl` and `FocusWindow.zhl` signatures for isolated HUD target rendering and read-only native result-window detection.

The preceding HUD clearance/menu revision passed 40 Python tests and focused Vulkan HUD/input checks. Its native before/after captures verified that Ship, pause-menu and Options windows remain complete above the ship while their duplicate HUD pixels are absent. Both local folders passed their VR-wrapper desktop smoke launches with clean client logs and no bridge errors; setup and VR readiness checks passed separately. Campaign files remained unchanged. **Existing installations must also refresh their local hooks** using [Installation step 4](docs/INSTALLATION.md#4-resolve-the-local-executable-hooks) if they have not applied that revision.

The preceding revision passed nine Godot suites and combined desktop launch/exit checks. Physical Steam Frame comfort and stereo performance remain to test for these changes. Historical Tactical delivery reached about **28–29 updates/second in desktop scene checks**; this is texture delivery, not headset FPS. A clean installation on a different machine has not yet been tested. See [STATUS.md](docs/STATUS.md) for details.

## Repository layout

```text
bridge/             Hyperspace Lua state/events and Frida native hooks
scripts/            Godot scene, input, HUD, panels, models/effects and shaders
tools/              Extraction, preparation, launch, tests and profiling
config/             Example configuration with placeholder paths
docs/               Community guides
.github/            Issue forms and Python test workflow
project.godot       Open this source project in Godot
local_game_data/    Generated locally; ignored by Git
```

No standalone compiled release is included. Download third-party tools separately and generate the local game-dependent data from your owned installation.

## License

Project source is available under the [MIT license](LICENSE), retaining the universal-modder upstream notice. Dependency license-reference documents and credits are included in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [licenses/](licenses/README.md). FTL game content remains outside this source license; players supply their own game and generate local presentation data.

## Credits

FTL: Faster Than Light is created by **Subset Games**. This is an unofficial community project and is not affiliated with or endorsed by Subset Games or Valve.

- [universal-modder](https://github.com/rehan-remade/universal-modder), by Rehan and contributors: the toolkit and example workspace from which this standalone source was prepared.
- [Hyperspace](https://github.com/FTL-Hyperspace/FTL-Hyperspace) and [FTL-Version-Rollback](https://github.com/FTL-Hyperspace/FTL-Version-Rollback): the loader, Lua API, documented signatures and rollback route.
- [ftlman](https://github.com/afishhh/ftlman), with [Slipstream Mod Manager](https://github.com/Vhati/Slipstream-Mod-Manager) as a resource-format reference.
- [Godot](https://godotengine.org/), [Frida](https://frida.re/), [Capstone](https://www.capstone-engine.org/), [Pillow](https://python-pillow.org/) and [NumPy](https://numpy.org/).
- [Valve's Steam Frame Godot guidance](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/godot) and [controller documentation](https://partner.steamgames.com/doc/steamhardware/steamframe/input).

Developed iteratively with **OpenAI Codex (GPT-6)**, with design direction and Steam Frame playtesting by the project maintainer. Crew/weapon/drone voxel geometry is procedural source code; no external generated-asset service was used. FTL artwork, icons, bitmap fonts and audio come from the player's local game, rather than this repository.
