"""Prepare an isolated FTL lab. Activation must be explicitly requested."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

from lab_formats import apply_bps
from lab_settings import configure

STEAM_1614_SHA1 = 'c58e5283b2c1996fa36158265423f8c94f3a8954'
STEAM_169_SHA1 = 'eadd0a60dbf80c5a7c2a6879f8ae241afb553ade'
ROLLBACK_SHA256 = 'a1b70589c0614ee9aa9c1acd55af527bbec10f3e7af4640579b03ced0bd69f52'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, required=True)
    parser.add_argument('--lab', type=Path, required=True)
    parser.add_argument('--rollback', type=Path, required=True)
    parser.add_argument('--hyperspace', type=Path, required=True)
    parser.add_argument('--mod-manager', type=Path, required=True)
    parser.add_argument('--activate', action='store_true', help='Install loader and patched data into the isolated lab')
    args = parser.parse_args()
    game, lab = args.game.resolve(), args.lab.resolve()
    if game == lab or game in lab.parents or lab in game.parents:
        raise ValueError('Lab must be separate from the installed game directory')
    lab.mkdir(parents=True, exist_ok=True)
    marker = lab / 'ftlvr-lab.json'
    if any(lab.iterdir()) and not marker.exists():
        raise ValueError('Refusing to populate a nonempty, unrecognized lab')
    original = (game / 'FTLGame.exe').read_bytes()
    if hashlib.sha1(original).hexdigest() != STEAM_1614_SHA1:
        raise ValueError('Only the verified Steam Windows 1.6.14 build is supported by this lab preparer')
    rollback = args.rollback.read_bytes()
    if hashlib.sha256(rollback).hexdigest() != ROLLBACK_SHA256:
        raise ValueError('Rollback patch differs from the inspected official patch')
    patched = apply_bps(original, rollback)
    if hashlib.sha1(patched).hexdigest() != STEAM_169_SHA1:
        raise ValueError('Rollback output is not the expected Steam Windows 1.6.9 build')
    marker.write_text(json.dumps({'source_game': str(game), 'source_sha1': STEAM_1614_SHA1,
                                  'save_prefix': 'ftlvr', 'activated': False}, indent=2), encoding='utf-8')
    for name in ['FTLGame.exe', 'ftl.dat', 'bass.dll', 'bassmix.dll', 'steam_api.dll', 'steam_wrapper.dll']:
        if not (lab / name).exists():
            shutil.copy2(game / name, lab / name)
    (lab / 'FTLGame_1.6.9.prepared').write_bytes(patched)
    replacements = {}
    with zipfile.ZipFile(args.hyperspace / 'Hyperspace.ftl') as bundle:
        replacements['data/hyperspace.xml'] = bundle.read('data/hyperspace.xml')
    config = replacements['data/hyperspace.xml'].decode('utf-8-sig')
    config = re.sub(r'<saveFile>.*?</saveFile>', '<saveFile><prefix>ftlvr</prefix><inheritMode>2</inheritMode></saveFile>', config, flags=re.S)
    config = config.replace('<scripts/>', '<scripts><script>data/ftlvr_bridge.lua</script></scripts>')
    replacements['data/hyperspace.xml'] = config.encode('utf-8')
    replacements['data/ftlvr_bridge.lua'] = (Path(__file__).parents[1] / 'bridge/ftlvr_bridge.lua').read_bytes()
    mod_file = lab / 'tabletop-bridge.ftl'
    with zipfile.ZipFile(mod_file, 'w', zipfile.ZIP_DEFLATED) as output:
        for name, payload in replacements.items():
            output.writestr(name, payload)
    staging = lab / 'prepared-resources'
    staging.mkdir(exist_ok=True)
    shutil.copy2(game / 'ftl.dat', staging / 'ftl.dat')
    subprocess.run([str(args.mod_manager.resolve()), 'patch', '--data-dir', str(staging),
                    str((args.hyperspace / 'Hyperspace.ftl').resolve()), str(mod_file)], check=True)
    shutil.copy2(staging / 'ftl.dat', lab / 'ftl.vr.prepared')
    marker.write_text(json.dumps({'source_game': str(game), 'source_sha1': STEAM_1614_SHA1,
                                  'rollback_sha1': STEAM_169_SHA1, 'save_prefix': 'ftlvr',
                                  'activated': args.activate}, indent=2), encoding='utf-8')
    if args.activate:
        shutil.copy2(lab / 'FTLGame_1.6.9.prepared', lab / 'FTLGame.exe')
        shutil.copy2(lab / 'ftl.vr.prepared', lab / 'ftl.dat')
        binary_dir = args.hyperspace / 'Windows - Extract these files into where FTLGame.exe is'
        for name in ['Hyperspace.dll', 'xinput1_4.dll']:
            shutil.copy2(binary_dir / name, lab / name)
        configure(lab)
    print(json.dumps({'lab': str(lab), 'prepared_entries': len(replacements), 'activated': args.activate}))


if __name__ == '__main__':
    main()
