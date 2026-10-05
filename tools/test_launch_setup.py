"""Read-only launch readiness and Windows wrapper regression checks; no FTL needed."""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import launch


@unittest.skipUnless(os.name == "nt", "The live launcher is Windows only")
class LaunchSetupTests(unittest.TestCase):
    def setUp(self):
        # Native Windows lookup must be able to read these fixtures too; some
        # sandboxes grant that access in the checkout but not the user's Temp.
        scratch = Path(__file__).resolve().parents[1] / "local_game_data/test_scratch"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=scratch)
        self.root = Path(self.temporary.name) / "FTL checkout with spaces"
        self.root.mkdir()
        self.lab = self.root / "separate lab"
        self.lab.mkdir()
        self.source = self.root / "owned original"
        self.source.mkdir()
        (self.source / "ftl.dat").write_bytes(b"synthetic archive placeholder")
        (self.lab / "FTLGame.exe").write_bytes(b"synthetic executable placeholder")
        (self.lab / "Hyperspace.dll").write_bytes(b"synthetic loader placeholder")
        self.marker = {"source_game": str(self.source), "activated": True, "save_prefix": "ftlvr"}
        self.write_marker()
        names = ("GetShiftState", "GetCtrlState", "ForceAutofireFlag", "OnTextInput",
                 "OnTextEvent", "TextInputOnRender", "TextInputStart", "CommandGuiRenderStatic",
                 "CommandGuiRenderPause", "TabbedWindowOnRender", "ChoiceBoxOnRender",
                 "MouseControlOnRender", "StarMapOnRender", "MenuScreenOnRender", "OptionsScreenOnRender", "CombatControlRenderTarget")
        self.hooks = self.lab / "hooks.json"
        self.hooks.write_text(json.dumps({"rvas": dict.fromkeys(names, 1),"offsets":{"gui_game_over":0x1e88,"focus_window_open":4},
                                         "sha1": hashlib.sha1((self.lab / "FTLGame.exe").read_bytes()).hexdigest()}))
        self.godot = self.root / "godot.exe"
        self.godot.write_bytes(b"synthetic renderer placeholder")
        self.local = self.root / "local_game_data"
        self.local.mkdir()
        self.manifest = self.local / "manifest.json"
        self.manifest.write_text(json.dumps({"ships": ["test"], "fonts": 1, "ui_assets": 1}))
        self.config = {"lab": str(self.lab), "hooks": str(self.hooks), "godot": str(self.godot)}
        self.project_patch = patch.object(launch, "PROJECT", self.root)
        self.project_patch.start()
        self.packages_patch = patch.object(launch.importlib.util, "find_spec", return_value=object())
        self.packages_patch.start()

    def tearDown(self):
        self.packages_patch.stop()
        self.project_patch.stop()
        self.temporary.cleanup()

    def write_marker(self):
        (self.lab / "ftlvr-lab.json").write_text(json.dumps(self.marker))

    def test_shared_preflight_accepts_complete_desktop_setup(self):
        self.assertEqual(launch.preflight(self.config, desktop=True)["mode"], "desktop")

    def test_old_hooks_require_modal_hud_capture_update(self):
        value = json.loads(self.hooks.read_text())
        for name in ("MenuScreenOnRender", "OptionsScreenOnRender", "CombatControlRenderTarget"):
            with self.subTest(name=name):
                incomplete = dict(value, rvas={key: address for key, address in value["rvas"].items() if key != name})
                self.hooks.write_text(json.dumps(incomplete))
                with self.assertRaisesRegex(ValueError, "Regenerate lab hooks.json.*live native HUD capture"):
                    launch.preflight(self.config, desktop=True)

    def test_missing_configuration_explains_setup(self):
        with self.assertRaisesRegex(ValueError, "Run SETUP.cmd"):
            launch.load_config(self.local / "launcher.json")

    def test_config_accepts_utf8_bom(self):
        path = self.local / "launcher.json"
        path.write_text(json.dumps(self.config), encoding="utf-8-sig")
        self.assertEqual(launch.load_config(path), self.config)

    def test_blank_or_relative_configuration_is_rejected(self):
        for path, message in (("", "nonempty"), ("godot.exe", "absolute")):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, message):
                launch.preflight(dict(self.config, godot=path), desktop=True)

    def test_game_and_renderer_need_correct_path_types(self):
        with self.assertRaisesRegex(ValueError, "Missing godot"):
            launch.preflight(dict(self.config, godot=str(self.root)), desktop=True)

    def test_missing_or_partial_assets_prevent_game_launch(self):
        self.manifest.unlink()
        with self.assertRaisesRegex(ValueError, "Local game assets are missing"):
            launch.preflight(self.config, desktop=True)
        self.manifest.write_text(json.dumps({"ships": ["test"], "fonts": 0, "ui_assets": 1}))
        with self.assertRaisesRegex(ValueError, "extraction is incomplete"):
            launch.preflight(self.config, desktop=True)

    def test_qa_save_prefix_is_rejected_by_normal_launcher(self):
        self.marker["save_prefix"] = "testvr"
        self.write_marker()
        with self.assertRaisesRegex(ValueError, "ftlvr save prefix"):
            launch.preflight(self.config, desktop=True)

    def test_click_wrappers_report_unconfigured_checkout_without_hanging(self):
        checkout = self.root / "unconfigured clone"
        checkout.mkdir()
        (checkout / "tools").mkdir()
        actual_project = Path(__file__).resolve().parents[1]
        helper = actual_project / "tools/show_launcher_error.cmd"
        shutil.copyfile(helper, checkout / "tools/show_launcher_error.cmd")
        for name in ("RUN-VR.cmd", "RUN-DESKTOP.cmd", "CHECK-SETUP.cmd"):
            shutil.copyfile(actual_project / name, checkout / name)
            environment = dict(os.environ, FTLVR_NO_PAUSE="1")
            result = subprocess.run([os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", name],
                                    cwd=checkout, env=environment, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1, name)
            self.assertIn("SETUP.cmd", result.stdout, name)
            self.assertIn("Launch stopped", result.stdout, name)

    def test_setup_rejects_microsoft_store_alias(self):
        checkout = self.root / "store alias clone"
        checkout.mkdir()
        (checkout / "tools").mkdir()
        actual_project = Path(__file__).resolve().parents[1]
        for name in ("SETUP.cmd", "tools/show_launcher_error.cmd"):
            shutil.copyfile(actual_project / name, checkout / name)
        alias = checkout / "fake LocalAppData/Microsoft/WindowsApps"
        alias.mkdir(parents=True)
        (alias / "python.exe").touch()
        # System32 can contain a real py.exe on CI runners. Keep only the
        # lookup utility, not that directory, on this synthetic PATH.
        lookup = checkout / "isolated lookup tools"
        lookup.mkdir()
        where = lookup / "where.exe"
        shutil.copyfile(Path(os.environ["SystemRoot"]) / "System32/where.exe", where)
        environment = dict(os.environ, FTLVR_NO_PAUSE="1", LOCALAPPDATA=str(checkout / "fake LocalAppData"),
                           PATH=str(lookup) + os.pathsep + str(alias))
        environment.pop("FTLVR_PYTHON", None)
        absent_launcher = subprocess.run([str(where), "py"], cwd=checkout, env=environment,
                                        capture_output=True, text=True, timeout=10)
        self.assertEqual(absent_launcher.returncode, 1, "Synthetic PATH must not expose the host's py launcher")
        store_alias = subprocess.run([str(where), "python"], cwd=checkout, env=environment,
                                    capture_output=True, text=True, timeout=10)
        self.assertEqual(store_alias.returncode, 0)
        self.assertEqual(store_alias.stdout.strip().casefold(), str(alias / "python.exe").casefold())
        result = subprocess.run([os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", "SETUP.cmd --dry-run"],
                                cwd=checkout, env=environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Microsoft Store alias is not a Python installation", result.stdout)
        self.assertFalse((checkout / ".venv").exists())

    def test_setup_accepts_explicit_python_and_forwards_dry_run(self):
        checkout = self.root / "explicit Python clone"
        checkout.mkdir()
        (checkout / "tools").mkdir()
        actual_project = Path(__file__).resolve().parents[1]
        for name in ("SETUP.cmd", "tools/setup_environment.py", "tools/show_launcher_error.cmd"):
            shutil.copyfile(actual_project / name, checkout / name)
        environment = dict(os.environ, FTLVR_NO_PAUSE="1", FTLVR_PYTHON=sys.executable)
        result = subprocess.run([os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", "SETUP.cmd --dry-run"],
                                cwd=checkout, env=environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Dry run complete", result.stdout)
        self.assertFalse((checkout / ".venv").exists())
        self.assertFalse((checkout / "local_game_data").exists())


if __name__ == "__main__":
    unittest.main()
