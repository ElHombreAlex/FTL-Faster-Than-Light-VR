# FTL VR

**Command your ship from a floating tabletop in VR.**

An experimental OpenXR mod for **FTL: Faster Than Light**. Walk around a miniature ship, direct crew into rooms, target an opposing ship, and use FTL's original HUD and menus with tracked controllers.

> **Playable source alpha · Windows · SteamVR · Steam Frame tested**
>
> The real FTL process runs the campaign, combat, events, saves and soundtrack. The VR client presents that live game in Godot. Bring your own copy of FTL; game files and extracted assets are not included.

## What it does

- Floating player and enemy ships with opposing bows, room interiors, visible shields and movable encounter placement.
- Compact original HUD following the headset, with clearance above the ship when needed; upper status and crew roster, controller navigation, Tactical, shortcuts, system power and illustrated Help.
- Crew selection and drag-to-room orders, door controls, weapon/beam targeting and native system targeting.
- Contextual Jump/Ship/Store actions, a cockpit-anchored sector map, floating event dialogs and complete native shop/ship panels.
- An eight-slot action wheel with localized equipped names, family/ammo hints, Shift/Ctrl shortcuts and a QWERTY VR keyboard for renaming crew and ships.
- Original procedural voxel crew, weapons and drones, weapon charge indicators, room-condition feedback, cross-shaped breaches and native miss cues.
- Surrounding stars and native-state-driven asteroid, sun, nebula/storm and pulsar environments.
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

The maintainer has played substantial portions of runs on Steam Frame and confirmed that earlier revisions are playable. The compact gameplay HUD now follows the headset first and stops above the ship only when it would intersect the hull or shield. Equipped weapon entries remain available on the wheel when no drones are installed. Room floors retain role icons and condition colors; health/status bars and counters are removed. System Power, storm-aware free power, native miss feedback and cross-shaped breaches remain available.

Core game input, capture, native state and graceful launch/exit have been verified in an isolated game. **Complete campaign coverage and measured stereo headset performance remain open.** Hacking target acceptance is verified; drone attachment/effect completion still needs encounter testing. The renderer presents hazards and some effects approximately while the original game remains authoritative.

The **current source** passed 38 Python tests and nine Godot suites in the prepared source folder. Desktop and VR wrappers passed combined launch/exit in desktop smoke mode, including the GitHub Desktop checkout's FTL-VR alias, with clean client logs and no bridge errors; a separate copied campaign also verified native weapon entries in the rendered wheel. VR preflight passed, while physical Steam Frame comfort and stereo performance remain unmeasured for these changes. Campaign hashes and game executable fingerprints were preserved. Historical Tactical delivery reached about **28–29 updates/second in desktop scene checks**; this is texture delivery, not headset FPS. A clean installation on a different machine has not yet been tested. See [STATUS.md](docs/STATUS.md) for details.

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
