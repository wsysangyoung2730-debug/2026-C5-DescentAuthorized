"""Put 2F cameras inside their authored rooms and close cutaway entrance backs.
The source cameras were behind the front edge (A/B -10, C -11). Existing
side/rear/roof meshes are closed solids; they do not need duplicate inner faces.
"""
from pathlib import Path
import json
from pxr import Usd, UsdGeom, UsdShade, Gf
root = Path(__file__).resolve().parents[2]
contracts = json.loads((root/'docs/final-3d-integration/room-contracts.json').read_text())
reports = []
for r in contracts:
    if r['floor'] != 2: continue
    for path in sorted((root/'DescentAuthorized/Resources'/r['directory']).glob('*.usdc')):
        stage = Usd.Stage.Open(str(path)); prefix = '/' + r['resource'] + '/'
        camera = UsdGeom.Xformable(stage.GetPrimAtPath(prefix + r['cameras']['main']))
        matrix = camera.GetLocalTransformation(); position = matrix.ExtractTranslation()
        y = -8.5 if r['role'] == 'administrator' else -7
        matrix.SetTranslateOnly(Gf.Vec3d(position[0], y, position[2]))
        camera.MakeMatrixXform().Set(matrix)
        if r['role'] != 'administrator':
            # The Blender composition is open behind the viewer. Extend its steel
            # shell so the wide, freely rotated game camera cannot see the void.
            width, height = (20, 7.8) if r['role'] == 'residualA' else (22, 12.4)
            wall = UsdGeom.Cube.Define(stage, prefix + 'InteriorEntranceReturn')
            wall.CreateSizeAttr(1)
            xf = UsdGeom.Xformable(wall)
            xf.ClearXformOpOrder()
            xf.AddTranslateOp().Set(Gf.Vec3d(0, -10, height/2))
            xf.AddScaleOp().Set(Gf.Vec3f(width, .38, height))
            source = next(p for p in stage.Traverse() if p.GetTypeName() == 'Mesh' and p.GetName().startswith(r['prefix'] + '_SideWall'))
            material = UsdShade.MaterialBindingAPI(source).ComputeBoundMaterial()[0]
            assert material
            UsdShade.MaterialBindingAPI.Apply(wall.GetPrim()).Bind(material)
        stage.GetRootLayer().Save()
        reports.append(dict(asset=path.name, cameraPosition=list(matrix.ExtractTranslation()), entranceReturn=r['role'] != 'administrator'))
(root/'docs/reality-assets/floor2-camera-183.json').write_text(json.dumps(reports, indent=2)+'\n')
