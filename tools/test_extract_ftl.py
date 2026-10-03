import struct
import tempfile
import unittest
from pathlib import Path

from extract_ftl import Pkg, build_ship, extract_fonts, parse_layout, system_rooms


class ExtractTests(unittest.TestCase):
    def test_owned_font_bootstrap_copies_original_bytes_only(self):
        original = b"FONT\x01" + bytes(19)

        class FakePkg:
            entries = {"fonts/JustinFont10.font": original}

            def read(self, name):
                return self.entries[name]

        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)
            self.assertEqual(extract_fonts(FakePkg(), target), ["fonts/JustinFont10.font"])
            self.assertEqual((target / "fonts/JustinFont10.font").read_bytes(), original)
            self.assertEqual(list(target.rglob("*.ttf")), [])
            FakePkg.entries["fonts/JustinFont10.font"] = b"bad font"
            with self.assertRaises(ValueError):
                extract_fonts(FakePkg(), target)

    def test_layout_room_and_door(self):
        layout = parse_layout(b"X_OFFSET\n0\nROOM\n7\n3\n4\n2\n1\nDOOR\n4\n4\n7\n8\n1\n")
        self.assertEqual(layout["rooms"], [{"id": 7, "x": 3, "y": 4, "w": 2, "h": 1}])
        self.assertEqual(layout["doors"][0]["b"], 8)

    def test_pkg_bounds_and_read(self):
        name = b"data/test.txt\x00"
        payload = b"FTL test"
        offset = 16 + 20 + len(name)
        header = b"PKG\n" + struct.pack(">HHII", 16, 20, 1, len(name))
        record = struct.pack(">I", 0) + b"\x00\x00\x00\x00" + struct.pack(">III", offset, len(payload), len(payload))
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "ftl.dat"
            path.write_bytes(header + record + name + payload)
            self.assertEqual(Pkg(path).read("data/test.txt"), payload)

    def test_system_room_mapping_only_includes_installed_systems(self):
        xml = b'<FTL><shipBlueprint name="PLAYER_SHIP_HARD" layout="kestral"><systemList><pilot room="0" start="true"/><drones room="2" start="false"/></systemList></shipBlueprint></FTL>'
        name, systems = system_rooms(xml, "kestral")
        self.assertEqual(name, "PLAYER_SHIP_HARD")
        self.assertEqual(systems, {"0": "pilot"})

    def test_ship_texture_matches_native_dimensions_and_crop_offsets(self):
        def png(width, height):
            return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", width, height)

        class FakePkg:
            entries = {
                "data/test.txt": b"ROOM 0 0 0 2 2",
                "data/test.xml": b'<ship><img x="-20" y="-30" w="100" h="120"/></ship>',
                "data/blueprints.xml": b"<FTL/>",
                "img/ships_noglow/test_base.png": png(60, 80),
                "img/ships_glow/test_base.png": png(100, 120),
            }

            def read(self, name):
                return self.entries[name]

        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)
            result = build_ship(FakePkg(), "test", target)
            self.assertEqual(result["image_path"], "img/ships_glow/test_base.png")
            result = build_ship(FakePkg(), "test", target,
                                native_image_rect={"x": 5, "y": -7, "w": 60, "h": 80})
            self.assertEqual(result["image_path"], "img/ships_noglow/test_base.png")
            import json
            saved = json.loads((target / "test.json").read_text(encoding="utf-8"))
            self.assertEqual(saved["image_rect"], {"x": 5, "y": -7, "w": 60, "h": 80})
            self.assertEqual(saved["texture_size"], [60, 80])


if __name__ == "__main__":
    unittest.main()
