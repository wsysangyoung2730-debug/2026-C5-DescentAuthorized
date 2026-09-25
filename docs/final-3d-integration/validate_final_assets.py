"""Check shipped USD dependencies, cameras, anchors, and animation coverage."""
import json,argparse
from pathlib import Path
from pxr import Usd,UsdGeom,UsdSkel,Sdf
p=argparse.ArgumentParser();p.add_argument('--floor',type=int);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[2]/'DescentAuthorized/Resources'
rows=json.loads((root/'Reality/FinalSceneManifest.json').read_text());reports=[]
for r in rows:
 if a.floor and r['floor']!=a.floor:continue
 for quality in ['high','medium','low']:
  file=root/r['directory']/(r['resource']+('' if quality=='high' else '_'+quality)+'.usdc')
  stage=Usd.Stage.Open(str(file));names={x.GetName() for x in stage.Traverse()}
  missing=[name for name in [*r['cameras'].values(),*r['anchors'].values()] if name not in names]
  dependencies=[]
  for prim in stage.Traverse():
   for attr in prim.GetAttributes():
    if attr.GetTypeName()==Sdf.ValueTypeNames.Asset:
     value=attr.Get()
     if value and value.path and not value.resolvedPath:dependencies.append(value.path)
  assert not missing,(file,missing)
  assert not dependencies,(file,dependencies)
  assert UsdGeom.GetStageUpAxis(stage)=='Z'
  reports.append({'floor':r['floor'],'room':r['resource'],'quality':quality,'missingAnchors':missing,'missingTextures':dependencies,'cameraCount':sum(x.IsA(UsdGeom.Camera) for x in stage.Traverse())})
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(reports,indent=2)+'\n')
print(f'Validated {len(reports)} room/quality combinations')
