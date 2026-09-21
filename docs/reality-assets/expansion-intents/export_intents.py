import bpy, json
from pathlib import Path
names=['MemoryRecord','MimicAttack','OpeningWait','ScheduledExecution','SpellSeal','Amplify','DamageReservation']
out=Path('/tmp/c5-136-intents-source')
report=[]
for name in names:
    scene=bpy.data.scenes.new('Export_'+name)
    source=bpy.data.collections['EXPORT_Intent'+name]
    scene.collection.children.link(source)
    bpy.context.window.scene=scene
    for obj in scene.objects:
        obj.hide_set(False)
        obj.hide_viewport=False
        obj.hide_render=False
    scene.frame_set(1)
    folder=out/('Intent'+name)
    folder.mkdir(parents=True,exist_ok=True)
    snake=''.join('_'+c.lower() if c.isupper() else c for c in name).lstrip('_')
    target=folder/('intent_'+snake+'.usdc')
    bpy.ops.wm.usd_export(filepath=str(target),selected_objects_only=False,export_animation=False,export_materials=True,export_textures_mode='NEW',export_uvmaps=True,export_normals=True,generate_preview_surface=True,convert_scene_units='METERS',meters_per_unit=1.0,relative_paths=True)
    report.append({'asset':'intent_'+snake,'collection':source.name,'objects':[o.name for o in source.all_objects]})
(out/'export-report.json').write_text(json.dumps({'source':bpy.data.filepath,'assets':report},ensure_ascii=False,indent=2))
print('EXPORTED',len(report))
