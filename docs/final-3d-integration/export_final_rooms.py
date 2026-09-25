"""Run in a separate Blender process. Never save the loaded source file.

blender -b SOURCE.blend --python export_final_rooms.py -- --output OUTPUT [--floor 7]
"""
import argparse, json, math, runpy, sys
from pathlib import Path
import bpy
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parent
ap = argparse.ArgumentParser()
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--floor', type=int)
ap.add_argument('--skip-bake', action='store_true')
ap.add_argument('--limit', type=int)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
args.output.mkdir(parents=True, exist_ok=True)
contracts = json.loads((ROOT / 'room-contracts.json').read_text())
rooms = [r for r in contracts if args.floor is None or r['floor'] == args.floor]
if args.limit: rooms = rooms[:args.limit]
source = bpy.data.filepath

def activate(scene):
    bpy.context.window.scene = scene
    scene.frame_set(1)
    bpy.context.view_layer.update()

def find(scene, names):
    for name in names:
        if name in scene.objects: return scene.objects[name]
    raise RuntimeError(f'{scene.name}: required object missing: {names}')

def anchor(scene, name, matrix):
    obj = scene.objects.get(name)
    if obj is None:
        obj = bpy.data.objects.new(name, None)
        scene.collection.objects.link(obj)
    obj.matrix_world = matrix
    obj.empty_display_size = .15
    return obj

def descendants(root):
    yield root
    for child in root.children: yield from descendants(child)

def exclude(obj):
    p = obj
    while p:
        if p.get('runtime_actor_preview') or p.name.startswith('RuntimePreview_'): return True
        p = p.parent
    return obj.hide_render or 'RewardScroll_' in obj.name

def bounds(root):
    points = []
    def visit(obj, matrix):
        if obj.type == 'MESH': points.extend(matrix @ Vector(p) for p in obj.bound_box)
        if obj.instance_collection:
            offset = Matrix.Translation(-obj.instance_collection.instance_offset)
            for member in obj.instance_collection.all_objects:
                if member.type == 'MESH':
                    points.extend(matrix @ offset @ member.matrix_world @ Vector(p) for p in member.bound_box)
        for child in obj.children: visit(child, matrix @ child.matrix_local)
    visit(root, root.matrix_world)
    if not points: raise RuntimeError(f'No geometry under {root.name}')
    return Vector([min(p[i] for p in points) for i in range(3)]), Vector([max(p[i] for p in points) for i in range(3)])

reports = []
for r in rooms:
    scene = bpy.data.scenes[r['scene']]
    activate(scene)
    scene.use_fake_user = True
    prefix, floor = r['prefix'], r['floor']
    aliases = r['anchors']
    spawn = find(scene, [prefix + '_EnemySpawn', 'SPAWN_' + r['name'],
        'SPAWN_' + r['name'].replace('Residual', 'Residue'),
        'SPAWN_ResponsibilityAdministrator'])
    anchor(scene, aliases['enemySpawn'], spawn.matrix_world.copy())
    board = find(scene, [prefix + '_MagicInputBoard'])
    # Keep the complete hierarchy and physical bounds, changing only its identifier.
    board.name = aliases['magicInputBoard']
    if r['role'] == 'administrator':
        stand = find(scene, [prefix + '_SharedRewardStand', prefix + '_RewardSelection'])
        stand.name = aliases['rewardStand']
        lo, hi = bounds(stand)
        center = (lo + hi) / 2
        for i, slot in enumerate(['Left', 'Center', 'Right']):
            old = scene.objects.get(f'ANCHOR_F0{floor}_RewardSlot_{slot}')
            # Existing authored slots take priority. Missing slots use the empty stand top.
            matrix = old.matrix_world.copy() if old else Matrix.Translation((center.x + (i-1)*(hi.x-lo.x)*.25, center.y, hi.z + .1))
            anchor(scene, aliases['rewardScroll' + slot], matrix)
        stele = find(scene, [prefix + '_SharedDescentTerminal', prefix + '_SharedDescentInput',
            prefix + '_DescentInputPedestal' if floor == 3 else prefix + '_DescentStele', 'F04C_P15_01'])
        stele.name = aliases['descentStele']
        pad = find(scene, [prefix + '_DescentInputPlate', prefix + '_DescentPedestal', prefix + '_DescentInputPedestal'])
        pad.name = aliases['descentPedestal']
    scene.camera = find(scene, [r['cameras']['battle']])
    for name in set(r['cameras'].values()):
        camera = find(scene, [name])
        camera.data = camera.data.copy()
        camera.data.name = name

    # Remove static reward scrolls only from the export copy. Keep slot anchors.
    for obj in list(scene.objects):
        if exclude(obj) and 'RewardScroll_' in obj.name:
            scene.collection.objects.unlink(obj) if obj.name in scene.collection.objects else None
            obj.hide_render = True
    reports.append({'scene':scene.name,'resource':r['resource'],'source':source,
        'cameras':r['cameras'],'anchors':aliases,
        'spawn':list(scene.objects[aliases['enemySpawn']].matrix_world.translation)})

if not args.skip_bake:
    # Execute the existing portable surface baker with localized node lookup fixed.
    repair_path = ROOT.parent / 'reality-assets' / 'repair_portable_surfaces.py'
    code = repair_path.read_text().replace("portable.node_tree.nodes.get('Principled BSDF')",
        "next(n for n in portable.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')")
    namespace = {'__name__':'final_surface_bake'}
    exec(compile(code, str(repair_path), 'exec'), namespace)
    namespace.update(SCENES=[r['scene'] for r in rooms], SIZE=1024, OUT=args.output/'surfaces')
    namespace['OUT'].mkdir(exist_ok=True)
    namespace['repair']()

# Cap images once, including collection-instance materials. Imported UVs remain intact.
for image in bpy.data.images:
    if image.type == 'IMAGE' and image.size[0] and max(image.size) > 2048:
        factor = 2048/max(image.size)
        image.scale(max(1,round(image.size[0]*factor)), max(1,round(image.size[1]*factor)))

for r, report in zip(rooms, reports):
    scene = bpy.data.scenes[r['scene']]
    activate(scene)
    dest = args.output/r['name']; dest.mkdir(exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    selected=[]
    for obj in scene.objects:
        if exclude(obj) or obj.type == 'LIGHT': continue
        if obj.type == 'CAMERA' and obj.name not in r['cameras'].values(): continue
        obj.hide_set(False); obj.hide_viewport=False; obj.select_set(True); selected.append(obj.name)
    bpy.ops.wm.usd_export(filepath=str(dest/(r['resource']+'.usdc')),
        selected_objects_only=True, export_animation=False, export_materials=True,
        export_uvmaps=True, export_normals=True, generate_preview_surface=True,
        export_textures_mode='NEW', relative_paths=True, export_lights=False,
        export_cameras=True, use_instancing=False, root_prim_path='/'+r['resource'],
        convert_scene_units='METERS', meters_per_unit=1.0)
    report['exportedObjects']=len(selected)
    (dest/'room-report.json').write_text(json.dumps(report,indent=2))
    print('ROOM_EXPORTED',r['name'],flush=True)
    # Low resolution indirect illumination capture, with authored scene lighting.
    oldcam=scene.camera
    data=bpy.data.cameras.new('FinalReflectionCapture'); data.type='PANO'; data.panorama_type='EQUIRECTANGULAR'
    camera=bpy.data.objects.new('FinalReflectionCapture',data); scene.collection.objects.link(camera)
    camera.location=(0,3,3); camera.rotation_euler=(math.pi/2,0,0); scene.camera=camera
    scene.render.engine='CYCLES'; scene.cycles.samples=8; scene.cycles.use_denoising=True
    scene.render.resolution_x=512; scene.render.resolution_y=256; scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='HDR'; scene.render.filepath=str(dest/'environment.hdr')
    bpy.ops.render.render(write_still=True)
    scene.camera=oldcam; bpy.data.objects.remove(camera,do_unlink=True)
    print('ROOM_DONE',r['name'],flush=True)

# Editable per-floor derivatives, explicitly retaining all floor scenes.
for floor in sorted({r['floor'] for r in rooms}):
    scenes={bpy.data.scenes[r['scene']] for r in rooms if r['floor']==floor}
    bpy.data.libraries.write(str(args.output/f'Floor{floor:02d}_Final.blend'),scenes,
        path_remap='ABSOLUTE',fake_user=True,compress=True)
(args.output/'room-report.json').write_text(json.dumps(reports,indent=2))
print('FINAL_EXPORT_COMPLETE',flush=True)
