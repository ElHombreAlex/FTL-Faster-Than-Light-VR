# Troubleshooting

Start with `CHECK-SETUP.cmd`, or `CHECK-SETUP.cmd --desktop` if testing without SteamVR. These checks are read-only. Setup remains a technical alpha; if the documented versions or paths are different, get the prerequisites in place before bypassing a check.

## Environment and installation

| Symptom | What to check |
|---|---|
| `python` opens Microsoft Store, or Python cannot be found | Install Python 3.10+ from python.org with its launcher, reopen your terminal and rerun `SETUP.cmd`. |
| Missing `frida`, `PIL`, `numpy` or `capstone` | Run `SETUP.cmd` and use the repository's `.venv` Python. Installing into another Python environment will not satisfy the launch wrappers. |
| Package installation fails | Check the pip output and internet connectivity. Python 3.12 is the development baseline. Setup does not download game dependencies. |
| `.venv` is incomplete | Rename the incomplete `.venv` and rerun `SETUP.cmd`. Never move a virtual environment between checkouts; recreate it after moving the repository. |
| Missing lab, Godot or hooks | Edit `local_game_data/launcher.json`, using absolute paths. Check that the Godot field is the executable file, not its folder. |
| Bad JSON / invalid path | Use the format in `config/launcher.example.json`: forward slashes or doubled backslashes, double quotes and no trailing comma. |
| Original Steam build rejected | The preparer requires the verified Windows Steam 1.6.14 executable. GOG assets work with extraction, but the GOG executable route is unverified. Do not suppress the fingerprint gate. |
| Rollback patch rejected | Use the documented official `patch/Steam-1.6.14.bps`, not a patch for another storefront/version. |
| Lab destination rejected | Use a new empty separate directory outside the installed game. A nonempty unrelated directory is intentionally refused. |
| `Hyperspace.ftl`, loader DLL or ftlman error | Verify the full release folder structure and the ftlman executable/version described in Installation. |
| Resolver reports a missing/ambiguous signature | Use the matching win32/1.6.9 signature directory from Hyperspace source, with all neighboring `.zhl` files. Do not use other people's hook addresses. |
| Recorded original installation unavailable | The bridge still reads the original `ftl.dat` for newly encountered ships. Restore that location or rebuild the lab/config against the new installation. |

## Launch and VR

| Symptom | What to check |
|---|---|
| SteamVR runtime error | Start SteamVR and select it as the active OpenXR runtime in SteamVR settings. The launcher reads that setting; it does not modify it. |
| Godot shows a scene but no live game | Use `RUN-VR.cmd` or `RUN-DESKTOP.cmd`; Godot alone does not start the native bridge. |
| Bridge timeout or exits immediately | Read `local_game_data/logs/bridge.log`. Confirm the lab is activated, its executable matches `hooks.json`, Hyperspace exists and extraction is complete. |
| “Bridge already running” | Close the existing client and allow graceful shutdown before retrying. Do not start several sessions against one VR save profile. |
| Black or stale HUD/tactical image | Check `bridge_status.json` for fresh heartbeat/state/capture and errors. Check the logs. Do not judge the live Tactical stream from diagnostic PNGs: PNG previews update only once per second. |
| Pointer missing or controller unresponsive | Confirm both controllers are tracked in SteamVR. Inspect the in-game warning, Help diagram and `xr_input.json` for each hand's tracking/profile/trigger values. Some fallback controller bindings remain untested. |
| Tactical looks slow | Report headset settings and whether the 3D scene, HUD or Tactical capture is slow. The live Tactical stream targets 30 Hz; mono desktop capture measurements are not stereo headset FPS. |
| Poor performance | Close unrelated GPU-intensive programs, record SteamVR resolution/refresh rate and note the encounter type. This alpha still needs physical stereo frame-pacing measurements and broad campaign QA. |
| Vulkan/client failure | Read `client.log` and `godot.log`; confirm the documented Godot executable and GPU driver. The client uses Godot's Vulkan Mobile renderer. |

## Saves and game input

The VR client uses the `hs_ftlvr_` profile in the normal FTL save directory. The launcher backs up that profile and isolated lab settings before each launch, under the lab's `save-backups/` directory. It does not make a complete backup of every ordinary FTL save. Make a manual full save-folder backup before your first run.

Close the session before restoring a VR backup. Preserve a copy of the current profile first and restore only the intended matching VR files. If shutdown fails, FTL's last autosave may be the most recent recoverable state. Do not run smoke/native QA tools against a precious campaign.

The bridge invokes handlers of the verified isolated FTL process. It does not drive your desktop mouse/keyboard or change the Windows keyboard layout. The floating renaming keyboard is QWERTY. Leave the lab's reserved input bindings and 1280×720 window unchanged.

## Useful diagnostic files

| Local file | Purpose |
|---|---|
| `local_game_data/logs/bridge.log` | Native process, Hyperspace state and capture/input bridge failures |
| `local_game_data/logs/client.log` | Godot client process output |
| `local_game_data/logs/godot.log` | Renderer/XR messages; search `FTLVR_XR_INPUT` for controller diagnostics |
| `local_game_data/bridge_status.json` | Session connection, heartbeat, state/capture freshness and errors |
| `local_game_data/xr_input.json` | Hand tracking, selected pose, interaction profile and button/axis values |
| `local_game_data/manifest.json` | Local asset extraction summary and source archive path |
| `<lab>/ftlvr-lab.json` | Local source installation, save prefix and activation marker |
| `<lab>/hooks.json` | Resolved local executable fingerprint and hook data |

For a bug report, include the expected/actual behavior, reproduction steps, storefront/game version, Godot/Hyperspace versions, headset/controllers, GPU, SteamVR settings and relevant **short** log excerpts. A short gameplay recording can help diagnose pointing or panel placement.

Review excerpts for your username, absolute filesystem paths or other personal information before posting. Do not attach game archives, executable copies, extracted game assets or full save folders. An issue report need not contain the entire local working directory.
