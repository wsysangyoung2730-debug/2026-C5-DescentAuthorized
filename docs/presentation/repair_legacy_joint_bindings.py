"""Replace stale source skin indices (up to 40) on the exported five-joint rigs."""
from pathlib import Path
from pxr import Usd,UsdGeom,UsdSkel,Vt
import numpy as np
root=Path(__file__).resolve().parents[2]
def smooth(x):
 t=np.clip(x,0,1);return t*t*(3-2*t)
for name in ['RecordAdministrator','ObservationAdministrator']:
 path=root/'DescentAuthorized/Resources/Reality/Actors'/name/'articulated.usdc';s=Usd.Stage.Open(str(path))
 for p in s.Traverse():
  if not p.IsA(UsdGeom.Mesh):continue
  points=np.array(UsdGeom.Mesh(p).GetPointsAttr().Get());x,y,z=points.T
  arm=smooth((np.abs(x)-.27)/.26)*smooth((z-.55)/.4)*(1-smooth((z-2.15)/.3))
  arm*=1-smooth((y-.25)/.35)
  # Low blade/shield/cannon surfaces travel rigidly with their holding arm.
  equipment=(np.abs(x)>.50)&(y<.1)&(z<2.05)
  arm[equipment]=1
  head=smooth((z-2.08)/.35)*(1-arm)
  spine=smooth((z-.55)/.65)*(1-arm-head)
  weights=np.stack([1-arm-head-spine,spine,head,np.where(x>0,arm,0),np.where(x<=0,arm,0)],axis=1)
  ids=np.tile(np.arange(5),(len(points),1))
  bind=UsdSkel.BindingAPI(p)
  for pv,data in [(bind.CreateJointIndicesPrimvar(False,5),Vt.IntArray(ids.reshape(-1).tolist())),(bind.CreateJointWeightsPrimvar(False,5),Vt.FloatArray(weights.reshape(-1).tolist()))]:
   pv.Set(data);pv.SetElementSize(5);pv.SetInterpolation('vertex');pv.BlockIndices()
 s.GetRootLayer().Save();print(name)
