"""Restore bindings dropped by older 9F/8F administrator exports. Keep existing motions."""
from pathlib import Path
from pxr import Usd,UsdSkel,UsdGeom,Gf
root=Path(__file__).resolve().parents[2]/'DescentAuthorized/Resources/Reality/Actors'
for name,base in [('RecordAdministrator','record_administrator'),('ObservationAdministrator','observation_administrator')]:
 file=root/name/(base+'.usdc');stage=Usd.Stage.Open(str(file))
 actor=next(p for p in stage.Traverse()if p.GetName()=='ACTOR_'+name);actor.SetTypeName('SkelRoot')
 skeleton=next(p for p in stage.Traverse()if p.IsA(UsdSkel.Skeleton))
 for p in Usd.PrimRange(actor):
  if p.IsA(UsdGeom.Mesh) and p.GetAttribute('primvars:skel:jointWeights').HasValue():
   binding=UsdSkel.BindingAPI.Apply(p);binding.CreateSkeletonRel().SetTargets([skeleton.GetPath()])
   if not binding.GetGeomBindTransformAttr().HasValue():binding.CreateGeomBindTransformAttr().Set(Gf.Matrix4d(1))
 stage.GetRootLayer().Save()
 print('Restored binding',name)
