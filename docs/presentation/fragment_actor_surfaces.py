"""Partition static actor surfaces into rigid fracture pieces; preserve assembled appearance and materials."""
from pathlib import Path
import numpy as np
from pxr import Usd,UsdGeom,Sdf,Gf,Vt
root=Path(__file__).resolve().parents[2]
for file in (root/'DescentAuthorized/Resources/Reality/Actors').rglob('*.usdc'):
 if file.stem.endswith(('_low','_medium')):continue
 stage=Usd.Stage.Open(str(file));layer=stage.GetRootLayer()
 for prim in [p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh) and not p.GetName().startswith('DA_Fragment_')]:
  mesh=UsdGeom.Mesh(prim);points=np.array(mesh.GetPointsAttr().Get(),float);counts=np.array(mesh.GetFaceVertexCountsAttr().Get(),int);indices=np.array(mesh.GetFaceVertexIndicesAttr().Get(),int);offset=np.r_[0,np.cumsum(counts)]
  if len(points)==0:continue
  # Local mesh orientation is arbitrary; subdivide the longest dimension most.
  lo=points.min(0);span=np.maximum(points.max(0)-lo,1e-6);div=np.array([2,2,2]);div[np.argmax(span)]=5
  centers=np.array([points[indices[offset[f]:offset[f+1]]].mean(0) for f in range(len(counts))]);cells=np.minimum(div-1,((centers-lo)/span*div).astype(int));labels=cells[:,0]+div[0]*(cells[:,1]+div[1]*cells[:,2]);normals=np.array(mesh.GetNormalsAttr().Get() or [],float);ni=mesh.GetNormalsInterpolation();uv=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st');uvs=np.array(uv.ComputeFlattened() or [],float) if uv else np.array([]);ui=uv.GetInterpolation() if uv else ''
  for k,label in enumerate(sorted(set(labels))):
   fs=np.where(labels==label)[0];corners=np.concatenate([np.arange(offset[f],offset[f+1]) for f in fs]);verts=indices[corners];dest=prim.GetParent().GetPath().AppendChild('DA_Fragment_'+str(k));Sdf.CopySpec(layer,prim.GetPath(),layer,dest);part=UsdGeom.Mesh(stage.GetPrimAtPath(dest));data=points[verts]
   part.GetPointsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(*v) for v in data]));part.GetFaceVertexCountsAttr().Set(counts[fs].tolist());part.GetFaceVertexIndicesAttr().Set(list(range(len(data))));part.GetExtentAttr().Set([Gf.Vec3f(*data.min(0)),Gf.Vec3f(*data.max(0))])
   if len(normals):part.GetNormalsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(*v) for v in normals[corners if ni=='faceVarying' else verts]]));part.SetNormalsInterpolation('faceVarying')
   if len(uvs):pv=UsdGeom.PrimvarsAPI(part).GetPrimvar('st');pv.Set(Vt.Vec2fArray([Gf.Vec2f(*v)for v in uvs[corners if ui=='faceVarying' else verts]]));pv.SetInterpolation('faceVarying');pv.SetIndices([])
   for child in part.GetPrim().GetChildren():
    if child.IsA(UsdGeom.Subset):
     attr=UsdGeom.Subset(child).GetIndicesAttr();wanted=set(attr.Get());attr.Set([i for i,f in enumerate(fs)if f in wanted])
   # Runtime models are static; discard stale per-vertex skin attributes if present.
   for prop in list(part.GetPrim().GetProperties()):
    if prop.GetName().startswith('primvars:skel:'):part.GetPrim().RemoveProperty(prop.GetName())
  stage.RemovePrim(prim.GetPath())
 layer.Save();print(file.parent.name)
# Center each piece's local pivot so fracture rotation is around the piece itself.
for file in (root/'DescentAuthorized/Resources/Reality/Actors').rglob('*.usdc'):
 if file.stem.endswith(('_low','_medium')):continue
 stage=Usd.Stage.Open(str(file))
 for prim in stage.Traverse():
  if not prim.IsA(UsdGeom.Mesh) or not prim.GetName().startswith('DA_Fragment_'):continue
  mesh=UsdGeom.Mesh(prim);points=np.array(mesh.GetPointsAttr().Get(),float);pivot=points.mean(0);points-=pivot
  transform=UsdGeom.Xformable(prim);original=transform.GetLocalTransformation();translation=Gf.Matrix4d(1);translation.SetTranslate(Gf.Vec3d(*pivot));transform.ClearXformOpOrder();transform.AddTransformOp(opSuffix='fracturePivot').Set(translation*original)
  mesh.GetPointsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(*v)for v in points]));mesh.GetExtentAttr().Set([Gf.Vec3f(*points.min(0)),Gf.Vec3f(*points.max(0))])
 stage.GetRootLayer().Save()
