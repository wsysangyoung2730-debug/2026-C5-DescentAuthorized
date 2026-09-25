import json
from pathlib import Path
from pxr import Usd,UsdSkel,UsdGeom,Sdf
root=Path('DescentAuthorized/Resources/Reality/Actors');reports=[]
for folder in root.iterdir():
 if not folder.is_dir():continue
 motion=folder/'motion.json'
 if not motion.exists():continue
 meta=json.loads(motion.read_text())
 for file in folder.glob('*.usdc'):
  s=Usd.Stage.Open(str(file));prims=list(s.Traverse());skeletons=[p for p in prims if p.IsA(UsdSkel.Skeleton)];animations=[p for p in prims if p.IsA(UsdSkel.Animation)];roots=[p for p in prims if p.IsA(UsdSkel.Root)]
  assert skeletons and roots and animations,file
  for mesh in [p for p in prims if p.IsA(UsdGeom.Mesh) and p.GetAttribute('primvars:skel:jointWeights').HasValue()]:
   binding=UsdSkel.BindingAPI(mesh)
   assert binding.GetInheritedSkeleton(),(file,mesh.GetPath(),'missing skin binding')
   assert binding.GetGeomBindTransformAttr().HasValue(),(file,'missing bind matrix')
  assert all(x in meta['clips']for x in ['idle','attack','heavyAttack','death']),file
  unresolved=[]
  for p in prims:
   for a in p.GetAttributes():
    if a.GetTypeName()==Sdf.ValueTypeNames.Asset:
     v=a.Get()
     if v and v.path and not v.resolvedPath:unresolved.append(v.path)
  assert not unresolved,(file,unresolved)
  reports.append({'actor':folder.name,'file':file.name,'skeletalRoots':len(roots),'joints':len(skeletons[0].GetAttribute('joints').Get()),'animationSamples':len(animations[0].GetAttribute('rotations').GetTimeSamples()),'clips':len(meta['clips']),'missingTextures':unresolved})
Path('docs/final-3d-integration/validation/all-actor-assets.json').write_text(json.dumps(reports,indent=2))
print('Validated',len(reports),'actor/quality combinations')
