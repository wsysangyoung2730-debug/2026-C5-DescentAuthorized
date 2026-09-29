"""Collapse mechanical arm influence chains to rigid shoulders, preserving body weights.
Run after install_articulated_surfaces.py. Equipment follows its owning arm.
"""
from pathlib import Path
from pxr import Usd, UsdSkel, UsdGeom, Vt
import numpy as np, json
root=Path(__file__).resolve().parents[2]
names=['RejectionExecutionResidual','QuarantineEnforcerResidual','OverloadResidual','BackflowBlockerResidual','ExitReviewResidual']
report=[]
for name in names:
 path=root/'DescentAuthorized/Resources/Reality/Actors'/name/'articulated.usdc'
 stage=Usd.Stage.Open(str(path))
 sk=next(UsdSkel.Skeleton(p) for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton))
 joints=list(sk.GetJointsAttr().Get())
 mapping=np.arange(len(joints))
 for side in ['L','R']:
  arm=next(i for i,j in enumerate(joints) if j.endswith('/upper_arm_'+side))
  for i,j in enumerate(joints):
   if j==joints[arm] or j.startswith(joints[arm]+'/'):mapping[i]=arm
 changed=0
 for p in stage.Traverse():
  if not p.IsA(UsdGeom.Mesh):continue
  bind=UsdSkel.BindingAPI(p);ids=bind.GetJointIndicesPrimvar()
  before=np.array(ids.ComputeFlattened(),int);after=mapping[before]
  changed+=int(np.count_nonzero(before!=after))
  # The generated stamp shares stretched triangles with the body. Give each
  # armour face one rigid owner, so metal separates at joints instead of melting.
  if name == 'RejectionExecutionResidual':
   mesh=UsdGeom.Mesh(p);points=np.array(mesh.GetPointsAttr().Get());n=ids.GetElementSize()
   old_indices=np.array(mesh.GetFaceVertexIndicesAttr().Get(),int)
   counts=np.array(mesh.GetFaceVertexCountsAttr().Get(),int)
   after=after.reshape(-1,n);weights=bind.GetJointWeightsPrimvar()
   values=np.array(weights.ComputeFlattened(),float).reshape(-1,n)
   right=next(i for i,j in enumerate(joints) if j.endswith('/upper_arm_R'))
   face_joints=[];offset=0
   for count in counts:
    vertices=old_indices[offset:offset+count];x,y,z=points[vertices].mean(0)
    totals=np.bincount(after[vertices].reshape(-1),weights=values[vertices].reshape(-1),minlength=len(joints))
    joint=int(np.argmax(totals))
    if x < -.68 and .9 < z < 2.2:joint=right
    elif abs(x)<.68 and z<1.65:joint=0
    face_joints.extend([joint]*count);offset+=count
   mesh.GetPointsAttr().Set(Vt.Vec3fArray(points[old_indices].tolist()))
   mesh.GetFaceVertexIndicesAttr().Set(Vt.IntArray(list(range(len(old_indices)))))
   if mesh.GetNormalsInterpolation()=='vertex':
    normals=np.array(mesh.GetNormalsAttr().Get());mesh.GetNormalsAttr().Set(Vt.Vec3fArray(normals[old_indices].tolist()))
   for pv in UsdGeom.PrimvarsAPI(p).GetPrimvars():
    if pv.GetInterpolation()=='vertex' and pv.GetPrimvarName() not in ['skel:jointIndices','skel:jointWeights']:
     data=pv.ComputeFlattened()
     if data is not None and len(data)==len(points):
      pv.Set(type(data)([data[i] for i in old_indices]));pv.BlockIndices()
   after=np.zeros((len(old_indices),n),int);after[:,0]=face_joints
   values=np.zeros((len(old_indices),n),float);values[:,0]=1
   weights.Set(Vt.FloatArray(values.reshape(-1).tolist()));weights.BlockIndices()
   after=after.reshape(-1)
  ids.Set(Vt.IntArray(after.tolist()));ids.BlockIndices()
 stage.GetRootLayer().Save()
 report.append({'actor':name,'collapsedArmInfluences':changed,'bodyWeightsPreserved':name!='RejectionExecutionResidual'})
(root/'docs/presentation/rigid-arm-report.json').write_text(json.dumps(report,indent=2))
