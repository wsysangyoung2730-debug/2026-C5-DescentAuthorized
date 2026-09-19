import bpy,runpy,json,itertools,os
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
OUT=Path(__file__).parent;F=runpy.run_path(str(OUT/'build_floor5_v039.py'))
s=bpy.data.scenes[F['SCENES']['F05A']];bpy.context.window.scene=s;s.frame_set(1);bpy.context.view_layer.update()
baseline=json.loads((OUT/'floor5_v041_unchanged_baseline.json').read_text())
checks={'other_scenes_including_boss_unchanged':all(F['fingerprint'](bpy.data.scenes[n])==v for n,v in baseline.items()),'residue_stage_removed':not any('CombatStage' in o.name or 'ArenaCircuit' in o.name for o in s.objects),'boss_stage_retained':bpy.data.objects.get('F05B_CombatStage') is not None,'reward_scrolls_absent':not any('RewardScroll' in o.name for sn in F['SCENES'].values() for o in bpy.data.scenes[sn].objects)}
roots=[o for o in s.objects if o.get('source_asset')];bs={o.name:F['bounds'](o) for o in roots};overlaps=[]
for a,b in itertools.combinations(roots,2):
    if not(a.get('residue_revision') or b.get('residue_revision')):continue
    lo,hi=bs[a.name];bl,bh=bs[b.name]
    if min(min(hi[i],bh[i])-max(lo[i],bl[i]) for i in range(3))>.08:overlaps.append([a.name,b.name])
checks['new_props_do_not_overlap']=not overlaps
checks['central_floor_clear']=all(not(lo.x<2.5 and hi.x>-2.5 and lo.y<7.5 and hi.y>1) for o in roots if o.get('residue_revision') for lo,hi in [bs[o.name]])
cam=s.objects['F05A_iPad_MainCamera'];origin=cam.matrix_world.translation
spawn=s.objects['SPAWN_MemoryOmissionResidue'].location.copy();target=spawn+Vector((0,0,1))
pr=world_to_camera_view(s,cam,target);checks['spawn_in_combat_view']=pr.z>0 and 0<pr.x<1 and 0<pr.y<1
hit,loc,normal,index,obj,mat=s.ray_cast(bpy.context.evaluated_depsgraph_get(),origin,(target-origin).normalized(),distance=(target-origin).length-.03)
checks['spawn_sightline_clear']=not hit
missing=[i.name for i in bpy.data.images if i.users and i.source=='FILE' and not i.packed_file and not os.path.exists(bpy.path.abspath(i.filepath))]
checks['all_textures_available']=not missing
report={'checks':checks,'overlaps':overlaps,'ray_hit':obj.name if hit else None,'spawn':list(spawn),'missing_textures':missing,'added_bounds':{o.name:[list(v) for v in bs[o.name]] for o in roots if o.get('residue_revision')}}
(OUT/'AUDIT_floor5_v041.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
assert all(checks.values()),report
s.camera=s.objects['F05A_Overview']
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.overlay.show_overlays=False
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'DA_F05_F06_F07_F08_F09_F10_Combined_v041_residue_archive.blend'))
bpy.data.libraries.write(str(OUT/'DA_F05_TwoRooms_v041.blend'),{bpy.data.scenes[n] for n in F['SCENES'].values()},fake_user=True)
print(json.dumps(report,ensure_ascii=False))
