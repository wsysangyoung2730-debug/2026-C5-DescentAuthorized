"""Reuse the latest articulated 7F gate in 9F/10F; preserve their placement.
Run with a Python environment containing pxr. Source Blender/GLB are untouched.
"""
from pathlib import Path
import os
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf
ROOT = Path(__file__).resolve().parents[2]
R = ROOT / 'DescentAuthorized/Resources/Reality'
out = R / 'Interactables/LatestDescentDoor'
out.mkdir(parents=True, exist_ok=True)
for suffix in ['', '_medium', '_low']:
    source = R / 'Scenes/Floor07/CoordinateAdministrator' / ('floor07_coordinate_administrator' + suffix + '.usdc')
    src = Usd.Stage.Open(str(source)); flat = src.Flatten()
    gate = next(p for p in src.Traverse() if p.GetName() == 'F07B_DescentDoor')
    dest = out / ('latest_descent_door' + suffix + '.usdc')
    layer = Sdf.Layer.CreateAnonymous(); dst = Usd.Stage.Open(layer)
    path = Sdf.Path('/LatestDescentDoor')
    Sdf.CopySpec(flat, gate.GetPath(), layer, path)
    dst.SetDefaultPrim(dst.GetPrimAtPath(path)); UsdGeom.SetStageUpAxis(dst, 'Z'); UsdGeom.SetStageMetersPerUnit(dst, 1)
    UsdGeom.Xformable(dst.GetDefaultPrim()).MakeMatrixXform().Set(Gf.Matrix4d(1))
    UsdGeom.Scope.Define(dst, path.AppendChild('Materials'))
    mapping = {gate.GetPath(): path}
    materials = {}
    for p in Usd.PrimRange(gate):
        if p.IsA(UsdGeom.Mesh):
            mat, _ = UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()
            if mat: materials[mat.GetPath()] = mat
    for index, matpath in enumerate(materials):
        new = path.AppendChild('Materials').AppendChild('Material_' + str(index))
        mapping[matpath] = new; Sdf.CopySpec(flat, matpath, layer, new)
    def remap(p):
        for old, new in sorted(mapping.items(), key=lambda pair: -len(str(pair[0]))):
            if p.HasPrefix(old): return p.ReplacePrefix(old, new)
        return p
    for p in dst.Traverse():
        for rel in p.GetRelationships(): rel.SetTargets([remap(t) for t in rel.GetTargets()])
        for attr in p.GetAttributes():
            if attr.GetConnections(): attr.SetConnections([remap(t) for t in attr.GetConnections()])
            val = attr.Get()
            if isinstance(val, Sdf.AssetPath) and val.path:
                resolved = Path(val.resolvedPath or str(source.parent / val.path)).resolve()
                attr.Set(Sdf.AssetPath(os.path.relpath(resolved, out)))
    layer.Export(str(dest))
    for floor, directory, name in [(9, 'Floor09/ArchiveRedesign', 'floor09_archive_redesign'), (10, 'Floor10/ClosedOffice', 'floor10_closed_office')]:
        file = R / 'Scenes' / directory / (name + suffix + '.usdc')
        stage = Usd.Stage.Open(str(file)); target = next(p for p in stage.Traverse() if p.GetName() == f'F{floor:02}_DescentDoor')
        for child in list(target.GetChildren()): stage.RemovePrim(child.GetPath())
        target.GetReferences().ClearReferences()
        target.GetReferences().AddReference(os.path.relpath(dest, file.parent))
        stage.GetRootLayer().Save()
print('Updated 9F/10F gates for high, medium and low quality.')
