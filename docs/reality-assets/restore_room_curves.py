"""Restore Blender-evaluated bevel surfaces in each installed quality variant.
Usage (pxr Python): restore_room_curves.py EXTRACTED.json REPORT.json
Object transforms and material bindings are retained; duplicate USD curve wrappers
are replaced with a single mesh. Safe to rerun on already restored rooms.
"""
from pathlib import Path
import json, sys
from pxr import Usd, UsdGeom, UsdShade
root = Path(__file__).resolve().parents[2]
reports = []
for room in json.loads(Path(sys.argv[1]).read_text()):
    contract = room['contract']
    folder = root / 'DescentAuthorized/Resources' / contract['directory']
    for path in sorted(folder.glob('*.usdc')):
        stage = Usd.Stage.Open(str(path))
        restored = 0
        inherited = bool(stage.GetRootLayer().subLayerPaths)
        parents = {p.GetName(): p for p in stage.Traverse() if p.GetTypeName() == 'Xform'}
        for row in room['curves']:
            parent = parents.get(row['name'])
            assert parent, row['name']
            geometry = [p for p in Usd.PrimRange(parent) if p.GetTypeName() in ('BasisCurves', 'Mesh')]
            assert geometry, row['name']
            if inherited:
                assert any(p.GetName() == 'AuthoredBevelMesh' for p in geometry), row['name']
                restored += 1
                continue
            material = UsdShade.MaterialBindingAPI(geometry[0]).ComputeBoundMaterial()[0]
            assert material, row['name']
            material_path = material.GetPath()
            for child in list(parent.GetChildren()):
                stage.RemovePrim(child.GetPath())
            mesh = UsdGeom.Mesh.Define(stage, parent.GetPath().AppendChild('AuthoredBevelMesh'))
            mesh.CreatePointsAttr(row['points'])
            mesh.CreateFaceVertexCountsAttr(row['counts'])
            mesh.CreateFaceVertexIndicesAttr(row['indices'])
            mesh.CreateNormalsAttr(row['normals'])
            mesh.SetNormalsInterpolation('uniform')
            mesh.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(mesh.GetPointsAttr().Get()))
            mesh.CreateSubdivisionSchemeAttr('none')
            mesh.CreateDoubleSidedAttr(True)
            UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(UsdShade.Material(stage.GetPrimAtPath(material_path)))
            restored += 1
        remaining = sum(p.GetTypeName() == 'BasisCurves' for p in stage.Traverse())
        assert remaining == 0, (path, remaining)
        stage.GetRootLayer().Save()
        reports.append(dict(asset=str(path.relative_to(root)), restoredCurveObjects=restored, remainingCurves=remaining))
Path(sys.argv[2]).write_text(json.dumps(reports, indent=2) + '\n')
print(json.dumps(reports, indent=2))
