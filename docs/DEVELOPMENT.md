# Development and verification

[Back to README](../README.md) · [Architecture](ARCHITECTURE.md) · [Contributing](../CONTRIBUTING.md) · [Project status](STATUS.md)

Start with [installation](INSTALLATION.md) for the verified Windows tool versions and local asset import. This is a source prototype with a version-specific native bridge, not a universal drop-in game converter.

## Working on the client

Open `project.godot` in the documented Godot version. Keep `local_game_data/`, imported caches, exports, lab copies and third-party binaries out of the repository. For game-free renderer inspection, start the project with `--demo --desktop`:

```powershell
godot --xr-mode off --path . -- --demo --desktop
```

This does not launch a native campaign. Detailed ship/UI inspection still needs local extraction from an owned game archive. Live play uses `tools/launch.py`, not the demo command. Do not use stale captured state as evidence that a new native integration works.

The main implementation areas are listed in [Architecture](ARCHITECTURE.md). A focused change usually fits one of four paths:

1. **Presentation:** procedural models, effects or placement; preserve native positions/visibility and pause behavior.
2. **Controller/UI:** action mapping, ray/crop picking, contextual pages and panel priority; update the Help diagram and [controls](CONTROLS.md) together.
3. **Bridge:** schema and native command translation; verify native outcomes in a separate lab/profile.
4. **Transport/performance:** capture/read/upload timing; keep resolution-independent native picking and avoid per-frame mesh/texture allocation.

## Python checks

After installing the documented Python requirements, run from the repository root:

```powershell
python -m unittest discover -s tools -p "test_*.py"
```

The current prepared source passed **38 Python tests**, including empty native drone-list and portable-launcher regressions. The tests exercise synthetic archive/layout/font extraction, bridge schema/input translation, native-pixel filtering, raw frame publication and launcher preflight/error handling. They do not launch FTL. Temporary fixture files are created by the tests. Godot suites and focused native checks are recorded in [STATUS](STATUS.md); physical headset coverage remains separate.

## Godot checks

Use a **separate development checkout or disposable local-data folder** with the required extracted assets. Some suites write screenshots/test frames under `local_game_data/`; do not run them over an active production bridge or package those outputs. Create the local output folder before graphical suites if it is missing.

The nine suites below passed for the current prepared source in the configured development environment, including the latest HUD/wheel/bar corrections. See [STATUS](STATUS.md) for evidence and limits. A fresh source checkout lacks game assets; model/input/font checks may fail until local extraction is complete.

```powershell
godot --headless --xr-mode off --path . --script tools/test_combat.gd -- --demo
godot --headless --xr-mode off --path . --script tools/test_input.gd -- --demo --desktop
godot --headless --xr-mode off --path . --script tools/test_models.gd -- --demo --desktop
godot --headless --xr-mode off --path . --script tools/test_environment.gd -- --demo --desktop
godot --xr-mode off --path . --script tools/test_ui.gd -- --desktop
godot --xr-mode off --path . --script tools/test_controller_ui.gd -- --demo --desktop
godot --xr-mode off --path . --script tools/test_frame_transport.gd -- --desktop
godot --headless --xr-mode off --path . --script tools/test_hud_layout.gd -- --desktop
godot --headless --xr-mode off --path . --script tools/test_damage_visuals.gd -- --demo --desktop
```

The UI/controller/transport suites use actual GPU rendering, so keep their graphical mode. Headless runs of them are not equivalent verification. These suites cover effects, room/beam picking, controller context/bindings, model/task distinctions, environmental presentation, original local fonts, UI priority/crops and the raw frame protocol. HUD-layout checks cover headset-relative placement, swept collision prevention and transformed ship/shield clearance. Controller checks include native empty/malformed equipment collections. Damage-visual checks cover permission-aware room colors, absence of floor status bars, native miss presentation and oxygen-dependent breach effects.

No test command above drives a native game or modifies its saves. Separate **live bridge checks** do run the game and can advance a run or change equipment/state.

## Native integration checks

Keep a disposable isolated lab/profile for automation. Back up its saves/settings and record how to restore it before interacting with FTL. Inspect the actual snapshot/input/capture result, not just a success log from the client. Do not perform live experiments in a valuable campaign.

```powershell
python tools/launch.py --check --desktop
python tools/launch.py --smoke
```

`--check` performs preflight without launching. `--smoke` launches the actual isolated game and desktop client, then requests client shutdown after a short interval and checks cleanup. It uses the configured VR save prefix, takes the normal pre-launch backup and may save game state on exit; it is not a purely synthetic test.

When adding a system or command, compare the visible native outcome and snapshot: installed-system availability, native power step, target room/ship, actual crew position, resource change or event transition. A target being accepted does not establish that its eventual effect completed. Hacking attachment/effects, native beam/bomb encounter coverage and full campaigns remain areas for further verification.

A preceding native missed-event check used a private projectile and forced `Evasion.MISS` to exercise the actual flag/event path. It is integration evidence, not a measurement of random evasion probabilities. Enemy room condition colors respect the native visibility rules; floor health/status bars are no longer rendered. Do not infer permission to reveal other hidden state from public icon color or crew-room fog alone.

The preparer, resolver and launcher reject unknown executable fingerprints. To support another executable, identify a known owned build, implement and validate a complete matching route and keep the rejection path. Do not disable fingerprint checks or reuse addresses from a different build.

## Profiling and visual inspection

For a running disposable live session with Tactical open:

```powershell
python tools/profile_tactical.py
godot --xr-mode off --path . --script tools/profile_tactical.gd -- --desktop --full-main
```

These measure native transport delivery and received textures/desktop rendering. **They are not stereo headset FPS.** The observed improvements and outstanding headset gates are summarized in [STATUS](STATUS.md). Use raw sequence/timestamp freshness rather than the deliberately slow PNG previews.

Additional helpers:

| Tool | Use |
|---|---|
| `tools/benchmark_effects.gd` | Renderer effect benchmark; desktop results only |
| `tools/capture_models.gd` | Local model/weapon gallery |
| `tools/capture_ship_details.gd` | Explicit visual fixture for door tiers, fire/breach effects and hull bar |
| `tools/capture_environment.gd` | Environmental presentation inspection |
| `tools/capture_native_models.gd` | Inspect models from an owner-local native snapshot |
| `tools/capture_live.gd`, `tools/record_live.gd` | Capture this client's viewport with a running bridge |
| `tools/capture_input.gd`, `tools/input_harness.gd` | Simulated interaction inspection |

Fixtures illustrate behavior; label them as fixtures rather than real gameplay. Keep game-derived screenshots, snapshots and extracted resources local.

## Logs and useful evidence

- `local_game_data/logs/bridge.log`: native process/bridge errors.
- `local_game_data/logs/client.log`: client output in combined launches.
- `local_game_data/bridge_status.json`: connection, heartbeat and state/capture freshness.
- `local_game_data/xr_input.json`: tracking state, chosen pose, action profile and trigger/grip values.
- `FTLVR_XR_INPUT` client log lines: controller mapping/tracking diagnostics.
- The configured lab's `save-backups/`: pre-launch VR-profile and settings snapshots.

Include relevant redacted excerpts in bug reports. Remove personal paths, save contents and any unrelated process/account details. A frozen native event/store UI is distinct from the user's pause toggle; check both state fields when diagnosing pause effects.

## Before proposing a change

- Describe the behavior changed and the native rule it relies on.
- Run the focused checks for that area; state which assets/build/runtime were used.
- Verify graphical changes in actual rendering and interactions in their relevant UI context.
- For VR changes, report headset/controller testing separately from desktop/simulated results.
- Keep generated data, game binaries, archives, extracted assets and saves out of the diff.
- Update the Help diagram, controls, installation or status documentation when affected.

Full campaign testing, headset comfort and physical stereo performance remain community testing priorities. Passing all automated suites is useful evidence, not a declaration that these gates are complete.
