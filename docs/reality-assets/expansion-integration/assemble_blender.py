"""Create a reviewable Blender integration copy; source and actor library stay untouched."""
import bpy, argparse, sys, json
from pathlib import Path
from mathutils import Matrix

p = argparse.ArgumentParser()
p.add_argument('--actors', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
rooms = [
    (7, False, 'CoordinateResidue', 'DA_F07A_CoordinateResidue'),
    (7, True, 'CoordinateAdministrator', 'DA_F07_CoordinateAdministrator'),
    (6, False, 'CausalityResidue', 'DA_F06A_ResultDelayResidue'),
    (6, True, 'CausalityAdministrator', 'DA_F06B_CausalityAdministrator'),
    (5, False, 'MemoryOmissionResidue', 'DA_F05A_MemoryOmissionResidue'),
    (5, True, 'OriginalMemoryAdministrator', 'DA_F05B_OriginalMemoryAdministrator'),
]
names = {v for _, _, n, _ in rooms for v in ('ACTOR_' + n, n + '_Skin')}
with bpy.data.libraries.load(str(a.actors), link=False) as (source, destination):
    destination.objects = [n for n in source.objects if n in names]
objects = {o.name: o for o in destination.objects}
report = []
for floor, boss, name, scene_name in rooms:
    scene = bpy.data.scenes[scene_name]
    bpy.context.window.scene = scene
    scene.frame_set(1)
    spawn = scene.objects['SPAWN_' + name]
    collection = bpy.data.collections.new('RuntimePreview_' + name)
    scene.collection.children.link(collection)
    rig, mesh = objects['ACTOR_' + name], objects[name + '_Skin']
    collection.objects.link(rig)
    collection.objects.link(mesh)
    rig['runtime_actor_preview'] = True
    rig['runtime_asset'] = 'Reality/Actors/' + name
    rig.parent = spawn
    rig.matrix_parent_inverse = Matrix.Identity(4)
    scale = (4.2 if boss else 2.8) / 3
    rig.matrix_basis = Matrix.Diagonal((scale, scale, scale, 1))
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = int(rig.animation_data.action.frame_range[1])
    manifest = json.loads((a.actors.parent / name / 'motion.json').read_text())
    for clip, interval in manifest['clips'].items():
        scene.timeline_markers.new('ACTOR_' + clip, frame=round(interval['start'] * 30) + 1)
    if boss:
        for slot in ('Left', 'Center', 'Right'):
            anchor_name = f'ANCHOR_F0{floor}_RewardSlot_{slot}'
            if anchor_name not in scene.objects:
                idle = next(o for o in scene.objects if o.name.endswith(f'RewardScroll_{slot}_Idle'))
                anchor = bpy.data.objects.new(anchor_name, None)
                scene.collection.objects.link(anchor)
                anchor.matrix_world = idle.matrix_world.copy()
                anchor.rotation_euler = (0, 0, 0)
                anchor.scale = (1, 1, 1)
        for obj in list(scene.objects):
            if 'RewardScroll_' in obj.name:
                bpy.data.objects.remove(obj, do_unlink=True)
    report.append({'scene': scene_name, 'actor': rig.name, 'spawn': spawn.name,
                   'targetHeight': 4.2 if boss else 2.8})
for scene in bpy.data.scenes:
    scene.use_fake_user = True
bpy.context.window.scene = bpy.data.scenes['DA_F05B_OriginalMemoryAdministrator']
bpy.ops.file.pack_all()
a.output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(a.output))
a.output.with_suffix('.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print('BLENDER_INTEGRATION_SAVED', str(a.output), flush=True)
