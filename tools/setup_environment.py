"""Create this source checkout's Python environment, or check launch readiness.

Setup installs Python packages and creates local configuration only. It never
copies, patches, launches or attaches to FTL. --check and --dry-run are read-only.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
VENV = PROJECT / ".venv"
VENV_PYTHON = VENV / "Scripts" / "python.exe"
LOCAL = PROJECT / "local_game_data"
CONFIG = LOCAL / "launcher.json"


def require_platform() -> None:
    if os.name != "nt":
        raise ValueError("The live game bridge currently supports Windows only.")
    if sys.version_info < (3, 10):
        raise ValueError("Python 3.10 or newer is required; Python 3.12 is recommended.")


def setup(dry_run: bool = False) -> None:
    require_platform()
    steps = [
        f"Create or reuse {VENV}",
        "Install the packages from requirements.txt inside .venv (internet access required)",
        "Copy config/launcher.example.json to local_game_data/launcher.json if absent",
        "Keep all game paths unconfigured until you edit launcher.json",
    ]
    for step in steps:
        print(step, flush=True)
    if dry_run:
        print("Dry run complete: no files or dependencies were changed.")
        return
    if VENV.exists() and not VENV_PYTHON.is_file():
        raise ValueError(".venv exists but is incomplete. Rename that folder and run SETUP.cmd again.")
    if not VENV_PYTHON.is_file():
        subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=True)
    subprocess.run(
        [str(VENV_PYTHON), "-m", "pip", "install", "-r", str(PROJECT / "requirements.txt")],
        check=True,
    )
    LOCAL.mkdir(exist_ok=True)
    (LOCAL / ".gdignore").touch()
    if not CONFIG.exists():
        shutil.copyfile(PROJECT / "config" / "launcher.example.json", CONFIG)
    print("\nPython environment ready. Finish docs/INSTALLATION.md before launching.")
    print(f"Edit your local paths in: {CONFIG}")
    print("SETUP.cmd does not install Hyperspace or prepare a game copy.")


def check(desktop: bool = False) -> None:
    require_platform()
    # The production launcher's own checks include executable fingerprints,
    # required hook families, dependencies, loader and the OpenXR runtime.
    sys.dont_write_bytecode = True
    from launch import load_config, preflight
    result = preflight(load_config(CONFIG), desktop=desktop)
    print(json.dumps(result, indent=2))
    print("Setup checks passed. No game was launched or modified.")
    print("This checks readiness; it does not measure headset performance.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true", help="Read-only local launch preflight")
    modes.add_argument("--dry-run", action="store_true", help="Describe setup without writing or installing")
    parser.add_argument("--desktop", action="store_true", help="Skip the SteamVR runtime check with --check")
    args = parser.parse_args()
    if args.desktop and not args.check:
        parser.error("--desktop is only valid with --check")
    if args.check:
        check(desktop=args.desktop)
    else:
        setup(dry_run=args.dry_run)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"FTL Tabletop VR setup: {error}", file=sys.stderr)
        sys.exit(1)
