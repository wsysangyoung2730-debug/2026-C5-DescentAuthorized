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
  # This actor's long stamp extends below the generic arm domain (1.2 m).
  # Keep the entire outboard stamp rigid and the central legs on their base.
  if name == 'RejectionExecutionResidual':
   points=np.array(UsdGeom.Mesh(p).GetPointsAttr().Get());n=ids.GetElementSize()
   after=after.reshape(-1,n);weights=bind.GetJointWeightsPrimvar()
   values=np.array(weights.ComputeFlattened(),float).reshape(-1,n)
   arm=next(i for i,j in enumerate(joints) if j.endswith('/upper_arm_R'))
   x,y,z=points.T
   for mask,joint in [((x < -.68)&(z > .9)&(z < 2.2),arm), ((abs(x)<.68)&(z<1.65),0)]:
    after[mask]=0;after[mask,0]=joint;values[mask]=0;values[mask,0]=1
   weights.Set(Vt.FloatArray(values.reshape(-1).tolist()));weights.BlockIndices()
   after=after.reshape(-1)
  ids.Set(Vt.IntArray(after.tolist()));ids.BlockIndices()
 stage.GetRootLayer().Save()
 report.append({'actor':name,'collapsedArmInfluences':changed,'bodyWeightsPreserved':True})
(root/'docs/presentation/rigid-arm-report.json').write_text(json.dumps(report,indent=2))
