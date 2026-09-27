"""Read evaluated authored curves without changing/saving the Blender source.
blender -b SOURCE.blend --python export_room_curves.py -- FLOOR OUTPUT.json
"""
import bpy, json, sys
from pathlib import Path
args = sys.argv[sys.argv.index('--') + 1:]
floor, output = int(args[0]), Path(args[1])
contracts = json.loads((Path(__file__).resolve().parents[1] / 'final-3d-integration/room-contracts.json').read_text())
rooms = []
for contract in contracts:
    if contract['floor'] != floor:
        continue
    scene = bpy.data.scenes[contract['scene']]
    bpy.context.window.scene = scene
    scene.frame_set(1)
    bpy.context.view_layer.update()
    graph = bpy.context.evaluated_depsgraph_get()
    rows, boundaries = [], []
    for obj in scene.objects:
        if obj.hide_render:
            continue
        if obj.type in ('MESH', 'CURVE') and any(word in obj.name.lower() for word in ('wall', 'roof', 'ceiling', 'floor')):
            from mathutils import Vector
            corners = [obj.matrix_world @ Vector(v) for v in obj.bound_box]
            boundaries.append(dict(name=obj.name, low=[min(v[i] for v in corners) for i in range(3)], high=[max(v[i] for v in corners) for i in range(3)]))
        if obj.type != 'CURVE':
            continue
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        if not mesh.polygons:
            raise RuntimeError('Missing bevel surface: ' + obj.name)
        rows.append(dict(name=obj.name.replace('.', '_'), points=[list(v.co) for v in mesh.vertices],
            counts=[len(p.vertices) for p in mesh.polygons], indices=[v for p in mesh.polygons for v in p.vertices],
            normals=[list(p.normal) for p in mesh.polygons]))
        evaluated.to_mesh_clear()
    rooms.append(dict(contract=contract, curves=rows, boundaries=boundaries))
    print('EXTRACTED', contract['name'], len(rows), flush=True)
output.write_text(json.dumps(rooms))
