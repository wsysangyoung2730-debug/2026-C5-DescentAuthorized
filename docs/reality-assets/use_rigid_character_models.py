"""Keep source mesh/UV/material data, remove runtime skin deformation for every actor.
Editable Blender rigs are untouched. Git retains the previous animated USD files.
"""
from pathlib import Path
import hashlib,json
from pxr import Usd,UsdGeom,UsdSkel
root=Path(__file__).resolve().parents[2]/'DescentAuthorized/Resources/Reality/Actors'
rows=[]
for folder in sorted(root.iterdir()):
 if not (folder/'motion.json').exists():continue
 for file in sorted(folder.glob('*.usdc')):
  if file.stem.endswith(('_low','_medium')):continue
  stage=Usd.Stage.Open(str(file))
  original={str(p.GetPath()):hashlib.sha256(bytes(UsdGeom.Mesh(p).GetPointsAttr().Get())).hexdigest() for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)}
  remove=[]
  for p in list(stage.Traverse()):
   if p.IsA(UsdSkel.Skeleton) or p.IsA(UsdSkel.Animation):remove.append(p.GetPath());continue
   if p.IsA(UsdSkel.Root):p.SetTypeName('Xform')
   if p.HasAPI(UsdSkel.BindingAPI):p.RemoveAPI(UsdSkel.BindingAPI)
   for prop in list(p.GetProperties()):
    if prop.GetName().startswith(('skel:','primvars:skel:')):p.RemoveProperty(prop.GetName())
  for path in sorted(remove,key=lambda p:len(str(p)),reverse=True):stage.RemovePrim(path)
  stage.GetRootLayer().Save()
  assert original=={str(p.GetPath()):hashlib.sha256(bytes(UsdGeom.Mesh(p).GetPointsAttr().Get())).hexdigest() for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)}
 metadata=json.loads((folder/'motion.json').read_text());metadata['runtimeMotion']='subtleRigid';(folder/'motion.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
 for file in sorted(folder.glob('*.usdc')):
  stage=Usd.Stage.Open(str(file));prims=list(stage.Traverse())
  assert not any(p.IsA(UsdSkel.Root) or p.IsA(UsdSkel.Skeleton) or p.IsA(UsdSkel.Animation) or p.HasAPI(UsdSkel.BindingAPI)for p in prims),file
  assert not any(a.GetName().startswith('primvars:skel:')for p in prims for a in p.GetAttributes()),file
  rows.append({'actor':folder.name,'file':file.name,'meshes':sum(p.IsA(UsdGeom.Mesh)for p in prims),'skinDeformation':False})
Path(__file__).with_name('rigid-character-assets-168.json').write_text(json.dumps(rows,indent=2)+'\n')
print('Validated',len(rows),'rigid actor/quality assets')
