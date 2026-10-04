"""Repair 8F descent leaves without moving the lintel or jambs.
Run once on the pre-repair USD. Closed positions, normals, UVs and materials
are preserved; only exact polygons inside the portal opening can slide.
"""
import json
from pathlib import Path
import numpy as np
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt

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

def area(polys):
    return sum(float(np.linalg.norm(np.cross(p[i][:3]-p[0][:3], p[i+1][:3]-p[0][:3]))) / 2
               for _, p in polys for i in range(1,len(p)-1))

root=Path(__file__).resolve().parents[2]
file=root/'DescentAuthorized/Resources/Reality/Scenes/Floor08/AdministratorObservatory/floor08_administrator_observatory.usdc'
stage=Usd.Stage.Open(str(file)); layer=stage.GetRootLayer()
gate=next(p for p in stage.Traverse() if p.GetName()=='F08B_DescentDoor')
assert not gate.GetCustomDataByKey('exactLeafPartition'), 'Already repaired'
cache=UsdGeom.XformCache(); inverse=cache.GetLocalToWorldTransform(gate).GetInverse()
controllers=[stage.GetPrimAtPath(gate.GetPath().AppendChild('F08B_Door_'+s)) for s in ['LeftPanel','RightPanel','Frame','LogoLight']]
meshes=[p for c in controllers for p in Usd.PrimRange(c) if p.IsA(UsdGeom.Mesh)]
# Match the authored portal rectangle, below the fixed header and inside the jambs.
half,bottom,top=.1870946,.05500057,.73500764
planes=[(np.array([1,0,0]),half),(np.array([-1,0,0]),half),(np.array([0,0,1]),top),(np.array([0,0,-1]),-bottom)]
outputs=[]; before_area=0; after_area=0; counts=[0,0,0]
for prim in meshes:
    mesh=UsdGeom.Mesh(prim)
    matrix=np.array(cache.GetLocalToWorldTransform(prim)*inverse)
    points=np.array(mesh.GetPointsAttr().Get(),float)@matrix[:3,:3]+matrix[3,:3]
    indices=np.array(mesh.GetFaceVertexIndicesAttr().Get(),int)
    offsets=np.r_[0,np.cumsum(mesh.GetFaceVertexCountsAttr().Get())]
    normals=np.array(mesh.GetNormalsAttr().Get(),float)
    uv=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st'); tex=np.array(uv.ComputeFlattened(),float)
    output=[[],[],[]]
    for face in range(len(offsets)-1):
        corners=np.arange(offsets[face],offsets[face+1]); verts=indices[corners]
        ns=normals[corners if mesh.GetNormalsInterpolation()=='faceVarying' else verts]@np.linalg.inv(matrix[:3,:3]).T
        ts=tex[corners if uv.GetInterpolation()=='faceVarying' else verts]
        poly=list(np.concatenate([points[verts],ns,ts],axis=1))
        before_area+=area([(face,poly)])
        for axis,limit in planes:
            poly,outside=split_polygon(poly,axis,limit)
            if len(outside)>=3:output[2].append((face,outside))
            if len(poly)<3:break
        if len(poly)>=3:
            left,right=split_polygon(poly,np.array([1,0,0]),0)
            for side,part in enumerate([left,right]):
                if len(part)>=3:output[side].append((face,part))
    for side,polys in enumerate(output):
        counts[side]+=len(polys);after_area+=area(polys)
    outputs.append((prim.GetPath(),output))
assert abs(before_area-after_area)<before_area*1e-6,(before_area,after_area)
# Copy before deleting source hierarchies; bind targets live outside the door.
old_children=[c.GetPath() for controller in controllers for c in controller.GetChildren()]
for mi,(path,output) in enumerate(outputs):
    for side,polys in enumerate(output):
        if not polys:continue
        target=controllers[side].GetPath().AppendChild('ExactSurface_'+str(mi))
        Sdf.CopySpec(layer,path,layer,target)
        mesh=UsdGeom.Mesh(stage.GetPrimAtPath(target));write_mesh(mesh,polys)
        uv=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st')
        if uv.IsIndexed():uv.BlockIndices()
        assert UsdShade.MaterialBindingAPI(mesh).ComputeBoundMaterial()[0]
for path in old_children:stage.RemovePrim(path)
for controller in controllers:UsdGeom.Xformable(controller).ClearXformOpOrder()
gate.SetCustomDataByKey('exactLeafPartition', True)
for side,controller in enumerate(controllers[:2]):
    pts=np.concatenate([np.array(UsdGeom.Mesh(p).GetPointsAttr().Get()) for p in Usd.PrimRange(controller) if p.IsA(UsdGeom.Mesh)])
    assert pts[:,2].min()>=bottom-1e-6 and pts[:,2].max()<=top+1e-6
    assert pts[:,0].min()>=(-half if side==0 else 0)-1e-6
    assert pts[:,0].max()<=(0 if side==0 else half)+1e-6
layer.Save()
report={'gate':'F08B_DescentDoor','opening':{'halfWidth':half,'bottom':bottom,'top':top},
        'faces':dict(zip(['left','right','fixed'],counts)),'surfaceAreaBefore':before_area,
        'surfaceAreaAfter':after_area,'closedSurfacePreserved':True,'materialBindingsResolved':True}
(root/'docs/presentation/floor8-door-partition.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
