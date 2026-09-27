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
    # RealityKit imports the upward-facing roof quads with back-face culling.
    # Author a separate inward surface rather than relying on USD doubleSided.
    roofs = [p for p in stage.Traverse() if p.GetTypeName() == 'Mesh'
             and p.GetName().startswith('F03C_RoofPetal_')]
    assert len(roofs) == 24
    for roof in roofs:
        outer = UsdGeom.Mesh(roof)
        counts_per_face = list(outer.GetFaceVertexCountsAttr().Get())
        def reverse_faces(values):
            result, offset = [], 0
            for count in counts_per_face:
                result.extend(reversed(values[offset:offset + count]))
                offset += count
            assert offset == len(values)
            return result
        inner = UsdGeom.Mesh.Define(stage, roof.GetParent().GetPath().AppendChild('InteriorCeiling'))
        for attr in roof.GetAttributes():
            if attr.HasAuthoredValueOpinion() and attr.Get() is not None:
                copied = inner.GetPrim().CreateAttribute(attr.GetName(), attr.GetTypeName(), attr.IsCustom())
                copied.Set(attr.Get())
                for key, value in attr.GetAllAuthoredMetadata().items():
                    if key not in ('typeName', 'default', 'custom', 'variability'):
                        copied.SetMetadata(key, value)
        inner.GetPointsAttr().Set([Gf.Vec3f(p[0], p[1], p[2] - 0.025)
                                   for p in outer.GetPointsAttr().Get()])
        inner.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(inner.GetPointsAttr().Get()))
        inner.GetFaceVertexIndicesAttr().Set(reverse_faces(list(outer.GetFaceVertexIndicesAttr().Get())))
        assert outer.GetNormalsInterpolation() == 'faceVarying'
        inner.GetNormalsAttr().Set([-n for n in reverse_faces(list(outer.GetNormalsAttr().Get()))])
        for primvar in UsdGeom.PrimvarsAPI(inner).GetPrimvars():
            if primvar.GetInterpolation() == 'faceVarying':
                if primvar.IsIndexed():
                    primvar.SetIndices(reverse_faces(list(primvar.GetIndices())))
                else:
                    primvar.Set(reverse_faces(list(primvar.Get())))
        outer.CreateDoubleSidedAttr(False)
        inner.CreateDoubleSidedAttr(False)
        material = UsdShade.MaterialBindingAPI(roof).ComputeBoundMaterial()[0]
        UsdShade.MaterialBindingAPI.Apply(inner.GetPrim()).Bind(material)
    assert not any(p.GetTypeName()=='BasisCurves' for p in stage.Traverse())
    stage.GetRootLayer().Save()
    reports.append({'asset':path.name,'restoredCurveObjects':counts,'remainingCurves':0,'interiorCeilingPanels':len(roofs),'cameraPosition':list(matrix.ExtractTranslation())})
(root/'docs/reality-assets/floor3-restored-180.json').write_text(json.dumps(reports,indent=2)+'\n')
print(json.dumps(reports,indent=2))
