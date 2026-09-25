"""Run isolated debug room previews, checking cameras, bindings and skeletal movement."""
import argparse, json, os, subprocess, time, shutil
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument('--device', required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--rewards-only', action='store_true')
a = p.parse_args()
os.environ['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
bundle = 'com.wsysangyoung.DescentAuthorized'
def sim(*args, **kwargs):
    return subprocess.run(['xcrun', 'simctl', *args], check=True, **kwargs)
container = Path(sim('get_app_container', a.device, bundle, 'data', capture_output=True, text=True).stdout.strip())
configs = [(7, 'residue', 'coordinate_residue'), (7, 'boss', 'coordinate_administrator'),
           (6, 'residue', 'causality_residue'), (6, 'boss', 'causality_administrator'),
           (5, 'residue', 'memory_omission_residue'), (5, 'boss', 'original_memory_administrator')]
a.output.mkdir(parents=True, exist_ok=True)
reports = []
for floor, role, stem in configs:
    if a.rewards_only and role != 'boss': continue
    cases = [('medium', 'battle', '--boss'), ('medium', 'descentInput', '--descent')]
    if role == 'boss': cases.append(('medium', 'rewardSelection', None))
    cases += [('low', 'battle', '--boss'), ('high', 'battle', '--boss')]
    if a.rewards_only: cases = [(q, 'rewardSelection', None) for q in ('low', 'medium', 'high')]
    for quality, preset, flag in cases:
        scene = f'floor0{floor}_{stem}'
        source = container / 'Documents' / 'ExpansionDiagnostics' / scene / f'{quality}-{preset}'
        report = source / 'report.json'
        if report.exists(): report.unlink()
        log_path = a.output / f'{scene}-{quality}-{preset}.log'
        args = ['xcrun', 'simctl', 'launch', '--terminate-running-process', '--console-pty',
                a.device, bundle, '--floor9-preview', f'--floor{floor}-{role}',
                f'--graphics-{quality}', '--expansion-diagnostics']
        if flag: args.append(flag)
        started = time.monotonic()
        with log_path.open('w') as log:
            process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
            while not report.exists() and time.monotonic() - started < 90:
                if process.poll() is not None: break
                time.sleep(1)
            if not report.exists():
                process.terminate()
                raise RuntimeError(f'Preview did not complete: {scene} {quality} {preset}; see {log_path}')
            result = json.loads(report.read_text())
            assert result['actorPresent'] and result['environmentReady'] and not result['missingRoles'], result
            assert result['jointCount'] == 5, result
            if preset == 'battle': assert result['jointMotionObserved'], result
            if preset == 'rewardSelection': assert result['rewardReady'], result
            result['elapsedSeconds'] = round(time.monotonic() - started, 2)
            reports.append(result)
            shutil.copytree(source, a.output / scene / f'{quality}-{preset}', dirs_exist_ok=True)
            (a.output / 'runtime-validation.json').write_text(json.dumps(reports, indent=2))
            sim('terminate', a.device, bundle, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            process.wait(timeout=10)
        print('PASS', scene, quality, preset, flush=True)
print('PASS all', len(reports), 'runtime room/camera/quality cases', flush=True)
