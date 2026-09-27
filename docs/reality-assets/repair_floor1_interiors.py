"""Make the authored 1F vaults visible from inside and keep the camera in the room.
Also finish the open presentation-set backs/roof shoulders using their existing
materials, so free look cannot expose the environment behind the set.
"""
from pathlib import Path
import json
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf
root = Path(__file__).resolve().parents[2]
contracts = json.loads((root/'docs/final-3d-integration/room-contracts.json').read_text())
reports = []
for r in contracts:
    if r['floor'] != 1: continue
    path = root/'DescentAuthorized/Resources'/r['directory']/(r['resource']+'.usdc')
    stage = Usd.Stage.Open(str(path)); prefix = '/' + r['resource'] + '/'
    roof = next(p for p in stage.Traverse() if p.GetTypeName() == 'Mesh' and any(n in p.GetName() for n in ('PointedBarrelVault', 'VaultedDome')))
    mesh = UsdGeom.Mesh(roof)
    counts = list(mesh.GetFaceVertexCountsAttr().Get())
    def reverse_faces(values):
        result, offset = [], 0
        for count in counts:
            result.extend(reversed(values[offset:offset+count])); offset += count
        assert offset == len(values)
        return result
    inner_path = roof.GetParent().GetPath().AppendChild('InteriorVault')
    Sdf.CopySpec(stage.GetRootLayer(), roof.GetPath(), stage.GetRootLayer(), inner_path)
    inner = UsdGeom.Mesh(stage.GetPrimAtPath(inner_path))
    inner.GetFaceVertexIndicesAttr().Set(reverse_faces(list(mesh.GetFaceVertexIndicesAttr().Get())))
    assert mesh.GetNormalsInterpolation() == 'faceVarying'
    inner.GetNormalsAttr().Set([-n for n in reverse_faces(list(mesh.GetNormalsAttr().Get()))])
    for pv in UsdGeom.PrimvarsAPI(inner).GetPrimvars():
        if pv.GetInterpolation() == 'faceVarying':
            if pv.IsIndexed(): pv.SetIndices(reverse_faces(list(pv.GetIndices())))
            else: pv.Set(reverse_faces(list(pv.Get())))
    inner.CreateDoubleSidedAttr(False); mesh.CreateDoubleSidedAttr(False)
    wall = next(p for p in stage.Traverse() if p.GetTypeName() == 'Mesh' and any(n in p.GetName() for n in ('SideWall','RotundaWall')))
    wall_material = UsdShade.MaterialBindingAPI(wall).ComputeBoundMaterial()[0]
    roof_material = UsdShade.MaterialBindingAPI(roof).ComputeBoundMaterial()[0]
    assert wall_material and roof_material
    def box(name, position, dimensions, material):
        cube = UsdGeom.Cube.Define(stage, prefix + name); cube.CreateSizeAttr(1)
        xf = UsdGeom.Xformable(cube); xf.ClearXformOpOrder()
        xf.AddTranslateOp().Set(Gf.Vec3d(*position)); xf.AddScaleOp().Set(Gf.Vec3f(*dimensions))
        UsdShade.MaterialBindingAPI.Apply(cube.GetPrim()).Bind(material)
    boss = r['role'] == 'administrator'
    if boss:
        # The round hall opens into an authored 22 m wide entrance floor.
        box('EntranceBack', (0,-27,10), (22,.4,20), wall_material)
        for side in [-1,1]:
            box('EntranceSide'+str(side).replace('-','N'), (side*11,-20,10), (.4,14,20), wall_material)
        box('EntranceCeiling', (0,-20,20), (22,14,.3), roof_material)
    else:
        width, height, end_y = (24,12.5,27) if r['role']=='residualA' else (30,14,28)
        box('EntranceBack', (0,-24,height), (width,.4,height*2), wall_material)
        # Authored barrel spans 2 m less on either side than the side walls.
        for side in [-1,1]:
            box('VaultShoulder'+str(side).replace('-','N'), (side*(width/2-1), (end_y-24)/2, height),
                (2,end_y+24,.2), roof_material)
    camera = UsdGeom.Xformable(stage.GetPrimAtPath(prefix+r['cameras']['main']))
    matrix = camera.GetLocalTransformation(); pos = matrix.ExtractTranslation()
    matrix.SetTranslateOnly(Gf.Vec3d(pos[0], -12 if boss else -18, pos[2]))
    camera.MakeMatrixXform().Set(matrix)
    stage.GetRootLayer().Save()
    reports.append(dict(asset=path.name, cameraPosition=list(matrix.ExtractTranslation()), interiorVaultFaces=len(counts)))
(root/'docs/reality-assets/floor1-interior-184.json').write_text(json.dumps(reports,indent=2)+'\n')
