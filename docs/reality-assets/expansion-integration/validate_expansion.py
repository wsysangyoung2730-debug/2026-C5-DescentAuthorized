"""Validate shipped six-room scene/actor contracts across every quality."""
import argparse,json
from pathlib import Path
from pxr import Usd,UsdGeom,UsdSkel,Sdf
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
configs=[(7,'CoordinateResidue','coordinate_residue',False),(7,'CoordinateAdministrator','coordinate_administrator',True),(6,'CausalityResidue','causality_residue',False),(6,'CausalityAdministrator','causality_administrator',True),(5,'MemoryOmissionResidue','memory_omission_residue',False),(5,'OriginalMemoryAdministrator','original_memory_administrator',True)]
report=[]
def inspect(path,cap):
 s=Usd.Stage.Open(str(path));assert s,path
 assert UsdGeom.GetStageUpAxis(s)=='Z' and UsdGeom.GetStageMetersPerUnit(s)==1,path
 names={p.GetName() for p in s.Traverse()};textures=set();triangles=0
 for p in s.Traverse():
  if p.IsA(UsdGeom.Mesh):
   mesh=UsdGeom.Mesh(p);counts=mesh.GetFaceVertexCountsAttr().Get();triangles+=sum(max(c-2,0) for c in counts or [])
   for uv in UsdGeom.PrimvarsAPI(p).GetPrimvars():
    if uv.GetTypeName() in (Sdf.ValueTypeNames.TexCoord2fArray,Sdf.ValueTypeNames.Float2Array):assert not uv.IsIndexed(),(path,p.GetPath())
  for attr in p.GetAttributes():
   if attr.GetTypeName()==Sdf.ValueTypeNames.Asset:
    asset=attr.Get()
    if not asset or not asset.path:continue
    resolved=Path(asset.resolvedPath);assert asset.resolvedPath and resolved.is_file(),(path,asset)
    if resolved.suffix.lower() in ('.png','.jpg','.jpeg'):
     textures.add(str(resolved))
     with Image.open(resolved) as image:assert max(image.size)<=cap,(path,resolved,image.size)
 return s,names,triangles,len(textures)
for floor,name,stem,boss in configs:
 prefix=f'F0{floor}'+('B' if boss else 'A');directory=a.root/'Scenes'/f'Floor0{floor}'/name
 cameras=[f'F0{floor}_iPad_MainCamera',f'CAM_F0{floor}_RewardSelection',f'CAM_F0{floor}_DescentDoor'] if boss else [f'F0{floor}A_iPadCamera' if floor!=5 else 'F05A_iPad_MainCamera',f'CAM_F0{floor}A_BossAccessDoor' if floor!=5 else 'CAM_F05A_BossAccess']
 required=cameras+[prefix+'_MagicInputBoard','SPAWN_'+name]
 if boss:required += [prefix+'_RewardSelection',prefix+'_DescentStele','F05B_DescentInputPedestal' if floor==5 else prefix+'_DescentPedestal']+[f'ANCHOR_F0{floor}_RewardSlot_'+s for s in ('Left','Center','Right')]
 for q,cap in [('high',2048),('medium',1024),('low',512)]:
  suffix='' if q=='high' else '_'+q;path=directory/(f'floor0{floor}_{stem}'+suffix+'.usdc')
  stage,names,tris,tex=inspect(path,cap)
  assert set(required)<=names,(path,set(required)-names)
  assert not any('RewardScroll_' in n for n in names),(path,'static reward scroll duplicate')
  if floor==5 and not boss:assert not any('CombatStage' in n or 'ArenaCircuit' in n for n in names),(path,'boss stage in residue')
  if q!='high':assert path.stat().st_size<250000,(path,'duplicated quality geometry')
  actor=a.root/'Actors'/name/(stem+suffix+'.usdc');s,anames,atr,atex=inspect(actor,cap)
  assert 'ACTOR_'+name in anames
  skel=[p for p in s.Traverse() if p.IsA(UsdSkel.Skeleton)];anim=[p for p in s.Traverse() if p.IsA(UsdSkel.Animation)]
  assert len(skel)==1 and len(anim)==1,actor
  assert len(UsdSkel.Skeleton(skel[0]).GetJointsAttr().Get())==5,actor
  motion=json.loads((actor.parent/'motion.json').read_text())
  assert set(motion['clips'])=={'idle','appear','telegraph','attack','heavyAttack','special','hit','death'}
  assert len(UsdSkel.Animation(anim[0]).GetRotationsAttr().GetTimeSamples())>100
  report.append({'floor':floor,'boss':boss,'quality':q,'roomTriangles':tris,'roomTextures':tex,'actorTriangles':atr,'actorTextures':atex,'requiredEntities':len(required)})
 assert (directory/'environment.hdr').is_file()
a.report.write_text(json.dumps(report,indent=2));print('PASS: 18 room variants, 18 actor variants, 6 rigs and 48 motion ranges')
