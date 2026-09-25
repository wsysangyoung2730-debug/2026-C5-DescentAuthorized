"""Extract the verified 8F reward device and motion into a reusable local-space asset.
Run with Blender bundled Python (pxr) after updating the source 8F device.
"""
from pathlib import Path
import json, shutil
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf
ROOT=Path(__file__).resolve().parents[2]
R=ROOT/'DescentAuthorized/Resources/Reality'
out=R/'Interactables/RewardDevice';out.mkdir(parents=True,exist_ok=True)
source=R/'Scenes/Floor08/AdministratorObservatory'
origin=Gf.Vec3d(-8.100000381469727,12,0)
for quality,suffix in [('high',''),('medium','_medium'),('low','_low')]:
 src=Usd.Stage.Open(str(source/f'floor08_administrator_observatory{suffix}.usdc'))
 srclayer=src.Flatten()
 srcroot=src.GetPseudoRoot().GetChildren()[0].GetPath();newroot=Sdf.Path('/DA_SharedRewardDevice')
 path=out/f'reward_device{suffix}.usdc'
 if path.exists():path.unlink()
 dst=Usd.Stage.CreateNew(str(path));root=UsdGeom.Xform.Define(dst,newroot);dst.SetDefaultPrim(root.GetPrim());UsdGeom.SetStageUpAxis(dst,UsdGeom.Tokens.z);UsdGeom.SetStageMetersPerUnit(dst,1)
 byname={p.GetName():p for p in src.Traverse()}; selected=[byname['F08B_RewardStand']]+[byname[f'F08B_RewardScroll_{slot}_HoleAnchor'] for slot in ['Left','Center','Right']]
 materials={}
 for p in selected:
  Sdf.CopySpec(srclayer,p.GetPath(),dst.GetRootLayer(),newroot.AppendChild(p.GetName()))
  for q in Usd.PrimRange(p):
   if q.IsA(UsdGeom.Mesh):
    mat,_=UsdShade.MaterialBindingAPI(q).ComputeBoundMaterial()
    if mat:materials[str(mat.GetPath())]=mat.GetPrim()
 UsdGeom.Scope.Define(dst,newroot.AppendChild('_materials'))
 for mat in materials.values():Sdf.CopySpec(srclayer,mat.GetPath(),dst.GetRootLayer(),mat.GetPath().ReplacePrefix(srcroot,newroot))
 for p in dst.Traverse():
  for rel in p.GetRelationships():rel.SetTargets([t.ReplacePrefix(srcroot,newroot) for t in rel.GetTargets()])
  for attr in p.GetAttributes():
   if attr.GetConnections():attr.SetConnections([t.ReplacePrefix(srcroot,newroot) for t in attr.GetConnections()])
   val=attr.Get()
   if isinstance(val,Sdf.AssetPath) and val.path:
    tex=Path(val.path);tex=tex if tex.is_absolute() else source/tex
    assert tex.is_file(),tex
    dest=out/'textures'/quality/tex.name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(tex,dest)
    attr.Set(Sdf.AssetPath(dest.relative_to(out).as_posix()))
  if p.GetName()=='F08B_RewardStand' or p.GetName().endswith('_Appear'):
   xf=UsdGeom.Xformable(p);m=xf.GetLocalTransformation();m.SetTranslateOnly(m.ExtractTranslation()-origin);xf.MakeMatrixXform().Set(m)
 dst.GetRootLayer().Save();print('shared asset',quality,len(materials),'materials')
motion=json.loads((source/'floor08_reward_motion.json').read_text())
for t in motion['tracks']:
 if t['entity'].endswith('_Appear'):
  for m in t['matrices']:
   for i in range(3):m[12+i]-=origin[i]
(out/'reward_device_motion.json').write_text(json.dumps(motion,separators=(',',':')))
