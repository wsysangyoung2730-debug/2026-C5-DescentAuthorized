"""Replace unsupported USD curves with authored Blender bevel meshes, in all quality levels.
Run with pxr: python restore_floor3_curve_meshes.py EXTRACTED.json
Retains each existing object's world transform and installed material binding.
"""
from pathlib import Path
import json, sys
from pxr import Usd, UsdGeom, UsdShade, Gf
root = Path(__file__).resolve().parents[2]
folder = root/'DescentAuthorized/Resources/Reality/Scenes/Floor03/VoluntaryQuarantineAdministrator'
rows = json.loads(Path(sys.argv[1]).read_text())
assert len(rows) == 365
reports = []
for path in sorted(folder.glob('*.usdc')):
    stage = Usd.Stage.Open(str(path))
    counts = 0
    for row in rows:
        parent = stage.GetPrimAtPath('/floor03_voluntary_quarantine_administrator/' + row['name'])
        assert parent, row['name']
        geometry = [p for p in Usd.PrimRange(parent) if p.GetTypeName() in ('BasisCurves','Mesh')]
        assert geometry, row['name']
        material = UsdShade.MaterialBindingAPI(geometry[0]).ComputeBoundMaterial()[0]
        assert material, row['name']
        material_path = material.GetPath()
        # Curves were duplicated under an extra export wrapper; keep one bevel mesh.
        for child in list(parent.GetChildren()): stage.RemovePrim(child.GetPath())
        mesh = UsdGeom.Mesh.Define(stage, parent.GetPath().AppendChild('AuthoredBevelMesh'))
        mesh.CreatePointsAttr(row['points'])
        mesh.CreateFaceVertexCountsAttr(row['counts'])
        mesh.CreateFaceVertexIndicesAttr(row['indices'])
        mesh.CreateNormalsAttr(row['normals']); mesh.SetNormalsInterpolation('uniform')
        mesh.CreateSubdivisionSchemeAttr('none'); mesh.CreateDoubleSidedAttr(True)
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(UsdShade.Material(stage.GetPrimAtPath(material_path)))
        counts += 1
    camera = UsdGeom.Xformable(stage.GetPrimAtPath('/floor03_voluntary_quarantine_administrator/F03C_MainCamera'))
    matrix = camera.GetLocalTransformation()
    position = matrix.ExtractTranslation()
    # Source eye is at y=-12 outside the front wall (circle centre y=6, radius 15.5).
    # Move inside the authored room; absolute placement keeps this script repeatable.
    matrix.SetTranslateOnly(Gf.Vec3d(position[0], -7.5, position[2]))
    camera.MakeMatrixXform().Set(matrix)
    assert not any(p.GetTypeName()=='BasisCurves' for p in stage.Traverse())
    stage.GetRootLayer().Save()
    reports.append({'asset':path.name,'restoredCurveObjects':counts,'remainingCurves':0,'cameraPosition':list(matrix.ExtractTranslation())})
(root/'docs/reality-assets/floor3-restored-180.json').write_text(json.dumps(reports,indent=2)+'\n')
print(json.dumps(reports,indent=2))
