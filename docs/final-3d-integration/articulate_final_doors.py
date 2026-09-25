"""Partition the visible gate mesh into stationary frame and two sliding leaves.

The closed state preserves the original surface; boundary cuts interpolate UVs. Source Blender is untouched.
"""
import json,math,argparse
from pathlib import Path
import numpy as np
from pxr import Usd,UsdGeom,UsdShade,Sdf,Gf,Vt
p=argparse.ArgumentParser();p.add_argument('--floor',type=int);a=p.parse_args()
root=Path(__file__).resolve().parents[2];resources=root/'DescentAuthorized/Resources'
manifest=resources/'Reality/FinalSceneManifest.json';rows=json.loads(manifest.read_text())
configs={7:('F07B_DescentDoor',.215,.075,.68),6:('F06B_DescentDoor',.225,.08,.70),
 5:('F05B_DecorativeClosedDoor',.225,.08,.70),4:('F04C_P16_01',.25,.10,.74),
 3:('F03C_DescentGate_To_F02',.26,.105,.755),2:('F02C_DescentGate_To_F01',.335,.16,.83),
 1:('F01C_FinalDescentGate',.258,.10,.73)}
report=[]
def split_polygon(poly, axis, limit):
 inside=[];outside=[]
 for i,b in enumerate(poly):
  a=poly[i-1];da=float(np.dot(a[:3],axis)-limit);db=float(np.dot(b[:3],axis)-limit)
  if (da<=0)!=(db<=0):
   t=da/(da-db);q=a+(b-a)*t;inside.append(q);outside.append(q)
  (inside if db<=0 else outside).append(b)
 return inside,outside

def write_mesh(mesh, polygons):
 oldface=[f for f,poly in polygons];data=np.array([v for _,poly in polygons for v in poly])
 mesh.GetPointsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(*v) for v in data[:,:3]]))
 mesh.GetFaceVertexCountsAttr().Set([len(poly) for _,poly in polygons])
 mesh.GetFaceVertexIndicesAttr().Set(list(range(len(data))))
 mesh.GetExtentAttr().Set([Gf.Vec3f(*data[:,:3].min(0)),Gf.Vec3f(*data[:,:3].max(0))])
 normal=data[:,3:6];normal/=np.maximum(np.linalg.norm(normal,axis=1,keepdims=True),1e-9)
 mesh.GetNormalsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(*v)for v in normal]));mesh.SetNormalsInterpolation('faceVarying')
 uv=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st');uv.Set(Vt.Vec2fArray([Gf.Vec2f(*v)for v in data[:,6:8]]));uv.SetInterpolation('faceVarying')
 UsdGeom.Xformable(mesh).ClearXformOpOrder()
 for child in mesh.GetPrim().GetChildren():
  if child.IsA(UsdGeom.Subset):
   attr=UsdGeom.Subset(child).GetIndicesAttr();wanted=set(attr.Get());attr.Set([i for i,f in enumerate(oldface)if f in wanted])

for r in rows:
 if r['role']!='administrator' or (a.floor and r['floor']!=a.floor):continue
 file=resources/r['directory']/(r['resource']+'.usdc');stage=Usd.Stage.Open(str(file));layer=stage.GetRootLayer()
 gateName,half,bottom,top=configs[r['floor']]
 gate=next(p for p in stage.Traverse() if p.GetName()==gateName);prefix='FINAL_F0'+str(r['floor'])+'C'
 if stage.GetPrimAtPath(gate.GetPath().AppendChild(prefix+'_Door_LeftPanel')):raise RuntimeError('Gate already articulated: '+gateName)
 cache=UsdGeom.XformCache();inverse=cache.GetLocalToWorldTransform(gate).GetInverse()
 meshes=[p for p in Usd.PrimRange(gate) if p.IsA(UsdGeom.Mesh)]
 helpers=[UsdGeom.Xform.Define(stage,gate.GetPath().AppendChild(prefix+'_Door_'+side+'Panel')) for side in ['Left','Right']]
 before=0;moved=[0,0]
 planes=[(np.array([1,0,0]),half),(np.array([-1,0,0]),half),(np.array([0,0,1]),top),(np.array([0,0,-1]),-bottom)]
 if r['floor']==2:
  planes=[(np.array([math.cos(t),0,math.sin(t)]),half+math.sin(t)*.51)for t in np.linspace(0,2*math.pi,48,endpoint=False)]
 for mi,prim in enumerate(meshes):
  mesh=UsdGeom.Mesh(prim);points=np.array(mesh.GetPointsAttr().Get(),dtype=float)
  matrix=np.array(cache.GetLocalToWorldTransform(prim)*inverse);local=points@matrix[:3,:3]+matrix[3,:3]
  counts=np.array(mesh.GetFaceVertexCountsAttr().Get(),int);indices=np.array(mesh.GetFaceVertexIndicesAttr().Get(),int);offset=np.r_[0,np.cumsum(counts)]
  normals=np.array(mesh.GetNormalsAttr().Get(),float);ni=mesh.GetNormalsInterpolation()
  uv=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st');uvs=np.array(uv.ComputeFlattened(),float);ui=uv.GetInterpolation()
  output=[[],[],[]];before+=len(counts)
  for face in range(len(counts)):
   corners=np.arange(offset[face],offset[face+1]);verts=indices[corners]
   n=normals[corners if ni=='faceVarying' else verts]@np.linalg.inv(matrix[:3,:3]).T
   tex=uvs[corners if ui=='faceVarying' else verts]
   poly=list(np.concatenate([local[verts],n,tex],axis=1))
   # Exact clipping preserves UVs at new edges; centroid partition tears large triangles.
   for axis,limit in planes:
    poly,outside=split_polygon(poly,axis,limit)
    if len(outside)>=3:output[2].append((face,outside))
    if len(poly)<3:break
   if len(poly)>=3:
    left,right=split_polygon(poly,np.array([1,0,0]),0)
    for side,part in enumerate([left,right]):
     if len(part)>=3:output[side].append((face,part))
  for side,polygons in enumerate(output):
   if not polygons:continue
   parent=helpers[side].GetPath() if side<2 else gate.GetPath()
   target=parent.AppendChild(('LeafMesh_' if side<2 else 'StaticFrame_')+str(mi))
   Sdf.CopySpec(layer,prim.GetPath(),layer,target)
   write_mesh(UsdGeom.Mesh(stage.GetPrimAtPath(target)),polygons)
   if side<2:moved[side]+=len(polygons)
  stage.RemovePrim(prim.GetPath())
 assert min(moved)>0,(r['floor'],moved)
 # Dark portal inside the opening masks the closed architectural back-wall.
 portal=UsdGeom.Mesh.Define(stage,gate.GetPath().AppendChild(prefix+'_Door_PortalSurface'))
 camera=next(p for p in stage.Traverse() if p.GetName()==r['cameras']['descentInput'])
 cam=(cache.GetLocalToWorldTransform(camera)*inverse).ExtractTranslation();sign=1 if cam[1]>0 else -1
 depth=-sign*.10
 if r['floor']==2:
  vertices=[Gf.Vec3f(math.cos(t)*half,depth,.51+math.sin(t)*half) for t in np.linspace(0,2*math.pi,65)[:-1]]
 else:vertices=[Gf.Vec3f(-half,depth,bottom),Gf.Vec3f(half,depth,bottom),Gf.Vec3f(half,depth,top),Gf.Vec3f(-half,depth,top)]
 portal.GetPointsAttr().Set(vertices);portal.GetFaceVertexCountsAttr().Set([len(vertices)]);portal.GetFaceVertexIndicesAttr().Set(list(range(len(vertices))));portal.GetDoubleSidedAttr().Set(True)
 material=UsdShade.Material.Define(stage,gate.GetPath().AppendChild('FinalPortalMaterial'));shader=UsdShade.Shader.Define(stage,material.GetPath().AppendChild('Surface'));shader.CreateIdAttr('UsdPreviewSurface')
 shader.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set((.003,.005,.008));shader.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(1);shader.CreateInput('metallic',Sdf.ValueTypeNames.Float).Set(0)
 material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(),'surface');UsdShade.MaterialBindingAPI.Apply(portal.GetPrim()).Bind(material)
 for name in ['LockCore','LogoLight']:UsdGeom.Xform.Define(stage,gate.GetPath().AppendChild(prefix+'_Door_'+name))
 r['anchors']['descentDoor']=gateName;r['doorAnimationPrefix']=prefix;r['doorTravel']=half*1.1
 layer.Save();report.append({'floor':r['floor'],'gate':gateName,'facesBefore':before,'movingFaces':moved,'opening':'circular split slide' if r['floor']==2 else 'rectangular split slide','closedSurfacePreserved':True,'boundaryMethod':'exact polygon clipping with interpolated UVs'})
manifest.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
(root/'docs/final-3d-integration/validation/door-partition.json').write_text(json.dumps(report,indent=2)+'\n')
print('Articulated',len(report),'gates')
