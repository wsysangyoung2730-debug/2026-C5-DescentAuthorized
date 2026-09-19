import bpy,runpy,json,math
from pathlib import Path
OUT=Path(__file__).parent;F=runpy.run_path(str(OUT/'build_floor5_v039.py'))
p='F05A';s=bpy.data.scenes[F['SCENES'][p]];bpy.context.window.scene=s;s.frame_set(1)
assert bpy.data.objects.get('F05A_CombatStage')
baseline={sc.name:F['fingerprint'](sc) for sc in bpy.data.scenes if sc!=s}
(OUT/'floor5_v041_unchanged_baseline.json').write_text(json.dumps(baseline,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'DA_pre_v041_live_checkpoint.blend'),copy=True)
root=s.objects['F05A_CombatStage'];removed=[o.name for o in [root]+list(root.children_recursive)]
for o in reversed([root]+list(root.children_recursive)):bpy.data.objects.remove(o,do_unlink=True)
for o in list(s.objects):
    if o.name.startswith('F05A_ArenaCircuit'):
        removed.append(o.name);bpy.data.objects.remove(o,do_unlink=True)
s.objects['SPAWN_MemoryOmissionResidue'].location.z=.03

def add(key,label,loc,size,axis='z',angle=0):
    o=F['imported'](p,'floor5-'+key,p+'_ArchiveWork_'+label,loc,size,axis,math.radians(angle))
    # Do not inherit bookkeeping properties from a shared mesh prototype.
    for key in ['side_dressing','revision']:
        if key in o:del o[key]
    o['residue_revision']='v041'
    for obj in [o]+list(o.children_recursive):
        for c in list(obj.users_collection):c.objects.unlink(obj)
        F['collection'](p,'ArchiveWork_v041').objects.link(obj)
    return o

def top(key,label,base,width):
    lo,hi=F['bounds'](base)
    return add(key,label,((lo.x+hi.x)/2,(lo.y+hi.y)/2,hi.z+.025),width,'x')
add('handwriting-comparison-desk','CollationDesk',(0,10.4,0),1.75)
c=add('sealed-memory-casket','LeftCase',(-3.65,7.75,0),1.95,'x',15)
top('porcelain-mask-shard-set','MaskFragments',c,.84)
c=add('memory-scroll-cylinder-crate','RightCase',(3.8,8.55,0),1.7,'x',-18)
top('missing-name-tag-set','UnclaimedTags',c,.62)
s['layout_version']='v041';s['residue_layout']='Flat combat floor; low archival workstations frame an unobstructed residue spawn area. No boss stage.'
s.camera=s.objects['F05A_Overview'];bpy.context.view_layer.update()
(OUT/'CHANGE_floor5_v041.json').write_text(json.dumps({'removed':removed,'added':[o.name for o in s.objects if o.get('residue_revision')],'spawn_height':.03},indent=2))
print('Removed stage and three arena rings. Added five low archival props; lowered residue spawn to floor.')
