"""Retarget the verified 9F rise timing to the 8F device's own local pivots."""
import argparse,json
from pathlib import Path
from pxr import Usd,UsdGeom,Gf
parser=argparse.ArgumentParser()
parser.add_argument('stage',type=Path);parser.add_argument('reference_motion',type=Path)
args=parser.parse_args()
s=Usd.Stage.Open(str(args.stage));prims={p.GetName():p for p in s.Traverse() if p.GetTypeName()=='Xform'}
reference=json.loads(args.reference_motion.read_text());tracks=[]
for track in reference['tracks']:
 name=track['entity'].replace('F09_','F08B_')
 p=prims[name];base=UsdGeom.Xformable(p).GetLocalTransformation()
 samples=[]
 for values in track['matrices']:
  matrix=Gf.Matrix4d(*values)
  # Sample arrays are column-major simd / row-major Gf, as exported by Blender.
  first=track['matrices'][0]
  offset=Gf.Vec3d(*values[12:15])-Gf.Vec3d(*first[12:15])
  position=base.ExtractTranslation()+offset
  if name.endswith('HoleAnchor'):
   position=Gf.Vec3d(base[3][0],base[3][1],values[14])
   matrix=Gf.Matrix4d(1)
  elif name.endswith('_Idle'):
   position=Gf.Vec3d(*values[12:15])
  elif name.endswith('CentralLift'):
   position=Gf.Vec3d(base[3][0],base[3][1],values[14])
  matrix.SetTranslateOnly(position)
  samples.append([float(matrix[i][j]) for i in range(4) for j in range(4)])
 tracks.append({'entity':name,'matrices':samples})
 # Static stage starts closed. Runtime owns all animation after loading.
 UsdGeom.Xformable(p).MakeMatrixXform().Set(Gf.Matrix4d(*samples[0]))
motion={'fps':reference['fps'],'frames':reference['frames'],'tracks':tracks}
args.stage.with_name('floor08_reward_motion.json').write_text(json.dumps(motion,separators=(',',':')))
# Keep the tripod in the room but outside the reward sightline.
tripod=UsdGeom.Xformable(prims['TripodLens_R']);matrix=tripod.GetLocalTransformation()
matrix.SetTranslateOnly(Gf.Vec3d(-4.7,10.5,0));tripod.MakeMatrixXform().Set(matrix)
for name,position in [('DataPillar_0',(-10.5,11,0)),('PrismRack_R',(-10.5,7,0))]:
 obj=UsdGeom.Xformable(prims[name]);matrix=obj.GetLocalTransformation()
 matrix.SetTranslateOnly(Gf.Vec3d(*position));obj.MakeMatrixXform().Set(matrix)
camera=UsdGeom.Xformable(prims['CAM_F08_RewardSelection'])
camera.MakeMatrixXform().Set(Gf.Matrix4d().SetLookAt(Gf.Vec3d(-8.1,7.3,2.8),Gf.Vec3d(-8.1,12,2),Gf.Vec3d(0,0,1)).GetInverse())
for child in Usd.PrimRange(prims['CAM_F08_RewardSelection']):
 if child.IsA(UsdGeom.Camera):
  camera_data=UsdGeom.Camera(child)
  # Blender exports optical lengths in scene-scaled USD units. Preserve the
  # aperture/focal ratio (36 mm sensor / 25 mm lens), not a raw millimeter value.
  camera_data.GetFocalLengthAttr().Set(camera_data.GetHorizontalApertureAttr().Get()*25/36)
s.GetRootLayer().Save()
print('8F reward camera, tripod clearance and 13 motion tracks updated')
