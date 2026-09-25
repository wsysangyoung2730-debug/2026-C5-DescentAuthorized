"""Repair 7F gallery supports, mast placement and stair landing in all quality variants.
Run with Blender's bundled Python (pxr). Re-runnable after room exports.
"""
from pathlib import Path
import json, shutil
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf
ROOT=Path(__file__).resolve().parents[2]
R=ROOT/'DescentAuthorized/Resources/Reality'

def bounds(stage,p):
 return UsdGeom.BBoxCache(Usd.TimeCode.Default(),['default','render']).ComputeWorldBound(p).ComputeAlignedRange()
def fit(stage,p,lo,hi):
 b=bounds(stage,p); old=(b.GetMin()+b.GetMax())*.5; new=(Gf.Vec3d(*lo)+Gf.Vec3d(*hi))*.5
 scale=Gf.Vec3d(*[(hi[i]-lo[i])/(b.GetMax()[i]-b.GetMin()[i]) for i in range(3)])
 xf=UsdGeom.Xformable(p);w=xf.ComputeLocalToWorldTransform(Usd.TimeCode.Default())
 parent=UsdGeom.Xformable(p.GetParent()).ComputeLocalToWorldTransform(Usd.TimeCode.Default())
 matrix=w*Gf.Matrix4d().SetTranslate(-old)*Gf.Matrix4d().SetScale(scale)*Gf.Matrix4d().SetTranslate(new)*parent.GetInverse()
 xf.MakeMatrixXform().Set(matrix)
def move_center(stage,p,xy,bottom=None):
 b=bounds(stage,p);lo=list(b.GetMin());hi=list(b.GetMax());delta=[xy[i]-(lo[i]+hi[i])/2 for i in range(2)]+[0 if bottom is None else bottom-lo[2]]
 fit(stage,p,[lo[i]+delta[i] for i in range(3)],[hi[i]+delta[i] for i in range(3)])

for path in (R/'Scenes/Floor07/CoordinateAdministrator').glob('*.usdc'):
 s=Usd.Stage.Open(str(path));objects=[p for p in s.Traverse() if p.GetTypeName()=='Xform'];count=0
 for side in [-1,1]:
  for prefix,bottom in [('F07B_MastBase',4.0),('F07B_CalibrationMast',4.3),('F07B_MastLight',5.65)]:
   group=[p for p in objects if p.GetName().startswith(prefix) and bounds(s,p).GetMidpoint()[0]*side>0]
   group.sort(key=lambda p:bounds(s,p).GetMidpoint()[1]);assert len(group)==3,(prefix,len(group))
   for p,y in zip(group,[-2,2,6]):move_center(s,p,(side*9.7,y),bottom);count+=1
  stairs=[p for p in objects if p.GetName().startswith('F07B_GalleryStair') and bounds(s,p).GetMidpoint()[0]*side>0]
  stairs.sort(key=lambda p:bounds(s,p).GetMidpoint()[1]);assert len(stairs)==16
  for i,p in enumerate(stairs):
   y=-7.15+i*.27;fit(s,p,(side*9.7-1.2,y-.14,0),(side*9.7+1.2,y+.14,4.15*(i+1)/16));count+=1
 for p in objects:
  if p.GetName().startswith('F07B_GallerySupport'):
   b=bounds(s,p);lo=list(b.GetMin());hi=list(b.GetMax());hi[2]=3.9;fit(s,p,lo,hi);count+=1
 s.GetRootLayer().Save(); print('repaired',path.name,count)

