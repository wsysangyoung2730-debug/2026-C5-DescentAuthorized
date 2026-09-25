"""Per-room encoded resources and a conservative RGBA8+mipmap texture estimate, not GPU measurement."""
import json
from pathlib import Path
from PIL import Image
from pxr import Usd,UsdGeom,Sdf
root=Path(__file__).resolve().parents[2]/'DescentAuthorized/Resources';out=[]
for r in json.loads((root/'Reality/FinalSceneManifest.json').read_text()):
 for quality in ['high','medium','low']:
  file=root/r['directory']/(r['resource']+('' if quality=='high'else'_'+quality)+'.usdc');s=Usd.Stage.Open(str(file));textures=set();triangles=0
  for p in s.Traverse():
   if p.IsA(UsdGeom.Mesh):triangles+=sum(max(0,n-2)for n in UsdGeom.Mesh(p).GetFaceVertexCountsAttr().Get())
   for attr in p.GetAttributes():
    if attr.GetTypeName()==Sdf.ValueTypeNames.Asset:
     v=attr.Get()
     if v and v.resolvedPath:textures.add(Path(v.resolvedPath))
  pixels=0;encoded=0;maxedge=0
  for texture in textures:
   with Image.open(texture)as im:w,h=im.size
   pixels+=w*h;encoded+=texture.stat().st_size;maxedge=max(maxedge,w,h)
  out.append({'scene':r['resource'],'quality':quality,'triangles':triangles,'uniqueTextures':len(textures),'textureEncodedBytes':encoded,'textureRGBA8WithMipmapsEstimateBytes':round(pixels*4*4/3),'largestTextureEdge':maxedge,'meshLOD':False})
(Path(__file__).parent/'validation/asset-budgets.json').write_text(json.dumps(out,indent=2)+'\n')
print('Measured',len(out),'room/quality entries')
