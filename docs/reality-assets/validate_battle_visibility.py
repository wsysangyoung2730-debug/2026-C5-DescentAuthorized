"""Capture all rooms with the installed DEBUG app. Does not touch player saves.
Build/install first. Run only one capture process at a time; each route relaunches
that same simulator app. Outputs screenshots and fresh per-room JSON reports.
"""
import subprocess,os,time,json,re,shutil,fcntl
lock = open("/private/tmp/c5-battle-visibility-capture.lock", "w")
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
from pathlib import Path
repo=Path(__file__).resolve().parents[2]
out=repo.parent/'outputs/battle-visibility-validated';out.mkdir(parents=True,exist_ok=True)
os.environ['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
sim=os.environ.get('C5_SIMULATOR', 'booted'); app='com.wsysangyoung.DescentAuthorized'
def cmd(args): return subprocess.check_output(['xcrun','simctl']+args,text=True).strip()
base=Path(cmd(['get_app_container',sim,app,'data']))/'Documents/CameraResetDiagnostics'
rows=json.loads((repo/'DescentAuthorized/Resources/Reality/FinalSceneManifest.json').read_text())
routes=[('floor10_closed_office',['--floor10']),('floor09_archive_redesign',[]),('floor08_residue_isolation',['--floor8-residue']),('floor08_administrator_observatory',['--floor8-boss'])]+[(r['resource'],['--final-room',r['resource']]) for r in rows]
results=[]
for name,flags in routes:
 start=time.time();cmd(['launch','--terminate-running-process',sim,app,'--floor9-preview','--boss','--camera-reset-diagnostics','--graphics-medium']+flags)
 p=base/name/'report.json'
 while time.time()-start<65:
  if p.exists() and p.stat().st_mtime>start:break
  time.sleep(1)
 ok=p.exists() and p.stat().st_mtime>start
 if ok:shutil.copytree(base/name,out/name,dirs_exist_ok=True)
 results.append({'scene':name,'captured':ok});(out/'capture-index.json').write_text(json.dumps(results,indent=2))
 print(name,ok,round(time.time()-start,1),flush=True)
