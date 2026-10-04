"""Create independent middle-door leaves; preserve UVs, frame and source Blender files."""
import json, math
from pathlib import Path
import numpy as np
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt
root=Path(__file__).resolve().parents[2]; resources=root/'DescentAuthorized/Resources'
rows=json.loads((resources/'Reality/FinalSceneManifest.json').read_text())
rows=[r for r in rows if r['role']!='administrator']
rows.append(dict(floor=8,role='residualA',resource='floor08_residue_isolation',directory='Reality/Scenes/Floor08/ResidueIsolation',cameras={'descentInput':'CAM_F08A_BossAccessDoor'}))
names={7:['F07A_BossAccessDoor'],6:['F06A_BossAccessDoor'],5:['F05A_DecorativeMiddleDoor'],4:['F04A_MiddleDoor','F04B_MiddleDoor'],3:['F03A_CentralDoor_To_F03B','F03B_CentralDoor_To_F03C'],2:['F02A_CentralDoor_To_F02B','F02B_CentralDoor_To_Boss'],8:['F08A_BossAccessDoor']}
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


report=[]
for row in rows:
 file=resources/row['directory']/(row['resource']+'.usdc');stage=Usd.Stage.Open(str(file));layer=stage.GetRootLayer()
 prefix='MID_'+row['resource'];cache=UsdGeom.XformCache();bc=UsdGeom.BBoxCache(0,['default','render'])
 if any(p.GetName()==prefix+'_Door_LeftPanel' for p in stage.Traverse()):continue
 if row['floor']==1:
  parent=stage.GetDefaultPrim(); gate=UsdGeom.Xform.Define(stage,parent.GetPath().AppendChild(prefix+'_Gate')).GetPrim()
  inverse=cache.GetLocalToWorldTransform(parent).GetInverse()
  selected=[p for p in stage.Traverse() if any(k in p.GetName() for k in ['ConnectingDoorLeaf','DoorIvoryStripe']) and p.IsA(UsdGeom.Xform)]
  # Source meshes may have repeated names beneath Xforms; select only top-level owners.
  selected=[p for p in selected if not any(a.GetPath()!=p.GetPath() and p.GetPath().HasPrefix(a.GetPath()) for a in selected)]
  helpers=[UsdGeom.Xform.Define(stage,gate.GetPath().AppendChild(prefix+'_Door_'+side+'Panel')) for side in ['Left','Right']]
  mins=[];maxs=[]
  for i,prim in enumerate(selected):
   bound=bc.ComputeWorldBound(prim).ComputeAlignedRange();mins.append(np.array(bound.GetMin()));maxs.append(np.array(bound.GetMax()))
   side=0 if bound.GetMidpoint()[0]<0 else 1;target=helpers[side].GetPath().AppendChild('Leaf_'+str(i)); matrix=cache.GetLocalToWorldTransform(prim)*inverse
   Sdf.CopySpec(layer,prim.GetPath(),layer,target);x=UsdGeom.Xformable(stage.GetPrimAtPath(target));x.ClearXformOpOrder();x.AddTransformOp().Set(matrix);stage.RemovePrim(prim.GetPath())
  lo=np.min(mins,axis=0);hi=np.max(maxs,axis=0);cx=(lo[0]+hi[0])/2;half=(hi[0]-lo[0])/2;bottom=lo[2];top=hi[2];depth=hi[1]+.06
 else:
  gate=next(p for p in stage.Traverse() if p.GetName() in names[row['floor']]);inverse=cache.GetLocalToWorldTransform(gate).GetInverse()
  bound=bc.ComputeUntransformedBound(gate).ComputeAlignedRange();lo=np.array(bound.GetMin());hi=np.array(bound.GetMax());span=hi-lo
  cx=(lo[0]+hi[0])/2;half=span[0]*.30;bottom=lo[2]+span[2]*.055;top=lo[2]+span[2]*.73;depth=lo[1]+span[1]*.62
  helpers=[UsdGeom.Xform.Define(stage,gate.GetPath().AppendChild(prefix+'_Door_'+side+'Panel')) for side in ['Left','Right']]
  meshes=[p for p in Usd.PrimRange(gate) if p.IsA(UsdGeom.Mesh)]
  planes=[(np.array([1,0,0]),cx+half),(np.array([-1,0,0]),-cx+half),(np.array([0,0,1]),top),(np.array([0,0,-1]),-bottom)]
  for mi,prim in enumerate(meshes):
   mesh=UsdGeom.Mesh(prim);points=np.array(mesh.GetPointsAttr().Get(),float);matrix=np.array(cache.GetLocalToWorldTransform(prim)*inverse);local=points@matrix[:3,:3]+matrix[3,:3]
   counts=np.array(mesh.GetFaceVertexCountsAttr().Get(),int);indices=np.array(mesh.GetFaceVertexIndicesAttr().Get(),int);offset=np.r_[0,np.cumsum(counts)]
   normals=np.array(mesh.GetNormalsAttr().Get() or [],float);ni=mesh.GetNormalsInterpolation();uv=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st');uvs=np.array(uv.ComputeFlattened() or [],float) if uv else np.array([]);ui=uv.GetInterpolation() if uv else ''
   output=[[],[],[]]
   for face in range(len(counts)):
    corners=np.arange(offset[face],offset[face+1]);verts=indices[corners]
    n=normals[corners if ni=='faceVarying' else verts]@np.linalg.inv(matrix[:3,:3]).T if len(normals) else np.tile([0,-1,0],(len(verts),1))
    tex=uvs[corners if ui=='faceVarying' else verts] if len(uvs) else np.zeros((len(verts),2))
    poly=list(np.concatenate([local[verts],n,tex],axis=1))
    for axis,limit in planes:
     poly,outside=split_polygon(poly,axis,limit)
     if len(outside)>=3:output[2].append((face,outside))
     if len(poly)<3:break
    if len(poly)>=3:
     left,right=split_polygon(poly,np.array([1,0,0]),cx)
     for side,part in enumerate([left,right]):
      if len(part)>=3:output[side].append((face,part))
   for side,polygons in enumerate(output):
    if not polygons:continue
    target=(helpers[side].GetPath() if side<2 else gate.GetPath()).AppendChild(('LeafMesh_' if side<2 else 'StaticFrame_')+str(mi))
    Sdf.CopySpec(layer,prim.GetPath(),layer,target);newmesh=UsdGeom.Mesh(stage.GetPrimAtPath(target))
    if not UsdGeom.PrimvarsAPI(newmesh).GetPrimvar('st'):UsdGeom.PrimvarsAPI(newmesh).CreatePrimvar('st',Sdf.ValueTypeNames.TexCoord2fArray,'faceVarying')
    write_mesh(newmesh,polygons)
   stage.RemovePrim(prim.GetPath())
 portal=UsdGeom.Mesh.Define(stage,gate.GetPath().AppendChild(prefix+'_Door_PortalSurface'))
 portal.GetPointsAttr().Set([Gf.Vec3f(cx-half,depth,bottom),Gf.Vec3f(cx+half,depth,bottom),Gf.Vec3f(cx+half,depth,top),Gf.Vec3f(cx-half,depth,top)])
 portal.GetFaceVertexCountsAttr().Set([4]);portal.GetFaceVertexIndicesAttr().Set([0,1,2,3]);portal.GetDoubleSidedAttr().Set(True)
 UsdGeom.PrimvarsAPI(portal).CreatePrimvar('st',Sdf.ValueTypeNames.TexCoord2fArray,'vertex').Set([(0,0),(1,0),(1,1),(0,1)])
 for name in ['LockCore','LogoLight']:UsdGeom.Xform.Define(stage,gate.GetPath().AppendChild(prefix+'_Door_'+name))
 layer.Save();report.append(dict(resource=row['resource'],gate=gate.GetName(),prefix=prefix,travel=half*1.08))
(root/'docs/presentation/middle-door-controllers.json').write_text(json.dumps(report,indent=2)+'\n')
print('Prepared',len(report),'middle doors')
