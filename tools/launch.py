"""Launch the verified isolated game and OpenXR client together on Windows."""
import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import time
import winreg
import zipfile
from datetime import datetime
from pathlib import Path
from lab_settings import configure

PROJECT = Path(__file__).resolve().parents[1]


def preflight(config, desktop=False):
    for name in ('lab', 'godot', 'hooks'):
        if not Path(config[name]).exists(): raise ValueError(f'Missing {name}: {config[name]}')
    for module in ('frida', 'PIL', 'numpy'):
        if importlib.util.find_spec(module) is None: raise ValueError(f'Missing Python dependency: {module}')
    lab = Path(config['lab'])
    marker = json.loads((lab/'ftlvr-lab.json').read_text())
    hooks = json.loads(Path(config['hooks']).read_text())
    if not all(name in hooks.get('rvas',{}) for name in ('GetShiftState','GetCtrlState','ForceAutofireFlag')):
        raise ValueError('Regenerate lab hooks.json with tools/resolve_hooks.py for controller modifiers')
    if not all(name in hooks.get('rvas',{}) for name in ('OnTextInput','OnTextEvent','TextInputOnRender','TextInputStart')):
        raise ValueError('Regenerate lab hooks.json with tools/resolve_hooks.py for native renaming')
    if not all(name in hooks.get('rvas',{}) for name in ('CommandGuiRenderStatic','CommandGuiRenderPause','TabbedWindowOnRender','ChoiceBoxOnRender','MouseControlOnRender','StarMapOnRender')):
        raise ValueError('Regenerate lab hooks.json with tools/resolve_hooks.py for live native HUD capture')
    if not marker.get('activated') or hashlib.sha1((lab/'FTLGame.exe').read_bytes()).hexdigest() != hooks['sha1']:
        raise ValueError('Lab is not activated or its executable fingerprint changed')
    if not (lab/'Hyperspace.dll').exists(): raise ValueError('Hyperspace is missing')
    status = PROJECT/'local_game_data/bridge_status.json'
    if status.exists():
        previous = json.loads(status.read_text())
        if previous.get('connected') and time.time()-previous.get('heartbeat',0)<3:
            raise ValueError('An FTL VR bridge is already running. Close that session first.')
    runtime = ''
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,r'SOFTWARE\Khronos\OpenXR\1') as key:
            runtime = winreg.QueryValueEx(key,'ActiveRuntime')[0]
    except OSError: pass
    if not desktop and ('steamxr' not in runtime.lower() or not Path(runtime).exists()):
        raise ValueError('Select SteamVR as the OpenXR runtime in SteamVR settings, then retry')
    return {'lab':str(lab), 'runtime':runtime, 'mode':'desktop' if desktop else 'VR'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,default=PROJECT/'local_game_data/launcher.json')
    parser.add_argument('--desktop',action='store_true')
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--smoke',action='store_true',help='Desktop launch and graceful exit after 3 seconds')
    args=parser.parse_args()
    if args.smoke: args.desktop=True
    config=json.loads(args.config.read_text())
    print(json.dumps(preflight(config,args.desktop),indent=2),flush=True)
    if args.check: return
    local=PROJECT/'local_game_data'; local.mkdir(exist_ok=True)
    lab=Path(config['lab'])
    # Snapshot only this mod's separate save profile before each launch.
    saves=Path(os.environ['USERPROFILE'])/'Documents/My Games/FasterThanLight'
    backup=lab/'save-backups'; backup.mkdir(exist_ok=True)
    with zipfile.ZipFile(backup/(datetime.now().strftime('%Y%m%d-%H%M%S')+'.zip'),'w',zipfile.ZIP_DEFLATED) as archive:
        for path in saves.glob('hs_ftlvr_*'):
            if path.is_file(): archive.write(path,path.name)
        if (lab/'settings.ini').exists(): archive.write(lab/'settings.ini','settings.ini')
    configure(lab)
    stop=local/'launcher.stop'
    stop.unlink(missing_ok=True)
    logs=local/'logs'; logs.mkdir(exist_ok=True)
    with (logs/'bridge.log').open('w') as bridge_log, (logs/'client.log').open('w') as client_log:
        bridge=subprocess.Popen([sys.executable,str(PROJECT/'tools/run_bridge.py'),
            '--lab',str(lab),'--hooks',config['hooks'],'--allow-input','--stop-file',str(stop)],
            cwd=PROJECT,stdout=bridge_log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        client=None
        try:
            deadline=time.monotonic()+55
            status=local/'bridge_status.json'
            while time.monotonic()<deadline:
                if bridge.poll() is not None: raise RuntimeError('Game bridge failed; see local_game_data/logs/bridge.log')
                try:
                    value=json.loads(status.read_text())
                    if value.get('connected') and value.get('live_state_received') and value.get('capture_received') and time.time()-value['heartbeat']<2: break
                except (OSError,ValueError): pass
                time.sleep(.1)
            else: raise TimeoutError('Game bridge did not become ready')
            command=[config['godot'],'--path',str(PROJECT),'--log-file',str(logs/'godot.log')]
            if args.desktop: command+=['--xr-mode','off']
            if args.smoke: command+=['--quit-after','180','--max-fps','60']
            command+=['--']+(['--desktop'] if args.desktop else ['--require-vr'])
            print('Starting client. Closing it saves and exits the isolated FTL game.',flush=True)
            client=subprocess.Popen(command,cwd=PROJECT,stdout=client_log,stderr=subprocess.STDOUT)
            while client.poll() is None and bridge.poll() is None: time.sleep(.25)
            if bridge.poll() is not None and client.poll() is None:
                client.terminate()
            if client.poll() not in (None,0):
                raise RuntimeError('VR client exited with an error; see local_game_data/logs/client.log')
        finally:
            stop.touch()
            try: bridge.wait(timeout=15)
            except subprocess.TimeoutExpired:
                bridge.terminate(); bridge.wait(timeout=5)
            if client and client.poll() is None: client.terminate(); client.wait(timeout=5)


if __name__=='__main__':
    try: main()
    except Exception as error:
        print('FTL VR:',error,file=sys.stderr)
        sys.exit(1)
