import argparse,json,math
from pathlib import Path
from pxr import Usd,UsdGeom,Sdf
p=argparse.ArgumentParser();p.add_argument('resource_root',type=Path);args=p.parse_args()
reports=[]
for directory,name in [('Floor10/ClosedOffice','floor10_closed_office'),('Floor08/ResidueIsolation','floor08_residue_isolation'),('Floor08/AdministratorObservatory','floor08_administrator_observatory')]:
 for suffix in ['', '_medium','_low']:
  file=args.resource_root/directory/(name+suffix+'.usdc');stage=Usd.Stage.Open(str(file))
  assert stage and stage.GetDefaultPrim(),file
  mesh_count=triangles=maps=0
  for prim in stage.Traverse():
   for attr in prim.GetAttributes():
    if attr.GetTypeName()==Sdf.ValueTypeNames.Asset:
     value=attr.Get()
     if value and value.path:assert value.resolvedPath and Path(value.resolvedPath).is_file(),(file,prim.GetPath(),value)
   if prim.IsA(UsdGeom.Mesh):
    mesh=UsdGeom.Mesh(prim);mesh_count+=1
    corners=len(mesh.GetFaceVertexIndicesAttr().Get());triangles+=sum(n-2 for n in mesh.GetFaceVertexCountsAttr().Get())
    for uv in UsdGeom.PrimvarsAPI(prim).GetPrimvars():
     if uv.GetTypeName() not in (Sdf.ValueTypeNames.TexCoord2fArray,Sdf.ValueTypeNames.Float2Array):continue
     assert not uv.IsIndexed(),(file,prim.GetPath(),'indexed UV')
     if uv.GetInterpolation()=='faceVarying':assert len(uv.Get())==corners,(file,prim.GetPath(),'UV count')
     maps+=1
   if prim.IsA(UsdGeom.Camera):
    camera=UsdGeom.Camera(prim);ratio=camera.GetHorizontalApertureAttr().Get()/camera.GetFocalLengthAttr().Get()
    assert .3<ratio<3,(file,prim.GetPath(),'camera optical units',ratio)
  reports.append({'asset':file.name,'meshes':mesh_count,'triangles':triangles,'uvSets':maps})
stage=Usd.Stage.Open(str(args.resource_root/'Floor08/AdministratorObservatory/floor08_administrator_observatory.usdc'))
prims={prim.GetName():prim for prim in stage.Traverse() if prim.GetTypeName()=='Xform'}
motion=json.loads((args.resource_root/'Floor08/AdministratorObservatory/floor08_reward_motion.json').read_text())
assert motion['fps']==30 and motion['frames']==66 and len(motion['tracks'])==13
for track in motion['tracks']:
 assert track['entity'] in prims and len(track['matrices'])==66
 for matrix in track['matrices']:assert len(matrix)==16 and all(math.isfinite(v) for v in matrix)
 matrix=UsdGeom.Xformable(prims[track['entity']]).GetLocalTransformation()
 assert max(abs(float(matrix[i][j])-track['matrices'][0][i*4+j]) for i in range(4) for j in range(4))<1e-5
 if track['entity'].endswith('_Appear'):assert track['matrices'][-1][14]-track['matrices'][0][14]>.6
print(json.dumps(reports,indent=2))
print('PASS: texture resolution, UV corner mapping, camera optical units, 13 closed/rise tracks')
