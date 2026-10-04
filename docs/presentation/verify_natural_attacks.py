"""Record actual iPad simulator attack playback for every installed combat actor.

Run after building the app. Outputs are separate from player saves; all launches
use the isolated preview and the production combat-presentation event entry point.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = 'com.wsysangyoung.DescentAuthorized'
parser = argparse.ArgumentParser()
parser.add_argument('--app', required=True)
parser.add_argument('--device', default='4191ECDD-20C0-413F-AE31-A05D3AD8897C')
parser.add_argument('--output', required=True)
parser.add_argument('--quality', choices=['low', 'medium', 'high'], default='medium')
parser.add_argument('--rooms', nargs='*')
parser.add_argument('--skip-complete', action='store_true')
args = parser.parse_args()
os.environ['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'

def sim(*command):
    return subprocess.check_output(['xcrun', 'simctl', *command], text=True).strip()

sim('install', args.device, args.app)
container = Path(sim('get_app_container', args.device, BUNDLE, 'data'))
contracts = json.loads((ROOT/'docs/final-3d-integration/room-contracts.json').read_text())
rooms = ['floor09_archive_redesign', 'floor08_residue_isolation', 'floor08_administrator_observatory']
rooms += [r['resource'] for r in contracts]
if args.rooms:
    assert set(args.rooms).issubset(rooms), 'Unknown combat room requested'
    rooms = args.rooms
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
results = []
for room in rooms:
    dest = out / room / args.quality
    dest.mkdir(parents=True, exist_ok=True)
    if args.skip_complete and (dest/'report.json').exists():
        results.append(json.loads((dest/'report.json').read_text()))
        continue
    target = container/'Documents/AttackMotionDiagnostics'/room/args.quality
    report = target/'report.json'
    if report.exists():
        report.unlink()
    launch_args = ['--floor9-preview', '--boss', '--graphics-'+args.quality, '--attack-motion-diagnostics']
    if room == 'floor08_residue_isolation': launch_args.append('--floor8-residue')
    elif room == 'floor08_administrator_observatory': launch_args.append('--floor8-boss')
    elif room != 'floor09_archive_redesign': launch_args += ['--final-room', room]
    launch_epoch = time.time()
    sim('launch', '--terminate-running-process', args.device, BUNDLE, *launch_args)
    log = (dest/'video.log').open('w')
    video_start = time.time()
    recording = subprocess.Popen(['xcrun', 'simctl', 'io', args.device, 'recordVideo',
                                  '--codec=h264', '--force', str(dest/'playback.mp4')],
                                 stdout=log, stderr=log)
    try:
        while time.time() - launch_epoch < 120:
            if report.exists():
                data = json.loads(report.read_text())
                if data.get('complete'): break
            time.sleep(.25)
        else:
            raise TimeoutError(room)
        for image in target.glob('*.jpg'): shutil.copy2(image, dest/image.name)
        data['videoStartEpoch'] = video_start
        data['wallSeconds'] = round(time.time()-launch_epoch, 3)
        data['device'] = args.device
        data['video'] = 'playback.mp4'
        (dest/'report.json').write_text(json.dumps(data, indent=2)+'\n')
        results.append(data)
        print('CAPTURED', room, args.quality, 'joints', data['jointCount'],
              'pause', data['pauseHeld'], 'reduced', data['reducedMotionHeld'], flush=True)
    except Exception as exc:
        results.append({'scene': room, 'quality': args.quality, 'error': str(exc)})
        print('FAILED', room, str(exc), flush=True)
    finally:
        if recording.poll() is None:
            recording.send_signal(signal.SIGINT)
            try: recording.wait(timeout=20)
            except subprocess.TimeoutExpired:
                recording.terminate(); recording.wait(timeout=5)
        log.close()
    (out/'runtime-results.json').write_text(json.dumps(results, indent=2)+'\n')
assert all(r.get('complete') for r in results), 'Some simulator captures failed'
print('COMPLETE', len(results), 'combat rooms', flush=True)
