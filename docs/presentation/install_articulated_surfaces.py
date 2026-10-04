"""Keep fracture surfaces and restore a separate, bound skeletal surface for combat.
Source commit contains the repaired SkelRoot bindings. Only attack ranges are amplified.
"""
from pathlib import Path
import subprocess,json,math
from pxr import Usd,UsdGeom,UsdSkel,Gf,Vt
ROOT=Path(__file__).resolve().parents[2]
for folder in sorted((ROOT/'DescentAuthorized/Resources/Reality/Actors').iterdir()):
 base=next(p for p in folder.glob('*.usdc') if not p.stem.endswith(('_low','_medium')) and p.name!='articulated.usdc')
 rel=base.relative_to(ROOT);dest=folder/'articulated.usdc'
 dest.write_bytes(subprocess.check_output(['git','show','8759c5c:'+str(rel)],cwd=ROOT))
 stage=Usd.Stage.Open(str(dest));manifest=json.loads((folder/'motion.json').read_text());clips=manifest['clips']
 # Leave the idle/rest pose intact, amplify arm gestures only (equipment keeps its rigid binding).
 for prim in stage.Traverse():
  if not prim.IsA(UsdSkel.Animation):continue
  anim=UsdSkel.Animation(prim);joints=list(anim.GetJointsAttr().Get());attr=anim.GetRotationsAttr();fps=stage.GetTimeCodesPerSecond()
  for t in attr.GetTimeSamples():
   seconds=t/fps
   active=next((name for name in ['attack','heavyAttack','special','telegraph'] if name in clips and clips[name]['start']<=seconds<=clips[name]['end']),None)
   if not active:continue
   quats=list(attr.Get(t))
   for i,j in enumerate(joints):
    name=j.split('/')[-1].lower()
    if not any(n in name for n in ['arm','hand']):continue
    q=quats[i];angle=2*math.acos(max(-1,min(1,float(q.GetReal()))));v=Gf.Vec3d(q.GetImaginary());length=v.GetLength()
    if length<1e-7:continue
    # Rotations contain bone-rest orientation: amplify delta from the first sample of this clip.
    reference=attr.Get(round(clips[active]['start']*fps))[i]
    delta=Gf.Quatd(q)*Gf.Quatd(reference).GetInverse();rotation=Gf.Rotation(delta)
    factor=1.6 if active in ['attack','heavyAttack'] else 1.3
    boosted=Gf.Rotation(rotation.GetAxis(),rotation.GetAngle()*factor).GetQuat()*Gf.Quatd(reference)
    quats[i]=Gf.Quatf(boosted)
   attr.Set(Vt.QuatfArray(quats),t)
 stage.GetRootLayer().Save()
 current=Usd.Stage.Open(str(base));top=current.GetDefaultPrim()
 if not top:top=next(current.GetPseudoRoot().GetChildren())
 child=UsdGeom.Xform.Define(current,top.GetPath().AppendChild('DA_Articulated')).GetPrim()
 child.GetReferences().AddReference('./articulated.usdc',stage.GetDefaultPrim().GetPath() if stage.GetDefaultPrim() else stage.GetPseudoRoot().GetChildren()[0].GetPath())
 current.GetRootLayer().Save();print(folder.name,flush=True)
