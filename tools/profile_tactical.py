"""Measure native counters and actual published files during a scoped QA run."""
import argparse
import json
import time
from pathlib import Path


def read_json(path):
    for _ in range(20):
        try:
            return json.loads(path.read_text(encoding='utf-8'))
        except (PermissionError,json.JSONDecodeError):
            time.sleep(.01)
    raise RuntimeError('Could not read profile state')


def measure(local,seconds):
    first=read_json(local/'bridge_status.json')['native_capture']['performance']
    changes={name:0 for name in ('screen_frame.png','hud_frame.png','screen_frame.rgba','hud_frame.rgba')}
    previous={name:(local/name).stat().st_mtime_ns if (local/name).exists() else 0 for name in changes}
    start=time.monotonic()
    while time.monotonic()-start<seconds:
        for name in changes:
            try: modified=(local/name).stat().st_mtime_ns
            except (FileNotFoundError,PermissionError): continue
            if modified!=previous[name]: changes[name]+=1;previous[name]=modified
        time.sleep(.003)
    elapsed=time.monotonic()-start
    latest=read_json(local/'bridge_status.json')
    last=latest['native_capture']['performance']
    native_seconds=(last['elapsed_ms']-first['elapsed_ms'])/1000
    counts={key:last[key]-first[key] for key in ('native_loops','native_swaps','frames','hud_frames','capture_ms','hud_ms','read_ms','loop_ms','bytes_sent')}
    return {'seconds':elapsed,'native_seconds':native_seconds,'native':counts,
        'native_fps':counts['native_swaps']/native_seconds,'capture_fps':counts['frames']/native_seconds,
        'hud_capture_fps':counts['hud_frames']/native_seconds,'capture_cpu_ms_per_frame':counts['capture_ms']/max(1,counts['frames']),
        'published_files':changes,'published_fps':{name:count/elapsed for name,count in changes.items()},'errors':latest['errors']}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds',type=float,default=10)
    parser.add_argument('--output',default='tactical-native-profile.json')
    parser.add_argument('--local',type=Path,default=Path(__file__).resolve().parents[1]/'local_game_data')
    args=parser.parse_args();report=measure(args.local,args.seconds)
    (args.local/args.output).write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))
