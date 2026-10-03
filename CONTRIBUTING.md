# Contributing

Thanks for helping improve this experimental tabletop VR presentation of FTL. Good contributions include reproducible bug reports, controller comfort feedback, focused fixes, original procedural models/effects, documentation and verified compatibility work.

Read the [README](README.md), [project status](docs/STATUS.md) and [development guide](docs/DEVELOPMENT.md) before changing the bridge. The actual FTL process remains authoritative for gameplay.

## Reporting a bug

Include:

- Repository revision and whether this was **live VR**, **live desktop** or **demo/fixture** mode.
- Windows, FTL store/build, prepared lab build, Hyperspace, Godot, Python and SteamVR versions.
- Headset/controllers, active OpenXR profile, GPU and RAM.
- Steps to reproduce, expected behavior and what happened.
- Active panel/page, pause/event/transition state and relevant installed systems.
- Whether it occurs without other FTL mods.
- Short redacted bridge/client log excerpts and state/capture freshness when relevant.
- For pointing issues: which hand/button, target type, panel overlap and whether tracking was valid.
- For performance: which measurement tool and whether the number is transport Hz, desktop FPS or actual stereo headset frame timing.

Do not attach game executables, `ftl.dat`, extracted artwork/fonts/audio, full saves, decompiled game source or the complete local-data folder. Describe the encounter or use a minimal synthetic reproduction. Remove personal file paths before sharing logs.

## Submitting a focused change

1. Work in your own source checkout and isolated game lab.
2. Keep the change small enough to review and explain its expected native behavior.
3. Follow existing Python/GDScript/JavaScript/Lua style in the file you edit.
4. Run the relevant checks from [Development](docs/DEVELOPMENT.md).
5. Document verification, hardware/build/runtime and remaining limitations in the change description.
6. Update affected documentation and the in-VR controller diagram when bindings change.

A renderer screenshot does not verify a native command, and a desktop frame rate does not verify VR performance. Be explicit about simulated versus physical controller testing. Native experiments can change the disposable run; restore your own backup when needed.

## Technical boundaries

- Keep input scoped to the verified isolated game process; avoid global desktop mouse/keyboard automation.
- Preserve the separate VR save prefix, backups and graceful exit behavior.
- Preserve executable fingerprint/version checks. Unknown builds need a validated implementation, not removal of rejection logic.
- Keep native damage, crew movement, targeting restrictions, sensor fog and system availability authoritative.
- Preserve 1280×720 native input coordinates when changing capture/display resolution.
- Avoid blocking the game's main thread and avoid per-frame texture/mesh allocation.
- Keep installer paths configurable. Do not commit personal machine paths or bundled third-party executables.

## Source license and attribution

Original contributions to this project's source are provided under its [MIT license](LICENSE). Retain existing copyright/license notices. Document the origin and terms of any third-party code you add in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), preserving that component's terms. FTL content and locally extracted resources are outside the project license and stay out of commits.

## Community testing priorities

The current priorities are physical Steam Frame comfort and input reliability, stereo frame pacing during busy/hazard encounters, complete campaigns, boarding/teleporters, hacking completion, beam/bomb encounters and additional ship/drone combinations. GOG asset extraction is supported; its complete executable/loader path and other headset hardware require separate validation.

See [STATUS](docs/STATUS.md) for the current evidence and remaining work, and [CONTROLS](docs/CONTROLS.md) for the intended bindings.
