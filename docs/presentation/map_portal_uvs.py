"""Add planar UVs to authored portal surfaces so every floor accepts the shared vortex material."""
from pathlib import Path
from pxr import Usd,UsdGeom,Sdf
root=Path(__file__).resolve().parents[2]
for file in (root/'DescentAuthorized/Resources/Reality/Scenes').rglob('*.usdc'):
 stage=Usd.Stage.Open(str(file));changed=False
 for prim in stage.Traverse():
  if not prim.IsA(UsdGeom.Mesh) or 'PortalSurface' not in str(prim.GetPath()):continue
  mesh=UsdGeom.Mesh(prim);points=mesh.GetPointsAttr().Get()
  if not points:continue
  lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)];axes=sorted(range(3),key=lambda i:hi[i]-lo[i],reverse=True);u=0 if 0 in axes[:2] else axes[0];v=next(a for a in axes[:2] if a!=u)
  uv=UsdGeom.PrimvarsAPI(mesh).CreatePrimvar('st',Sdf.ValueTypeNames.TexCoord2fArray,'vertex');uv.Set([((p[u]-lo[u])/max(hi[u]-lo[u],1e-6),(p[v]-lo[v])/max(hi[v]-lo[v],1e-6)) for p in points]);uv.BlockIndices();changed=True
 if changed:stage.GetRootLayer().Save();print(file.name)
