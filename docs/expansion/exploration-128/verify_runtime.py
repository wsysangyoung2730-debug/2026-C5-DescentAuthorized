import argparse,subprocess,os,time,json,pathlib,shutil
os.environ['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
parser=argparse.ArgumentParser()
parser.add_argument('--device',required=True)
parser.add_argument('--output',required=True)
args=parser.parse_args()
device=args.device;bundle='com.wsysangyoung.DescentAuthorized'
def sim(*args): return subprocess.check_output(['xcrun','simctl',*args],text=True).strip()
output=pathlib.Path(args.output).resolve();output.mkdir(parents=True,exist_ok=True)
reports=[]
for floor in (7,6,5):
 for mode in ('residue','boss','investigation'):
  flags=['--preview-floor',str(floor),'--expansion-exploration-diagnostics']
  if mode=='investigation': flags+=['--preview-stage','entrance']
  else: flags+=['--preview-battle']
  if mode=='boss': flags+=['--preview-boss']
  container=pathlib.Path(sim('get_app_container',device,bundle,'data'))
  start=time.time()
  sim('launch','--terminate-running-process',device,bundle,*flags)
  found=None
  while time.time()-start<150:
   for f in (container/'Documents/ExpansionExplorationDiagnostics').glob('*/*/report.json'):
    if f.stat().st_mtime>=start: found=f;break
   if found:break
   time.sleep(2)
  if not found: raise RuntimeError(f'Timeout {floor} {mode}')
  report=json.loads(found.read_text());report['floor']=floor;report['case']=mode
  shutil.copytree(found.parent,output/f'{floor}-{mode}',dirs_exist_ok=True)
  sim('io',device,'screenshot',str(output/f'{floor}-{mode}.png'))
  keys=['enabledOnEntry','lookLeftChanged','lookRightChanged','resetRestoredCamera','lockedCameraRejectsLook']
  assert all(report[k] for k in keys),report
  assert report['actorVisibleOnEntry']==(mode!='investigation'),report
  assert len(report['anchorIDs'])==(0 if mode=='boss' else 2),report
  assert not report['missingRoles'],report
  reports.append(report);print(f'PASS {floor} {mode}',flush=True)
(output/'validation.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2))
print('PASS all 9 runtime cases',flush=True)
