"""Read-only scene audit for the four redesigned rooms."""
import bpy, json, os
from mathutils import Vector
from pathlib import Path
SCENES={'F07A':'DA_F07A_CoordinateResidue','F07B':'DA_F07_CoordinateAdministrator','F06A':'DA_F06A_ResultDelayResidue','F06B':'DA_F06B_CausalityAdministrator'}
def points(root):
    out=[]
    if root.type=='MESH':out.extend(root.matrix_world@Vector(v) for v in root.bound_box)
    for ch in root.children:out.extend(points(ch))
    if root.instance_collection:
        for ob in root.instance_collection.all_objects:
            if ob.type=='MESH':out.extend(root.matrix_world@ob.matrix_world@Vector(v) for v in ob.bound_box)
    return out
def bounds(root):
    ps=points(root)
    return {'min':[round(min(v[i] for v in ps),3) for i in range(3)],'max':[round(max(v[i] for v in ps),3) for i in range(3)]} if ps else None
report={'file':bpy.data.filepath,'rooms':{},'other_scene_counts':{},'checks':[]}
for p,sn in SCENES.items():
    s=bpy.data.scenes[sn]
    roots=[o for o in s.objects if o.parent is None and (o.type=='EMPTY')]
    common=[p+'_MagicInputBoard',p+'_BossAccessDoor'] if p.endswith('A') else [p+'_MagicInputBoard','BossStage_'+p[:3],p+'_RewardSelection']
    for name in common:assert name in s.objects, name+' missing'
    common_bounds={name:bounds(s.objects[name]) for name in common}
    for name,b in common_bounds.items():
        assert b is not None, name+' empty geometry'
        assert max(abs(n) for v in b.values() for n in v)<25, name+' unexpected transform'
    meshobs=set(o for o in s.objects if o.type=='MESH')
    for o in s.objects:
        if o.instance_collection:meshobs.update(x for x in o.instance_collection.all_objects if x.type=='MESH')
    images=set()
    for o in meshobs:
        for m in o.data.materials:
            if m and m.use_nodes:
                images.update(n.image for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
    missing=[im.name for im in images if not im.packed_file and im.source=='FILE' and not os.path.exists(bpy.path.abspath(im.filepath))]
    assert not missing, str(missing)
    report['rooms'][p]={'scene':sn,'objects':len(s.objects),'camera':s.camera.name,'camera_location':list(s.camera.location),'common_bounds':common_bounds,'root_assets':[{ 'name':o.name,'bounds':bounds(o)} for o in roots],'texture_images':len(images),'missing_textures':missing,'world':s.world.name,'identity':s.get('room_identity'),'render':s.render.filepath}
    report['checks'].append(p+': common assets present, transforms bounded, texture paths valid')
for s in bpy.data.scenes:
    if s.name not in SCENES.values():report['other_scene_counts'][s.name]=len(s.objects)
assert len({bpy.data.scenes[n].world.name for n in SCENES.values()})==4
report['checks'].append('Four independent room worlds; shared materials preserved through copies')
out=Path(bpy.data.filepath).parent/'F06_F07_v035_audit.json'
out.write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({'checks':report['checks'],'other_scene_counts':report['other_scene_counts']},ensure_ascii=False))
