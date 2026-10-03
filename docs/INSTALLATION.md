# Installation

This is a source release for a technical Windows alpha. Setup currently involves an isolated game copy, a matching Hyperspace installation and native hook resolution. The repository includes convenient environment and launch scripts; a complete installation on a fresh PC has not yet been validated.

The original FTL process runs gameplay, events, combat, saves and soundtrack. The Godot client reads its live state and forwards VR commands through the bridge. You need your own installed game; no FTL executable, archive, extracted artwork, fonts or music is included here.

## Prerequisites

| Requirement | Development/verification baseline |
|---|---|
| Operating system | Windows; the live bridge uses Windows native APIs |
| FTL | Owned **Steam Windows 1.6.14** installation, with an unmodified executable |
| Isolated FTL copy | Prepared by these tools, rolled back to **Windows 1.6.9** |
| Python | **3.10+**, with `venv` and `pip`; development uses Python 3.12 |
| Python packages | `requirements.txt`: Frida 17.9.0, Capstone 5.0.9, Pillow 10+, NumPy 1.24+ |
| Godot | **4.7.2** Windows executable, Vulkan capable GPU/driver |
| Hyperspace | **1.23.2** release archive and matching source/signature files |
| Rollback | Official `patch/Steam-1.6.14.bps` from FTL-Version-Rollback |
| Archive mod manager | **ftlman 0.7.4** Windows executable |
| VR | SteamVR installed/running and selected as the active OpenXR runtime |
| Tested hardware | Steam Frame, RTX 4060 Ti 8 GB, 32 GB RAM; desktop inspection and prior headset playtests |

The asset extractor can read compatible Steam or GOG 1.6.x archives. The complete GOG executable/loader route has **not** been validated. The preparer intentionally rejects an unknown executable or rollback patch. Other headsets and operating systems have not completed gameplay QA.

Obtain tools from their official project pages:

- [Python](https://www.python.org/downloads/windows/)
- [Godot downloads](https://godotengine.org/download/archive/)
- [Hyperspace releases and source](https://github.com/FTL-Hyperspace/FTL-Hyperspace)
- [FTL-Version-Rollback](https://github.com/FTL-Hyperspace/FTL-Version-Rollback)
- [ftlman releases](https://github.com/afishhh/ftlman/releases)

Keep downloaded tools and the isolated game **outside this repository**. Download the matching Hyperspace source as well as its release archive: the `.zhl` signature files are needed for `resolve_hooks.py`. The project does not download or install these game dependencies automatically.

## 1. Choose separate folders and back up your saves

Example paths below are placeholders. Replace them with your own locations:

| Purpose | Example |
|---|---|
| Repository | `D:\Projects\FTL-Tabletop-VR` |
| Original Steam game | `C:\Program Files (x86)\Steam\steamapps\common\FTL Faster Than Light` |
| New isolated lab | `C:\Games\FTL-VR-Lab` |
| Unpacked Hyperspace release | `C:\Tools\Hyperspace-1.23.2` |
| Hyperspace source | `C:\Tools\FTL-Hyperspace-source` |
| Rollback repository | `C:\Tools\FTL-Version-Rollback` |
| ftlman | `C:\Tools\ftlman\ftlman.exe` |

Before the first game launch, copy your existing `%USERPROFILE%\Documents\My Games\FasterThanLight` folder to a separate backup. If your Documents folder is redirected, locate the actual FTL saves first. Close FTL before making this copy. The VR profile uses separate `hs_ftlvr_` save files in FTL's save directory; the isolated copy is not a completely separate Windows user profile.

The lab must be separate from the original game and must not be a parent or child of it. Use a new empty folder. `prepare_lab.py` refuses an unrelated nonempty destination. Do not use a Steam-managed folder for the lab, or point it at your installation.

## 2. Create the Python environment

Open a terminal in the repository, then run:

```powershell
.\SETUP.cmd
```

This creates `.venv`, installs `requirements.txt` there and copies the example config to ignored `local_game_data/launcher.json` if that file does not already exist. It requires internet access for Python packages. It does **not** patch FTL, install a loader into the game or launch it. Your Windows language and keyboard settings are not changed.

You can inspect its actions first with `SETUP.cmd --dry-run`. If the Windows `python` command opens the Microsoft Store, install Python from python.org with the Python launcher, reopen the terminal and retry.

## 3. Prepare and activate the isolated game

Check that the unpacked Hyperspace release contains:

- `Hyperspace.ftl`
- `Windows - Extract these files into where FTLGame.exe is\Hyperspace.dll`
- `Windows - Extract these files into where FTLGame.exe is\xinput1_4.dll`

Run the following in PowerShell, substituting your paths:

```powershell
.\.venv\Scripts\python.exe tools\prepare_lab.py `
  --game "C:\Program Files (x86)\Steam\steamapps\common\FTL Faster Than Light" `
  --lab "C:\Games\FTL-VR-Lab" `
  --rollback "C:\Tools\FTL-Version-Rollback\patch\Steam-1.6.14.bps" `
  --hyperspace "C:\Tools\Hyperspace-1.23.2" `
  --mod-manager "C:\Tools\ftlman\ftlman.exe" `
  --activate
```

`--activate` explicitly installs the loader and patched resources into **that isolated lab**. The preparer verifies the original executable, rollback patch and resulting 1.6.9 executable. It packages our Lua bridge with Hyperspace resources, creates the `ftlvr` save prefix and sets the lab's window/bindings. The original Steam installation is read as the copy source.

Omit `--activate` to prepare resources without installing the loader into the lab. A prepared-only lab cannot run this client; rerun with `--activate` when ready. Keep the original installation in its recorded location: the bridge reads its archive to construct newly encountered ship variants.

## 4. Resolve the local executable hooks

Use `CApp.zhl` from the matching **win32/1.6.9** directory of the Hyperspace source:

```powershell
.\.venv\Scripts\python.exe tools\resolve_hooks.py `
  "C:\Games\FTL-VR-Lab\FTLGame.exe" `
  "C:\Tools\FTL-Hyperspace-source\libzhlgen\test\functions\win32\1.6.9\CApp.zhl" `
  "C:\Games\FTL-VR-Lab\hooks.json"
```

Keep the entire signature directory together. The resolver also reads neighboring files such as `CEvent.zhl`, `TextInput.zhl`, `CommandGui.zhl`, `TabbedWindow.zhl`, `ChoiceBox.zhl`, `MouseControl.zhl`, `StarMap.zhl`, `SystemControl.zhl`, `SystemBox.zhl` and `ShipSystem.zhl`. It checks unique signatures and structure probes, then stores the fingerprint and resolved addresses locally. Do not copy somebody else's `hooks.json` as a substitute.

## 5. Extract local presentation assets

Run against your **original owned archive**, not the lab's patched archive:

```powershell
.\.venv\Scripts\python.exe tools\extract_ftl.py `
  "C:\Program Files (x86)\Steam\steamapps\common\FTL Faster Than Light\ftl.dat"
```

This generates the initial player/enemy ship data, original UI artwork and bitmap fonts in ignored `local_game_data/`. The bridge extracts additional ships on demand. Do not commit that folder or the generated lab to a public repository.

## 6. Configure and check

Edit `local_game_data/launcher.json`. It contains exactly these local paths:

```json
{
  "lab": "C:/Games/FTL-VR-Lab",
  "hooks": "C:/Games/FTL-VR-Lab/hooks.json",
  "godot": "C:/Tools/Godot/Godot_v4.7.2-stable_win64.exe"
}
```

Use absolute paths and forward slashes, or double each backslash in JSON. Point `godot` at the actual downloaded executable, including its filename. Keep this configuration local.

For VR, start SteamVR, connect the headset/controllers and select SteamVR as the current OpenXR runtime in SteamVR settings. Then run:

```powershell
.\CHECK-SETUP.cmd
```

For a desktop check without a VR runtime:

```powershell
.\CHECK-SETUP.cmd --desktop
```

Checks verify dependencies, local extraction, the recorded original archive, the lab marker/fingerprint, required hooks, loader and OpenXR runtime. They do not launch, patch or attach to FTL. A passed check does not establish full campaign compatibility or headset performance.

## 7. Launch and close

```powershell
.\RUN-VR.cmd
# Or inspect the live client without a headset:
.\RUN-DESKTOP.cmd
```

The launcher backs up the separate VR save files and lab settings, starts the isolated FTL bridge, waits for fresh live state/capture and starts Godot. It can take up to roughly one minute to establish the bridge; failure details appear in the local logs.

Closing the client requests a graceful native save/exit and stops the bridge. Pre-launch VR backups are in the lab's `save-backups/` folder. Allow shutdown to finish before starting another session. Logs are in `local_game_data/logs/`. See [troubleshooting](TROUBLESHOOTING.md) and [controls](CONTROLS.md).

Do not change the lab's 1280×720 canvas or reserved bindings while testing. Run the source client with the launcher; opening Godot alone does not create the game bridge. Avoid running automated native QA tools against a campaign you want to keep: those tools can send game commands and change saves.

## Remove the prototype

Close the VR client, bridge and isolated game first. The repository, `.venv`, generated `local_game_data/`, downloaded dependencies and separate lab can then be removed as ordinary folders. VR profile files live in the FTL save directory, not only the lab; back them up before removing any `hs_ftlvr_` files. Keep the original game and ordinary FTL saves.
