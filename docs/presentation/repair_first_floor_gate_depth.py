"""Place floor 1 room previews in front of the opaque recess; carry seals with leaves."""
from pathlib import Path
from pxr import Usd,UsdGeom,Sdf,Gf
root=Path(__file__).resolve().parents[2]
for resource in ['floor01_identity_comparison_residual','floor01_exit_review_residual']:
 file=next((root/'DescentAuthorized/Resources/Reality/Scenes/Floor01').rglob(resource+'.usdc'))
 stage=Usd.Stage.Open(str(file));prefix='MID_'+resource
 portal=next(UsdGeom.Mesh(p) for p in stage.Traverse() if p.GetName()==prefix+'_Door_PortalSurface')
 left=next(p for p in stage.Traverse() if p.GetName()==prefix+'_Door_LeftPanel')
 bc=UsdGeom.BBoxCache(0,['default','render']);bounds=bc.ComputeWorldBound(left).ComputeAlignedRange()
 depth=bounds.GetMin()[1]-.01
 points=portal.GetPointsAttr().Get();portal.GetPointsAttr().Set([Gf.Vec3f(p[0],depth,p[2]) for p in points])
 cache=UsdGeom.XformCache();inverse=cache.GetLocalToWorldTransform(left).GetInverse()
 seals=[p for p in stage.GetDefaultPrim().GetChildren() if 'DoorSeal' in p.GetName()]
 for p in seals:
  dest=left.GetPath().AppendChild(p.GetName());matrix=cache.GetLocalToWorldTransform(p)*inverse
  Sdf.CopySpec(stage.GetRootLayer(),p.GetPath(),stage.GetRootLayer(),dest)
  x=UsdGeom.Xformable(stage.GetPrimAtPath(dest));x.ClearXformOpOrder();x.AddTransformOp().Set(matrix)
  stage.RemovePrim(p.GetPath())
 stage.GetRootLayer().Save()
 print(resource,'previewDepth',depth,'movingSeals',len(seals))
