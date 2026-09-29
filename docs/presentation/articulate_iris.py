"""Repartition floor 2 sliding leaves into eight rigid iris blades without changing UVs."""
import json,math
from pathlib import Path
import numpy as np
from pxr import Usd,UsdGeom,UsdShade,Sdf,Gf,Vt
root=Path(__file__).resolve().parents[2];res=root/'DescentAuthorized/Resources'
# Reuse only the polygon helpers, without running the middle-door conversion.
source=(root/'docs/presentation/articulate_middle_doors.py').read_text();exec(source[source.index('def split_polygon'):source.index('report=[]')])
row=next(r for r in json.loads((res/'Reality/FinalSceneManifest.json').read_text()) if r['floor']==2 and r['role']=='administrator')
s=Usd.Stage.Open(str(res/row['directory']/(row['resource']+'.usdc')));layer=s.GetRootLayer();prefix=row['doorAnimationPrefix'];gate=next(p for p in s.Traverse() if p.GetName()==row['anchors']['descentDoor']);cache=UsdGeom.XformCache();inverse=cache.GetLocalToWorldTransform(gate).GetInverse()
rotor=UsdGeom.Xform.Define(s,gate.GetPath().AppendChild(prefix+'_IrisLens'));blades=[]
for i in range(8):
 angle=(i+.5)*math.pi/4;pivot=np.array([math.cos(angle)*.335,0,.51+math.sin(angle)*.335]);blade=UsdGeom.Xform.Define(s,rotor.GetPath().AppendChild(prefix+'_IrisBlade_'+str(i)));blade.AddTranslateOp().Set(Gf.Vec3d(*pivot));blades.append((blade,pivot))
leaves=[p for p in s.Traverse() if p.GetName() in [prefix+'_Door_LeftPanel',prefix+'_Door_RightPanel']]
for li,leaf in enumerate(leaves):
 for mi,prim in enumerate([p for p in Usd.PrimRange(leaf) if p.IsA(UsdGeom.Mesh)]):
  mesh=UsdGeom.Mesh(prim);points=np.array(mesh.GetPointsAttr().Get(),float);matrix=np.array(cache.GetLocalToWorldTransform(prim)*inverse);local=points@matrix[:3,:3]+matrix[3,:3];counts=np.array(mesh.GetFaceVertexCountsAttr().Get());indices=np.array(mesh.GetFaceVertexIndicesAttr().Get());offset=np.r_[0,np.cumsum(counts)];normals=np.array(mesh.GetNormalsAttr().Get());uvs=np.array(UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st').ComputeFlattened());output=[[]for _ in range(8)]
  for f in range(len(counts)):
   corners=np.arange(offset[f],offset[f+1]);verts=indices[corners];poly=list(np.concatenate([local[verts],normals[corners],uvs[corners]],axis=1))
   for i in range(8):
    a=i*math.pi/4;b=(i+1)*math.pi/4;n1=np.array([math.sin(a),0,-math.cos(a)]);n2=np.array([-math.sin(b),0,math.cos(b)])
    cut,_=split_polygon(poly,n1,n1[2]*.51);cut,_=split_polygon(cut,n2,n2[2]*.51) if len(cut)>=3 else ([],[])
    if len(cut)>=3:
     pivot=blades[i][1];cut=[np.r_[v[:3]-pivot,v[3:]] for v in cut];output[i].append((f,cut))
  for i,polys in enumerate(output):
   if not polys:continue
   dest=blades[i][0].GetPath().AppendChild('Surface_'+str(li)+'_'+str(mi));Sdf.CopySpec(layer,prim.GetPath(),layer,dest);write_mesh(UsdGeom.Mesh(s.GetPrimAtPath(dest)),polys)
 for child in list(leaf.GetChildren()):s.RemovePrim(child.GetPath())
# A shallow metal lens barrel moves forward with the blades.
vertices=[];faces=[]
for y in [-.15,.045]:
 for radius in [.335,.37]:
  vertices += [Gf.Vec3f(math.cos(i*math.pi/32)*radius,y,.51+math.sin(i*math.pi/32)*radius) for i in range(64)]
for i in range(64):
 j=(i+1)%64
 for a,b in [(0,64),(64,192),(128,192),(0,128)]:faces += [a+i,a+j,b+j,b+i]
housing=UsdGeom.Mesh.Define(s,rotor.GetPath().AppendChild(prefix+'_LensBarrel'));housing.GetPointsAttr().Set(vertices);housing.GetFaceVertexCountsAttr().Set([4]*(len(faces)//4));housing.GetFaceVertexIndicesAttr().Set(faces);housing.GetDoubleSidedAttr().Set(True)
mat=UsdShade.Material.Define(s,rotor.GetPath().AppendChild('BarrelMetal'));shader=UsdShade.Shader.Define(s,mat.GetPath().AppendChild('Surface'));shader.CreateIdAttr('UsdPreviewSurface');shader.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set((.14,.11,.07));shader.CreateInput('metallic',Sdf.ValueTypeNames.Float).Set(.85);shader.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.28);mat.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(),'surface');UsdShade.MaterialBindingAPI.Apply(housing.GetPrim()).Bind(mat)
layer.Save();print('Created floor 2 lens and eight iris blades')
