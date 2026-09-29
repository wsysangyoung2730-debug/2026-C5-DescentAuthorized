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
  ids.Set(Vt.IntArray(after.tolist()));ids.BlockIndices()
 stage.GetRootLayer().Save()
 report.append({'actor':name,'collapsedArmInfluences':changed,'bodyWeightsPreserved':True})
(root/'docs/presentation/rigid-arm-report.json').write_text(json.dumps(report,indent=2))
