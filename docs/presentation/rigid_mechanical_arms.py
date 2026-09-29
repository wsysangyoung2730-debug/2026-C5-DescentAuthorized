"""Rigid shoulder articulation for machinery: no elastic stamp, shield or claw deformation."""
from pathlib import Path
from pxr import Usd,UsdSkel,UsdGeom,Vt
import numpy as np,json
root=Path(__file__).resolve().parents[2]
names=['RejectionExecutionResidual','QuarantineEnforcerResidual','OverloadResidual','BackflowBlockerResidual','ExitReviewResidual']
report=[]
for name in names:
 path=root/'DescentAuthorized/Resources/Reality/Actors'/name/'articulated.usdc';stage=Usd.Stage.Open(str(path))
 sk=next(UsdSkel.Skeleton(p)for p in stage.Traverse()if p.IsA(UsdSkel.Skeleton));joints=list(sk.GetJointsAttr().Get());short=[j.split('/')[-1]for j in joints];binds=sk.GetBindTransformsAttr().Get();chest=short.index('chest')
 for p in stage.Traverse():
  if not p.IsA(UsdGeom.Mesh):continue
  mesh=UsdGeom.Mesh(p);points=np.array(mesh.GetPointsAttr().Get());bind=UsdSkel.BindingAPI(p)
  ids=bind.GetJointIndicesPrimvar();weights=bind.GetJointWeightsPrimvar();n=ids.GetElementSize()
  ji=np.array(ids.ComputeFlattened(),int).reshape(-1,n);jw=np.array(weights.ComputeFlattened(),float).reshape(-1,n);changed=0
  for sign,side in [(1,'L'),(-1,'R')]:
   arm=short.index('upper_arm_'+side);shoulder=np.array(binds[arm].ExtractTranslation());half=abs(shoulder[0])
   # Rigid arm outside the shoulder cuff. Blend only the cuff, never the weapon.
   for i,(x,y,z) in enumerate(points):
    if not (.48<z<shoulder[2]+.16 and y<.30 and sign*x>half*.60):continue
    # Keep thighs and knees on their original leg joints; low outer geometry is equipment.
    if z < 1.65 and sign*x < half*1.25:continue
    t=min(1,max(0,(sign*x-half*.60)/(half*.38)));t=t*t*(3-2*t)
    ji[i]=[arm,chest]+[0]*(n-2);jw[i]=[t,1-t]+[0]*(n-2);changed+=1
  ids.Set(Vt.IntArray(ji.reshape(-1).tolist()));weights.Set(Vt.FloatArray(jw.reshape(-1).tolist()));report.append({'actor':name,'rigidArmVertices':changed})
 stage.GetRootLayer().Save()
(root/'docs/presentation/rigid-arm-report.json').write_text(json.dumps(report,indent=2))
