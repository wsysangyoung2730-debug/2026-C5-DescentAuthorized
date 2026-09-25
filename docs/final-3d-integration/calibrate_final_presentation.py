"""Runtime display adaptations; approved Blender cameras and source textures stay intact."""
import json,math
from pathlib import Path
from pxr import Usd,UsdGeom,UsdShade,Sdf
root=Path(__file__).resolve().parents[2];manifest=root/'DescentAuthorized/Resources/Reality/FinalSceneManifest.json';rows=json.loads(manifest.read_text());report=[]
for r in rows:
 file=root/'DescentAuthorized/Resources'/r['directory']/(r['resource']+'.usdc');stage=Usd.Stage.Open(str(file));pitch={};fov={}
 for name in set(r['cameras'].values()):
  container=next(p for p in stage.Traverse()if p.GetName()==name);camera=next(UsdGeom.Camera(p)for p in Usd.PrimRange(container)if p.IsA(UsdGeom.Camera))
  offset=camera.GetVerticalApertureOffsetAttr().Get();focal=camera.GetFocalLengthAttr().Get()
  if abs(offset)>1e-6:pitch[name]=math.degrees(math.atan(offset/focal))
 if r['role']=='administrator' and r['floor']in[1,3]:
  name=r['cameras']['battle'];pitch[name]=-11 if r['floor']==1 else -3;fov[name]=.65 if r['floor']==1 else .95
 r['cameraPitchDegrees']=pitch;r['cameraFOVScale']=fov
 if r['floor']==1:
  for prim in stage.Traverse():
   if prim.IsA(UsdShade.Material)and 'PolishedBlackFloor' in prim.GetName():
    surface=UsdShade.Material(prim).ComputeSurfaceSource()[0]
    rough=surface.GetInput('roughness');rough.DisconnectSource();rough.Set(.58)
    surface.GetInput('specular').Set(.25)
  stage.GetRootLayer().Save()
 report.append({'room':r['resource'],'pitchDegrees':pitch,'fovScale':fov})
manifest.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
(root/'docs/final-3d-integration/validation/presentation-calibration.json').write_text(json.dumps(report,indent=2)+'\n')
