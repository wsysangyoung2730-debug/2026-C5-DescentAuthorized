import argparse,json,shutil
from pathlib import Path
from pxr import Usd,UsdSkel
p=argparse.ArgumentParser();p.add_argument('--floors',required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--raw',type=Path,required=True);p.add_argument('--label',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[2];doc=root/'docs/final-3d-integration';rows=json.loads((doc/'actor-contracts.json').read_text());report=[]
for r in rows:
 if str(r['floor']) not in a.floors.split(','):continue
 source=a.source/r['name'];dest=root/'DescentAuthorized/Resources/Reality/Actors'/r['name']
 for q in ['', '_medium','_low']:
  s=Usd.Stage.Open(str(source/(r['asset']+q+'.usdc')));rigs=[UsdSkel.Skeleton(p) for p in s.Traverse() if p.IsA(UsdSkel.Skeleton)]
  assert rigs and len(rigs[0].GetJointsAttr().Get())>=18,(r['name'],'missing joints')
  assert any(p.IsA(UsdSkel.Animation) and len(UsdSkel.Animation(p).GetRotationsAttr().GetTimeSamples())>100 for p in s.Traverse())
 if dest.exists():shutil.rmtree(dest)
 shutil.copytree(source,dest);shutil.copy2(a.raw/r['name']/'motion.json',dest/'motion.json')
 motion=json.loads((dest/'motion.json').read_text());assert len(motion['clips'])==9
 for c,impact in [('attack',.46),('heavyAttack',.62)]:assert motion['clips'][c]['impact']==impact
 report.append({'actor':r['name'],'joints':len(rigs[0].GetJointsAttr().Get()),'clips':len(motion['clips']),'profile':motion['profile']['style']})
shutil.copy2(a.raw/'FinalActors_Rigged.blend',doc/'authoring'/f'{a.label}_FinalActors.blend')
(doc/'validation'/f'{a.label}-motion.json').write_text(json.dumps(report,indent=2)+'\n')
print('Installed',len(report),'animated actors')
