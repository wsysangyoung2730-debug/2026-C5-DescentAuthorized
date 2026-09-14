"""Run with Blender's bundled Python (pxr/numpy) against the repository root."""
import json,math,sys
from pathlib import Path
from pxr import Usd,UsdGeom,UsdShade,Sdf
import numpy as np
r=Path(sys.argv[1]);d=r/'DescentAuthorized/Resources/Reality/Scenes/Floor09/ArchiveRedesign'
s=Usd.Stage.Open(str(d/'floor09_archive_redesign.usdc'));motion=json.loads((d/'floor09_reward_motion.json').read_text())
prims={str(p.GetName()):p for p in s.Traverse()}
assert UsdGeom.GetStageUpAxis(s)=='Z'
assert motion['frames']==66 and motion['fps']==30 and len(motion['tracks'])==13
for t in motion['tracks']:
 assert t['entity'] in prims,t['entity']
 assert len(t['matrices'])==66
 for a in t['matrices']:
  assert len(a)==16 and all(math.isfinite(x) for x in a)
  assert abs(a[15]-1)<1e-5
  m=np.array(a).reshape(4,4).T
  scale=np.linalg.norm(m[:3,:3],axis=0)
  assert np.all(scale>0),t['entity']
  rotation=m[:3,:3]/scale
  assert np.max(abs(rotation.T@rotation-np.eye(3)))<1e-4,('shear',t['entity'])
 # Exported frame-66 transforms and sidecar must refer to the same local space.
 usd=np.array(UsdGeom.Xformable(prims[t['entity']]).GetLocalTransformation()).flatten()
 assert np.max(abs(usd-np.array(t['matrices'][-1])))<1e-4,('space mismatch',t['entity'])
for n in ['CAM_F09_RewardSelection','F09_iPad_MainCamera','CAM_F09_DescentDoor','DA_STATE_OpenDoor_F09','F09_DescentDoor']:
 assert n in prims,n
cameras=[p for p in s.Traverse() if p.IsA(UsdGeom.Camera)]
assert len(cameras)==3
assert not any(p.GetName()=='F09_Concept_Preview' for p in s.Traverse())
assert not any(a.GetNumTimeSamples() for p in s.Traverse() for a in p.GetAttributes()),'Unexpected second animation owner'
missing=[]
for p in s.Traverse():
 for a in p.GetAttributes():
  if a.GetTypeName()==Sdf.ValueTypeNames.Asset:
   path=a.Get()
   if path and path.path and not (d/path.path).is_file():missing.append(path.path)
assert not missing,missing
track=next(t for t in motion['tracks'] if t['entity']=='F09_RewardSlot_RightLid')
def rotation(a):
 m=np.array(a).reshape(4,4).T[:3,:3];return m/np.linalg.norm(m,axis=0)
r0=rotation(track['matrices'][0]);r1=rotation(track['matrices'][-1]);angle=math.degrees(math.acos(np.clip((np.trace(r0.T@r1)-1)/2,-1,1)))
assert abs(angle-35)<.05,angle
print(f'PASS: 3 cameras, 13 x 66 valid local transforms, no USD autoplay tracks, resolved textures; right lid settles at {angle:.2f} degrees.')
