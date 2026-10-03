"""Run the isolated FTL process bridge. No global desktop input is generated."""
import argparse
import hashlib
import json
import os
import queue
import struct
import subprocess
import threading
import time
import uuid
from collections import deque
from pathlib import Path

import frida
from PIL import Image
from extract_ftl import Pkg, build_ship
from hud_alpha import clear_world_alpha


def atomic_json(path, value):
    temporary = path.with_suffix('.pending')
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
    replace_when_available(temporary, path)


def replace_when_available(source, destination):
    # Windows readers may briefly deny replacement while opening a frame/state.
    for attempt in range(20):
        try:
            os.replace(source, destination)
            return
        except PermissionError:
            time.sleep(0.005)
    os.replace(source, destination)


FRAME_HEADER = struct.Struct('<4sIIIIQd')


def raw_frame_bytes(image, sequence, captured_at):
    """Top-down RGBA; dimensions describe transport, never native input space."""
    if image.mode != 'RGBA': image = image.convert('RGBA')
    width, height = image.size
    return FRAME_HEADER.pack(b'FVR1', 1, width, height, 4, sequence, captured_at) + image.tobytes()


class FramePublisher:
    """Live frames avoid PNG compression; occasional PNGs support capture tools."""
    def __init__(self, local):
        self.local = local
        self.lock = threading.Lock()
        self.sequences = {}
        self.preview_times = {}
        self.previews = {}
        self.closed = threading.Event()
        self.preview_worker = threading.Thread(target=self._preview_frames,daemon=True)
        self.preview_worker.start()

    def publish(self, name, image, captured_at):
        with self.lock:
            sequence = self.sequences.get(name, 0) + 1
            self.sequences[name] = sequence
            temporary = self.local / (name + '.pending.rgba')
            temporary.write_bytes(raw_frame_bytes(image, sequence, captured_at))
            replace_when_available(temporary, self.local / (name + '.rgba'))
            now = time.monotonic()
            if now - self.preview_times.get(name, 0) >= 1.0:
                self.previews[name] = image
                self.preview_times[name] = now

    def _preview_frames(self):
        while not self.closed.wait(0.02):
            with self.lock:
                previews, self.previews = self.previews, {}
            for name, image in previews.items():
                temporary = self.local / (name + '.pending.png')
                image.save(temporary, compress_level=1)
                replace_when_available(temporary, self.local / (name + '.png'))

    def close(self):
        self.closed.set()
        self.preview_worker.join(timeout=2)


def decode_state_line(line):
    prefix = 'FTLVR_STATE '
    if prefix not in line:
        return None
    content = line.split(prefix, 1)[1].strip()
    result = json.loads(content)
    if result.get('protocol') != 2 or result.get('source') != 'hyperspace':
        raise ValueError('Unsupported FTL snapshot protocol')
    if not isinstance(result.get('shots'), list):
        result['shots'] = []
    if not isinstance(result.get('projectiles'), list):
        result['projectiles'] = []
    for side in ('player','enemy'):
        if isinstance(result.get(side),dict):
            for field in ('rooms','crew','weapons','doors','drones','drone_equipment','system_status'):
                if not isinstance(result[side].get(field),list): result[side][field]=[]
            for room in result[side]['rooms']:
                for field in ('fire_tiles','breach_tiles'):
                    if not isinstance(room.get(field),list): room[field]=[]
    if isinstance(result.get('dialog'),dict) and not isinstance(result['dialog'].get('choices'),list):
        result['dialog']['choices']=[]
    # vCrewList ownership/current-ship membership can differ during boarding.
    # Render and select each surviving crew member on its actual current ship.
    crew_by_id={c['id']:c for side in ('player','enemy') for c in (result.get(side) or {}).get('crew',[])}
    for side,ship_id in (('player',0),('enemy',1)):
        if isinstance(result.get(side),dict):
            result[side]['crew']=[c for c in crew_by_id.values() if c.get('ship')==ship_id]
    drones_by_id={d['id']:d for side in ('player','enemy') for d in (result.get(side) or {}).get('drones',[])}
    for side,ship_id in (('player',0),('enemy',1)):
        if isinstance(result.get(side),dict):
            result[side]['drones']=[d for d in drones_by_id.values() if d.get('space')==ship_id]
    return result


def room_pixel(state, ship, room_id):
    data = state.get(ship) or {}
    room = next((r for r in data.get('rooms', []) if int(r['id']) == int(room_id)), None)
    if room is None:
        raise ValueError('Room is not in the current FTL ship')
    origin = state[ship + '_origin']
    center = room['center']
    return round(origin['x'] + center['x']), round(origin['y'] + center['y'])


def full_screen_capture(state):
    # Native shops, upgrades, crew and equipment are world panels, never HUDs.
    # An in-run window owns its pixels even if the native menu flag also sets
    # ui_mode to menu. Initial/hangar screens keep their full headset view.
    return not state.get('ready') or (state.get('ui_mode','menu') == 'menu' and not state.get('panel_open'))


def world_gameplay_available(state):
    """Tactical is a view of gameplay; real native modal windows block commands."""
    return bool(state.get('ready') and not state.get('blocking_ui') and not state.get('event_open') and not state.get('map_open')
                and not state.get('panel_open') and not state.get('transition')
                and (state.get('ui_mode')=='game' or
                     (state.get('tactical') and state.get('ui_mode')=='screen')))


def remove_enemy_hud(pixels):
    """Remove the entire native target frame, even on cached/out-of-combat HUDs."""
    result=pixels.copy()
    result[40:602,872:,3]=0
    return result


def remove_pause_overlay(pixels):
    """The VR client shows pause from native state, never from a cached glyph."""
    result=pixels.copy()
    result[520:598,510:770,3]=0
    return result


def native_window_frame(pixels):
    """Keep native window contours, including detached boxes, and discard HUD.

    The native renderer already clips ships and environment. Edge-connected
    cleared black becomes transparent; enclosed black window ink is retained.
    SELL includes a detached drop box and an open gap at screen center. Select
    substantial framed components, then keep their enclosed ink; requiring an
    opaque center pixel loses SELL, while filling whole bounds leaks PAUSED.
    """
    import numpy as np
    result=pixels.copy()
    # At the fixed native 1280x720 viewport, floating window tabs start at
    # y=83. Remove the separate top HUD before finding components: its jump
    # button glow can touch the tab frame and otherwise expand the crop.
    result[:80,:,3]=0
    # Native windows have bright connected borders. The dimmed background HUD
    # can overlap a SELL drop box; exclude its dark connector pixels while
    # locating frames, then retain the original ink inside each chosen frame.
    opaque=np.max(result[:,:,:3],axis=2)>=80
    opaque[:80,:]=False
    center=(opaque.shape[1]//2,opaque.shape[0]//2)
    # Union horizontal runs rather than flood filling every window pixel in
    # Python: large opaque windows must retain the bridge's 10 Hz cadence.
    parents,runs,previous=[],[],[]
    def root(index):
        while parents[index]!=index:
            parents[index]=parents[parents[index]]
            index=parents[index]
        return index
    for y,row in enumerate(opaque):
        changes=np.flatnonzero(np.diff(np.pad(row.astype(np.int8),(1,1))))
        current=[]
        cursor=0
        for x0,x1 in zip(changes[::2],changes[1::2]):
            index=len(parents)
            parents.append(index)
            current.append((x0,x1,index))
            runs.append((y,x0,x1,index))
            while cursor<len(previous) and previous[cursor][1]<=x0: cursor+=1
            k=cursor
            while k<len(previous) and previous[k][0]<x1:
                a,b=root(index),root(previous[k][2])
                if a!=b: parents[b]=a
                k+=1
        previous=current
    bounds={}
    for y,x0,x1,index in runs:
        key=root(index)
        if key not in bounds: bounds[key]=[x0,y,x1,y+1,0]
        box=bounds[key]
        box[0]=min(box[0],x0);box[1]=min(box[1],y)
        box[2]=max(box[2],x1);box[3]=max(box[3],y+1);box[4]+=x1-x0
    candidates=[b for b in bounds.values() if b[0]<=center[0]<b[2] and b[1]<=center[1]<b[3]
                and b[2]-b[0]>=100 and b[3]-b[1]>=80]
    if not candidates:
        result[:,:,3]=0
        return result
    frame=max(candidates,key=lambda box:box[4])
    # SELL's drop target and the original item information windows are
    # separate native components. Keep their whole frames as well. Native
    # crew/weapon HUD widgets are narrower or below the window area.
    windows=[frame]+[b for b in bounds.values() if 80<=b[1]<600 and b[3]<=720 and
        b[2]-b[0]>=120 and b[3]-b[1]>=60 and b[4]>=3000 and
        not (b[0]>=875 and b[1]<100 and b[3]-b[1]>300)]
    keep=np.zeros(opaque.shape,dtype=bool)
    for x0,y0,x1,y1,_ in windows:keep[y0:y1,x0:x1]=True
    # Fill only holes enclosed by the native bright window contours, rather
    # than the entire bounding rectangle. The open gap below SELL/crew windows
    # contains the dim native PAUSED glyph; it belongs to the background.
    contour=np.zeros_like(result)
    contour[(opaque & keep),:3]=255
    result[:,:,3]=clear_world_alpha(contour)[:,:,3]
    return result


def translate_command(command, state):
    modifiers=command.get('data',{}).get('modifiers',{})
    if not isinstance(modifiers,dict) or any(k not in ('shift','control') for k in modifiers):
        raise ValueError('Unsupported modifier')
    result=_translate_command(command,state)
    for instruction in result:
        instruction['modifiers']={key:False if command['action']=='system_power' else bool(modifiers.get(key,False))
                                  for key in ('shift','control')}
    return result


def _translate_command(command, state):
    action, data = command['action'], command.get('data', {})
    if action=='text_input':
        entry=state.get('text_entry') or {}
        if not entry.get('active') or not data.get('entry_id') or str(data['entry_id'])!=str(entry.get('id')):
            raise ValueError('Native rename input is no longer active')
        operation=data.get('op')
        if operation=='insert':
            value=data.get('text','')
            if not isinstance(value,str) or not 1<=len(value)<=32 or any(not c.isprintable() for c in value):
                raise ValueError('Invalid rename text')
            return [{'type':'text','codepoint':ord(character),'entry_id':entry.get('id')} for character in value]
        if operation=='cancel':
            return [{'type':'text_cancel','entry_id':entry.get('id')}]
        events={'confirm':0,'clear':2,'backspace':3,'delete':4,'left':5,'right':6,'home':7,'end':8}
        if operation not in events: raise ValueError('Unsupported text operation')
        return [{'type':'text_event','event':events[operation],'entry_id':entry.get('id')}]
    if action == 'event_choice':
        dialog=state.get('dialog') or {}
        index=int(data['index'])
        choices=dialog.get('choices',[])
        if not state.get('event_open') or str(data.get('dialog_id')) != str(dialog.get('id')):
            raise ValueError('Event dialog changed before selection')
        if not 0 <= index < min(8,len(choices)) or not choices[index].get('enabled',True):
            raise ValueError('Event choice unavailable')
        return [{'type':'key','key':49+index}]
    if action=='navigate'  and data.get('screen') in ('menu','tactical'):
        return [{'type':'key','key':27 if data['screen']=='menu' else 289}]
    if action in ('ui_mouse', 'ui_move'):
        x, y = int(data['x']), int(data['y'])
        if not (0 <= x < 1280 and 0 <= y < 720):
            raise ValueError('UI coordinates outside the original game canvas')
        return [{'type': 'move' if action == 'ui_move' else 'mouse', 'x': x, 'y': y,
                 'button': data.get('button', 'left'), 'phase': data.get('phase', 'click')}]
    if action == 'key':
        allowed = {13,27,32,47,97,98,99,100,101,102,103,104,105,106,107,108,
                   109,110,112,113,114,115,116,117,118,119,120,121,122,
                   48,49,50,51,52,53,54,55,56,57,289,290,291}
        key = int(data['key'])
        if key not in allowed:
            raise ValueError('Unsupported game hotkey')
        return [{'type': 'key', 'key': key}]
    if action == 'cancel':
        if not world_gameplay_available(state): return [{'type':'key','key':27}]
        return [{'type':'mouse','button':'right','phase':'click','x':640,'y':719},
                {'type':'mouse','button':'left','phase':'up','x':640,'y':719},
                {'type':'mouse','button':'left','phase':'click','x':640,'y':719}]
    if not world_gameplay_available(state):
        raise ValueError('World command requires active gameplay')
    if action == 'pause':
        return [] if bool(data['paused']) == bool(state['paused']) else [{'type': 'key', 'key': 32}]
    if action == 'move_crew' or action == 'select_crew':
        crew = next((c for side in ('player','enemy') for c in (state.get(side) or {}).get('crew',[])
                     if str(c['id']) == str(data['crew_id'])), None)
        if not crew or not crew['controllable'] or crew['ship'] not in (0,1):
            raise ValueError('Crew is not controllable on a current ship')
        side='player' if crew['ship']==0 else 'enemy'
        origin = state[side+'_origin']
        commands = [{'type':'mouse','button':'left','phase':'click',
                     'x':round(origin['x']+crew['x']), 'y':round(origin['y']+crew['y'])}]
        if action == 'move_crew':
            if crew.get('selected'): commands=[]
            x,y = room_pixel(state, side, data['room_id'])
            commands.append({'type':'mouse','button':'right','phase':'click','x':x,'y':y})
        return commands
    if action == 'target_room':
        target=state.get('targeting') or {}
        active=target.get('active',int(state.get('weapon_selected',-1))>=0)
        side=data.get('ship','enemy')
        ships=target.get('ships',['enemy'])
        if (side=='enemy' and not state.get('combat')) or not active or side not in ships:
            raise ValueError('Select an actual FTL weapon or targeted system before targeting this ship')
        x,y = room_pixel(state, side, data['room_id'])
        return [{'type':'mouse','button':'left','phase':data.get('phase','click'),'x':x,'y':y}]
    if action == 'system_power':
        system_id=data.get('system_id')
        system_key=data.get('system_key')
        direction=data.get('direction')
        if direction not in (-1,1): raise ValueError('System power changes must be one native click')
        rows=(state.get('player') or {}).get('system_status',[])
        row=next((r for r in rows if (system_id is not None and r.get('id')==int(system_id)) or
                  (system_id is None and system_key and r.get('key')==system_key)),None)
        if not row or not row.get('powerable') or not row.get('power_button'):
            raise ValueError('System power control is unavailable in the native game')
        point=row['power_button']
        return [{'type':'mouse','button':'left' if direction>0 else 'right','phase':'click',
                 'x':round(point['x']),'y':round(point['y'])}]
    if action == 'door_toggle':
        if data.get('ship','player') != 'player':
            raise ValueError('Only doors on the player ship are controllable')
        door=next((d for d in (state.get('player') or {}).get('doors',[])
                   if int(d['id'])==int(data['door_id'])),None)
        if not door or not door.get('controllable',False):
            raise ValueError('Door is unavailable or locked in the native game')
        origin=state['player_origin']
        return [{'type':'mouse','button':'left','phase':'click',
                 'x':round(origin['x']+door['x']),'y':round(origin['y']+door['y'])}]
    if action == 'navigate':
        screen = data['screen']
        if screen in ('jump','ship','store') and not state.get('navigation',{}).get(screen,False):
            raise ValueError('Navigation action is unavailable in the current game state')
        if screen == 'tactical':
            return [{'type':'key','key':289}]
        if screen == 'menu':
            return [{'type':'key','key':27}]
        if screen == 'jump':
            point = state['jump_button']
            return [{'type':'mouse','button':'left','x':int(point['x'])+25,'y':int(point['y'])+15}]
        if screen == 'ship':
            point = state['ship_button']
            return [{'type':'mouse','button':'left','x':int(point['x'])+15,'y':int(point['y'])+15}]
        if screen == 'store':
            return [{'type':'key','key':291}]
    raise ValueError(f'Unsupported command: {action}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lab', type=Path, required=True)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--hooks', type=Path, required=True)
    parser.add_argument('--seconds', type=float, default=0, help='Bounded diagnostic run; zero keeps bridge running')
    parser.add_argument('--pid', type=int, help='Attach only to this verified lab PID instead of launching')
    parser.add_argument('--allow-input', action='store_true', help='Enable commands from the VR client')
    parser.add_argument('--stop-file',type=Path,help='Stop when this launcher-owned file appears')
    args = parser.parse_args()
    lab = args.lab.resolve()
    marker = json.loads((lab / 'ftlvr-lab.json').read_text())
    if not marker.get('activated'):
        raise ValueError('Lab is prepared but not activated')
    hooks = json.loads(args.hooks.read_text())
    executable = lab / 'FTLGame.exe'
    if hashlib.sha1(executable.read_bytes()).hexdigest() != hooks['sha1']:
        raise ValueError('Lab executable fingerprint changed; refusing to attach')
    local = args.project.resolve() / 'local_game_data'
    local.mkdir(exist_ok=True)
    status_path = local / 'bridge_status.json'
    command_path = local / 'commands.jsonl'
    frame_queue = queue.Queue(maxsize=1)
    hud_queue = queue.Queue(maxsize=1)
    log_queue = queue.Queue()
    stop = threading.Event()
    current = {}
    native_text_entry={'active':False}
    native_power_buttons={}
    power_buttons_received=0.0
    capture_size = [1280,720]
    state_lock = threading.Lock()
    errors = []
    assets = Pkg(Path(marker['source_game'])/'ftl.dat')
    prepared_ships = set()
    recent_events = deque(maxlen=128)
    bridge_session = uuid.uuid4().hex
    publisher = FramePublisher(local)
    (local/'.gdignore').touch()

    def on_message(message, binary):
        if message['type'] == 'error':
            errors.append(message.get('stack', str(message)))
            return
        payload = message.get('payload', {})
        if payload.get('type') in ('frame','hud_frame') and binary:
            if payload['type']=='frame':
                capture_size[:] = [payload.get('native_width',payload['width']),
                                   payload.get('native_height',payload['height'])]
            target=hud_queue if payload['type']=='hud_frame' else frame_queue
            # Each stream keeps its newest sample. A regular screen cannot
            # displace the supplemental HUD captured immediately before it.
            try: target.put_nowait((payload,binary))
            except queue.Full:
                try: target.get_nowait()
                except queue.Empty: pass
                try: target.put_nowait((payload,binary))
                except queue.Full: pass
        else:
            log_queue.put(payload)

    def encode_frames(source_queue):
        last_hud_image = None
        while not stop.is_set():
            try: payload,binary = source_queue.get(timeout=0.05)
            except queue.Empty: continue
            try:
                image = Image.frombytes('RGBA',(payload['width'],payload['height']),binary).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                captured_at=payload.get('captured_at',time.time())
                with state_lock:
                    snapshot=dict(current)
                # The Tactical stream retains the complete native screen at a
                # smaller resolution. Its independent worker never waits for
                # HUD flood-fill or PNG compression.
                tactical_only=bool(snapshot.get('tactical') and not any(snapshot.get(key) for key in ('map_open','event_open','panel_open','blocking_ui')))
                if payload['type']=='frame' and tactical_only and payload.get('supplemental_hud'):
                    publisher.publish('screen_frame',image,captured_at)
                    continue
                if image.size != (1280,720): image = image.resize((1280,720),Image.Resampling.NEAREST)
                # Preserve the original UI RGB. Make only the cleared black world transparent.
                rgb = image.convert('RGB')
                import numpy as np
                pixels = np.array(image)
                clean_pixels=None
                panel_pixels=None
                if payload['type']=='hud_frame':
                    if full_screen_capture(snapshot): continue
                    last_hud_image=Image.fromarray(remove_enemy_hud(clear_world_alpha(pixels)))
                    publisher.publish('hud_frame',last_hud_image,captured_at)
                    with state_lock: current['capture_full_screen']=False
                    continue
                controller_screen=bool(snapshot.get('map_open') or snapshot.get('tactical'))
                event_open=bool(snapshot.get('event_open'))
                panel_open=bool(snapshot.get('panel_open'))
                full_screen=full_screen_capture(snapshot)
                # Native windows stay original. Gameplay never promotes a colored
                # world/jump frame into an opaque head-locked screen.
                if controller_screen:
                    publisher.publish('screen_frame',image,captured_at)
                if event_open:
                    publisher.publish('event_frame',rgb.convert('RGBA'),captured_at)
                if panel_open:
                    panel_pixels=native_window_frame(pixels)
                    publisher.publish('panel_frame',Image.fromarray(panel_pixels),captured_at)
                # This original frame still supplies map/dialog/window pixels.
                # Its independent HUD sample is processed by its own worker.
                if payload.get('supplemental_hud') and not full_screen:
                    continue
                if full_screen:
                    image=rgb.convert('RGBA')
                elif controller_screen or event_open or panel_open or snapshot.get('transition'):
                    if last_hud_image is None:
                        if panel_open:
                            clean_pixels=clear_world_alpha(pixels)
                            hud=clean_pixels.copy()
                            hud[panel_pixels[:,:,3]>0,3]=0
                            last_hud_image=Image.fromarray(remove_enemy_hud(hud))
                        elif event_open:
                            pixels=clear_world_alpha(pixels)
                            left=313 if (snapshot.get('dialog') or {}).get('centered',True) else 163
                            pixels[138:528,left:left+650,3]=0
                            last_hud_image=Image.fromarray(remove_enemy_hud(pixels))
                        else:
                            last_hud_image=Image.new('RGBA',(1280,720),(0,0,0,0))
                    image=last_hud_image.copy()
                else:
                    # A transition can race a snapshot by one frame. Retain the
                    # last UI until the native world is clipped; never flash it.
                    middle=np.any(pixels[180:490,400:850,:3]!=0,axis=2)
                    if float(middle.mean())>0.18:
                        if last_hud_image is None: continue
                        image=last_hud_image.copy()
                    else:
                        pixels=clear_world_alpha(pixels)
                        image=Image.fromarray(remove_enemy_hud(pixels))
                        last_hud_image=image.copy()
                if not full_screen:
                    image=Image.fromarray(remove_pause_overlay(remove_enemy_hud(np.array(image))))
                with state_lock:
                    current['capture_full_screen']=full_screen
                publisher.publish('hud_frame',image,captured_at)
            except Exception as error:
                errors.append('Frame encode: '+str(error))

    workers=[threading.Thread(target=encode_frames,args=(source,),daemon=True)
             for source in (frame_queue,hud_queue)]
    for worker in workers: worker.start()
    process = None
    if args.pid is None:
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
        process = subprocess.Popen([str(executable),'--force-opengl'],cwd=lab,
            startupinfo=startup,creationflags=subprocess.CREATE_NO_WINDOW)
        pid = process.pid
    else:
        pid = args.pid
        # Verify the attached process is this lab executable, not a different FTL copy.
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD]
        kernel.OpenProcess.restype=wintypes.HANDLE
        kernel.QueryFullProcessImageNameW.argtypes=[wintypes.HANDLE,wintypes.DWORD,wintypes.LPWSTR,ctypes.POINTER(wintypes.DWORD)]
        kernel.CloseHandle.argtypes=[wintypes.HANDLE]
        handle=kernel.OpenProcess(0x1000,False,pid)
        buffer=ctypes.create_unicode_buffer(32768); count=wintypes.DWORD(len(buffer))
        try:
            if not handle or not kernel.QueryFullProcessImageNameW(handle,0,buffer,ctypes.byref(count)) or Path(buffer.value).resolve()!=executable:
                raise ValueError('PID does not belong to the verified isolated lab')
        finally:
            if handle: kernel.CloseHandle(handle)
    print('FTLVR_LAB_PID',pid,flush=True)
    session=None
    start=time.monotonic()
    command_offset=command_path.stat().st_size if command_path.exists() else 0
    log_offset=0
    native_capture_status={}
    capture_status_received=0.0
    supplemental_enabled=None
    pending_log=''
    try:
        time.sleep(1)
        session=frida.attach(pid)
        agent_source=(Path(__file__).parents[1]/'bridge/agent.js').read_text()
        hooks['capture_interval_ms']=100
        script=session.create_script(agent_source.replace('CONFIG_PLACEHOLDER',json.dumps(hooks)))
        script.on('message',on_message)
        script.load()
        if process:
            # Install native hooks after Hyperspace has finished its own detours.
            boot_deadline = time.monotonic()+45
            while time.monotonic()<boot_deadline:
                boot_log=lab/'FTL.log'
                if boot_log.exists() and 'Running Game!' in boot_log.read_text(errors='replace'):
                    break
                if process.poll() is not None: raise RuntimeError('Lab exited during startup')
                time.sleep(0.1)
            else: raise TimeoutError('FTL did not finish startup')
        script.exports_sync.start()
        while not stop.is_set() and (not args.seconds or time.monotonic()-start<args.seconds):
            if args.stop_file and args.stop_file.exists(): break
            if process and process.poll() is not None: break
            log_path=lab/'FTL_HS.log'
            if not log_path.exists(): log_path=lab/'ftl_hs.log'
            if log_path.exists():
                if log_path.stat().st_size < log_offset:
                    log_offset=0; pending_log=''; recent_events.clear()
                with log_path.open('r',encoding='utf-8',errors='replace') as stream:
                    stream.seek(log_offset)
                    pending_log+=stream.read()
                    log_offset=stream.tell()
                lines=pending_log.split('\n'); pending_log=lines.pop()
                latest=None; shots=[]
                for line in lines:
                    try: state=decode_state_line(line)
                    except (ValueError,json.JSONDecodeError) as error: errors.append(str(error)); continue
                    if state:
                        latest=state; shots.extend(state.get('shots',[]))
                    elif 'FTLVR_ERROR' in line: errors.append(line.strip())
                if latest:
                    enable_supplemental=bool(latest.get('ready') and latest.get('ui_mode')!='menu')
                    presentation='tactical' if latest.get('tactical') and not any(latest.get(key) for key in ('map_open','event_open','panel_open','blocking_ui')) else ('game' if enable_supplemental and not any(latest.get(key) for key in ('map_open','event_open','panel_open')) else 'window')
                    capture_mode=(enable_supplemental,presentation)
                    if supplemental_enabled!=capture_mode:
                        script.exports_sync.capturemode({'enabled':enable_supplemental,'presentation':presentation})
                        supplemental_enabled=capture_mode
                    if time.monotonic()-power_buttons_received<=1:
                        for row in (latest.get('player') or {}).get('system_status',[]):
                            point=native_power_buttons.get(str(int(row['id'])))
                            if point: row['power_button']=dict(point)
                    recent_events.extend(shots)
                    for side in ('player','enemy'):
                        ship=latest.get(side)
                        if ship:
                            layout, image_name=ship['layout'],ship['image']
                            key=layout if layout==image_name else f'{layout}__{image_name}'
                            ship['asset_key']=key
                            if key not in prepared_ships:
                                build_ship(assets,layout,local,image_name,native_image_rect=ship.get('ship_image'))
                                prepared_ships.add(key)
                    with state_lock:
                        latest['capture_full_screen']=current.get('capture_full_screen',False)
                        current.clear(); current.update(latest); current['shots']=list(recent_events)
                        current['text_entry']=dict(native_text_entry)
                        current['bridge_session']=bridge_session
                        current['bridge_time_unix']=time.time()
                        atomic_json(local/'live_state.json',current)
            while not log_queue.empty():
                payload=log_queue.get()
                if payload.get('type')=='text_entry':
                    native_text_entry=dict(payload['value'])
                    with state_lock:
                        current['text_entry']=dict(native_text_entry)
                    continue
                if payload.get('type')=='system_power_buttons':
                    width,height=payload['width'],payload['height']
                    native_power_buttons={key:{'x':point['x']*1280/width,'y':point['y']*720/height}
                                          for key,point in payload['buttons'].items()
                                          if 0<=point['x']<width and 0<=point['y']<height}
                    power_buttons_received=time.monotonic()
                    continue
                print('FTLVR_AGENT',json.dumps(payload),flush=True)
                if payload.get('type','').endswith('error'): errors.append(str(payload))
            if args.allow_input and command_path.exists():
                with command_path.open('r',encoding='utf-8') as stream:
                    stream.seek(command_offset)
                    for line in stream:
                        try:
                            command=json.loads(line)
                            if not -1 <= time.time()-float(command.get('time_unix',0)) <= 3: continue
                            with state_lock: instructions=translate_command(command,current)
                            for instruction in instructions:
                                instruction['id']=command.get('id',time.time_ns())
                                if 'x' in instruction:
                                    instruction['x']=round(instruction['x']*capture_size[0]/1280)
                                    instruction['y']=round(instruction['y']*capture_size[1]/720)
                                script.exports_sync.command(instruction)
                        except Exception as error:
                            errors.append('Command rejected: '+str(error))
                    command_offset=stream.tell()
            if time.monotonic()-capture_status_received>=1:
                native_capture_status=script.exports_sync.status()
                capture_status_received=time.monotonic()
            atomic_json(status_path,{'pid':pid,'connected':True,'input_enabled':args.allow_input,
                'live_state_received':bool(current) and time.time()-current.get('bridge_time_unix',0)<2,
                'capture_received':any((local/name).exists() and time.time()-(local/name).stat().st_mtime<2 for name in ('hud_frame.rgba','hud_frame.png')),
                'errors':errors[-10:],'heartbeat':time.time(),'native_capture':native_capture_status})
            time.sleep(0.02)
    finally:
        stop.set()
        for worker in workers: worker.join(timeout=2)
        publisher.close()
        if process and process.poll() is None:
            try:
                script.exports_sync.command({'type':'key','key':290,'id':'save-and-exit'})
                process.wait(timeout=8)
            except Exception:
                process.terminate(); process.wait(timeout=10)
                errors.append('Graceful exit failed; last FTL autosave remains available')
        if session:
            try: session.detach()
            except frida.InvalidOperationError: pass
        atomic_json(status_path,{'pid':pid,'connected':False,'errors':errors[-10:],'heartbeat':time.time()})
    if errors: print('FTLVR_ERRORS',json.dumps(errors[-10:]),flush=True)


if __name__=='__main__':
    main()
