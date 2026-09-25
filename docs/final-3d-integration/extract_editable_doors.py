"""Copy only the articulated gate and its materials for the Blender delivery package."""
import json,argparse
from pathlib import Path
from pxr import Usd,UsdGeom,UsdShade,Sdf
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[2];out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
for r in json.loads((root/'DescentAuthorized/Resources/Reality/FinalSceneManifest.json').read_text()):
 if r['role']!='administrator':continue
 source=root/'DescentAuthorized/Resources'/r['directory']/(r['resource']+'.usdc');src=Usd.Stage.Open(str(source));flat=src.Flatten()
 dest=out/f"Floor{r['floor']:02d}_Door.usdc";stage=Usd.Stage.CreateNew(str(dest));UsdGeom.SetStageUpAxis(stage,'Z');UsdGeom.SetStageMetersPerUnit(stage,1)
 gate=next(p for p in src.Traverse() if p.GetName()==r['anchors']['descentDoor'])
 for prim in [gate]+[p for p in src.Traverse() if p.IsA(UsdShade.Material)]:
  parent=prim.GetPath().GetParentPath()
  if parent!=Sdf.Path.absoluteRootPath:stage.DefinePrim(parent,'Xform')
  Sdf.CopySpec(flat,prim.GetPath(),stage.GetRootLayer(),prim.GetPath())
 for p in stage.Traverse():
  for attr in p.GetAttributes():
   value=attr.Get()
   if isinstance(value,Sdf.AssetPath) and value.path:
    attr.Set(Sdf.AssetPath(value.resolvedPath or str((source.parent/value.path).resolve())))
 stage.GetRootLayer().Save()
 print(dest)
