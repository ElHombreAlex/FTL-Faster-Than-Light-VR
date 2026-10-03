"""Read a user's FTL PKG and write local-only data for the tabletop prototype.

This intentionally does not patch the game or copy game data into the repository.
Works with a Steam or GOG ftl.dat that uses the 1.6.x PKG layout.
"""

from __future__ import annotations

import argparse
import json
import struct
import xml.etree.ElementTree as ET
from pathlib import Path


class Pkg:
    def __init__(self, path: Path):
        self.path = path
        self.entries: dict[str, tuple[int, int, int, int]] = {}
        with path.open("rb") as source:
            header = source.read(16)
            if len(header) != 16 or header[:4] != b"PKG\n":
                raise ValueError("Not an FTL PKG archive")
            header_size, entry_size, count, names_size = struct.unpack(">HHII", header[4:])
            if header_size != 16 or entry_size != 20 or count > 100_000:
                raise ValueError("Unsupported FTL PKG index")
            records = []
            for _ in range(count):
                record = source.read(20)
                if len(record) != 20:
                    raise ValueError("Truncated FTL PKG index")
                _hash = int.from_bytes(record[0:4], "big")
                flags = record[4]
                name_offset = int.from_bytes(record[5:8], "big")
                offset, size, raw_size = struct.unpack(">III", record[8:20])
                records.append((flags, name_offset, offset, size, raw_size))
            names = source.read(names_size)
            source.seek(0, 2)
            archive_size = source.tell()
            for flags, name_offset, offset, size, raw_size in records:
                if name_offset >= len(names) or offset + size > archive_size:
                    raise ValueError("FTL PKG index points outside archive")
                end = names.find(b"\x00", name_offset)
                if end < 0:
                    raise ValueError("Unterminated FTL PKG path")
                name = names[name_offset:end].decode("ascii")
                self.entries[name] = (flags, offset, size, raw_size)

    def read(self, name: str) -> bytes:
        flags, offset, size, raw_size = self.entries[name]
        if flags != 0 or raw_size != size:
            raise ValueError(f"Compressed or unsupported PKG entry: {name}")
        with self.path.open("rb") as source:
            source.seek(offset)
            data = source.read(size)
        if len(data) != size:
            raise ValueError(f"Truncated PKG entry: {name}")
        return data


def parse_layout(raw: bytes) -> dict:
    tokens = raw.decode("utf-8-sig").split()
    counts = {"X_OFFSET": 1, "Y_OFFSET": 1, "VERTICAL": 1, "ELLIPSE": 4,
              "ROOM": 5, "DOOR": 5}
    layout: dict = {"rooms": [], "doors": []}
    cursor = 0
    while cursor < len(tokens):
        tag = tokens[cursor].upper()
        cursor += 1
        if tag not in counts:
            raise ValueError(f"Unknown layout token: {tag}")
        count = counts[tag]
        if cursor + count > len(tokens):
            raise ValueError(f"Truncated {tag} record")
        values = [int(value) for value in tokens[cursor:cursor + count]]
        cursor += count
        if tag == "ROOM":
            room_id, x, y, w, h = values
            layout["rooms"].append({"id": room_id, "x": x, "y": y, "w": w, "h": h})
        elif tag == "DOOR":
            x, y, a, b, vertical = values
            layout["doors"].append({"x": x, "y": y, "a": a, "b": b,
                                    "vertical": bool(vertical)})
        else:
            layout[tag.lower()] = values[0] if count == 1 else values
    if not layout["rooms"]:
        raise ValueError("Layout contains no rooms")
    return layout


def system_rooms(blueprints: bytes, layout_name: str) -> tuple[str, dict[str, str]]:
    root = ET.fromstring(blueprints)
    candidates = [node for node in root.findall(".//shipBlueprint")
                  if node.get("layout") == layout_name]
    if not candidates:
        return "", {}
    preferred = "PLAYER_SHIP_HARD" if layout_name == "kestral" else ""
    blueprint = next((node for node in candidates if node.get("name") == preferred), candidates[0])
    systems = {}
    for node in blueprint.findall("./systemList/*"):
        if node.get("start", "true") == "false":
            continue
        room = node.get("room")
        if room is not None:
            systems[room] = node.tag
    return blueprint.get("name", ""), systems


def png_size(raw: bytes) -> tuple[int, int]:
    if len(raw) < 24 or raw[:8] != b"\x89PNG\r\n\x1a\n" or raw[12:16] != b"IHDR":
        raise ValueError("Invalid ship PNG header")
    return struct.unpack(">II", raw[16:24])


UI_FONTS = ("c&c.font", "JustinFont10.font", "JustinFont11Bold.font")


def extract_fonts(pkg: Pkg, destination: Path) -> list[str]:
    """Keep original SIL bitmap fonts local; the runtime decodes their atlas.

    No font converter, system font installation or Godot import is required.
    """
    written = []
    for name in UI_FONTS:
        source = f"fonts/{name}"
        if source not in pkg.entries:
            continue
        raw = pkg.read(source)
        if len(raw) < 24 or raw[:5] != b"FONT\x01":
            raise ValueError(f"Unsupported native bitmap font: {source}")
        path = destination / source
        path.parent.mkdir(parents=True, exist_ok=True)
        # SIL .font is not Godot's BMFont .font. Load it via our runtime decoder
        # and keep the editor from trying to import it as an unrelated format.
        (path.parent / ".gdignore").write_text("", encoding="utf-8")
        path.write_bytes(raw)
        written.append(source)
    return written


def build_ship(pkg: Pkg, name: str, destination: Path, image_name: str | None = None,
               *, native_image_rect: dict | None = None) -> dict:
    import re
    image_name = image_name or name
    if not all(re.fullmatch(r'[A-Za-z0-9_-]+', part) for part in (name, image_name)):
        raise ValueError('Invalid ship asset identifier')
    key = name if image_name == name else f'{name}__{image_name}'
    layout = parse_layout(pkg.read(f"data/{name}.txt"))
    root = ET.fromstring(pkg.read(f"data/{name}.xml"))
    image_node = root.find("img")
    if image_node is None:
        raise ValueError(f"No ship image rectangle for {name}")
    layout["name"] = name
    layout["image_rect"] = {key: int(image_node.attrib[key]) for key in ("x", "y", "w", "h")}
    if native_image_rect:
        rectangle = {key: int(native_image_rect[key]) for key in ("x", "y", "w", "h")}
        if not (0 < rectangle["w"] <= 8192 and 0 < rectangle["h"] <= 8192):
            raise ValueError("Invalid native ship image dimensions")
        layout["image_rect"] = rectangle
        layout["image_rect_source"] = "native_ship_image"
    layout["blueprint"], layout["systems"] = system_rooms(pkg.read("data/blueprints.xml"), name)
    layout["weapon_mounts"] = [dict(node.attrib) for node in root.findall("./weaponMounts/mount")]
    candidates = [f"img/ship/{image_name}_base.png",
                  f"img/ships_noglow/{image_name}_base.png",
                  f"img/ships_glow/{image_name}_base.png"]
    available = [(path, pkg.read(path)) for path in candidates if path in pkg.entries]
    if not available:
        raise ValueError(f"No base image for {name}")
    # Glow and noglow sprites often have different transparent borders. Match
    # the dimensions FTL actually renders instead of stretching a cropped PNG
    # over the larger XML rectangle and extruding a second, smaller silhouette.
    rectangle = layout["image_rect"]
    expected_size = (rectangle["w"], rectangle["h"])
    image_path, image_bytes = next((entry for entry in available if png_size(entry[1]) == expected_size), available[0])
    layout["texture_size"] = list(png_size(image_bytes))
    layout["image_source_path"] = image_path
    destination.mkdir(parents=True, exist_ok=True)
    (destination / f"{key}.png").write_bytes(image_bytes)
    (destination / f"{key}.json").write_text(json.dumps(layout, indent=2), encoding="utf-8")
    return {"name": name, "rooms": len(layout["rooms"]), "doors": len(layout["doors"]),
            "blueprint": layout["blueprint"],
            "image_path": image_path}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="Path to your Steam or GOG ftl.dat")
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[1] / "local_game_data")
    parser.add_argument("--ship", action="append", dest="ships",
                        help="Ship layout name; repeat for more ships")
    args = parser.parse_args()
    pkg = Pkg(args.archive)
    ships = args.ships or ["kestral", "rebel_long"]
    manifest = {"source": str(args.archive), "ships": []}
    for ship in ships:
        manifest["ships"].append(build_ship(pkg, ship, args.output))
    ui_paths = [name for name in pkg.entries if name.endswith(".png") and (
        name.startswith(("img/statusUI/", "img/systemUI/", "img/icons/", "img/combatUI/"))
        or name in {"img/box_subsystems4.png", "img/box_weapons_bottom4.png",
                    "img/box_weapons_bottom_label.png", "img/box_weapons_autofire_base.png",
                    "img/Text_pause1.png", "img/Text_pause2.png"}
        or name in {f"img/misc/crosshairs_placed{slot}{variant}.png"
                    for slot in range(1,5) for variant in ("", "_yellow")})]
    for name in ui_paths:
        destination = args.output / "ui" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(pkg.read(name))
    manifest["ui_assets"] = len(ui_paths)
    manifest["fonts"] = extract_fonts(pkg, args.output)
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
