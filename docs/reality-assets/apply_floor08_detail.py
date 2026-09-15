import sys
from pxr import Usd,UsdGeom
stage=Usd.Stage.Open(sys.argv[1]);detail=Usd.Stage.Open(sys.argv[2])
source={}
for p in detail.Traverse():
 if p.IsA(UsdGeom.Mesh): source[p.GetParent().GetName()]=p
for p in stage.Traverse():
 if not p.IsA(UsdGeom.Mesh):continue
 parent=p.GetParent().GetName()
 key='RestoredPartition' if '935ff78e' in parent else 'RestoredCrate' if '9771cc26' in parent else None
 if not key:continue
 src=source[key]
 for attr in src.GetAttributes():
  if attr.GetName().startswith(('xformOp','material:')) or not attr.HasAuthoredValueOpinion():continue
  p.CreateAttribute(attr.GetName(),attr.GetTypeName(),custom=attr.IsCustom()).Set(attr.Get())
  for name,value in attr.GetAllAuthoredMetadata().items():
   if name not in ['typeName','custom','variability']:p.GetAttribute(attr.GetName()).SetMetadata(name,value)
 for uv in UsdGeom.PrimvarsAPI(p).GetPrimvars():
  if uv.IsIndexed():values=uv.ComputeFlattened();uv.Set(values);uv.BlockIndices()
 print('RESTORED',p.GetPath(),len(UsdGeom.Mesh(p).GetFaceVertexCountsAttr().Get()))
stage.GetRootLayer().Save()
