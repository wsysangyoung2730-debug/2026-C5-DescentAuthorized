"""Extract evaluated bevel meshes from the authored 3F boss room; never save the blend.
Run: blender -b SOURCE.blend --python export_floor3_curves.py -- OUTPUT.json
"""
import bpy, json, sys
from pathlib import Path
scene = bpy.data.scenes['DA_F03_VoluntaryIsolationAdministrator']
bpy.context.window.scene = scene
scene.frame_set(1)
bpy.context.view_layer.update()
graph = bpy.context.evaluated_depsgraph_get()
rows = []
for obj in scene.objects:
    if obj.type != 'CURVE' or obj.hide_render:
        continue
    evaluated = obj.evaluated_get(graph)
    mesh = evaluated.to_mesh()
    if not mesh.polygons:
        raise RuntimeError('Missing bevel surface: ' + obj.name)
    rows.append(dict(name=obj.name.replace('.', '_'),
        points=[list(v.co) for v in mesh.vertices],
        counts=[len(p.vertices) for p in mesh.polygons],
        indices=[v for p in mesh.polygons for v in p.vertices],
        normals=[list(p.normal) for p in mesh.polygons]))
    evaluated.to_mesh_clear()
Path(sys.argv[sys.argv.index('--')+1]).write_text(json.dumps(rows))
print('EXTRACTED_CURVE_MESHES', len(rows), flush=True)
