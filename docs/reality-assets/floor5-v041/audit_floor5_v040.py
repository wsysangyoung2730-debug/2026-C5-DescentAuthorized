import bpy,runpy,json,os,math
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
OUT=Path(__file__).parent;F=runpy.run_path(str(OUT/'build_floor5_v039.py'))
report={'version':'v040','rooms':{},'asset_usage':{},'checks':{},'camera_checks':{}}
baseline=json.loads((OUT/'floor5_original_scene_fingerprints.json').read_text())
report['checks']['prior_scene_transforms_preserved']=all(F['fingerprint'](bpy.data.scenes[n])==v for n,v in baseline.items())
for p,sn in F['SCENES'].items():
    s=bpy.data.scenes[sn];bpy.context.window.scene=s;s.frame_set(66 if p.endswith('B') else 1);bpy.context.view_layer.update()
    meshes=[o for o in s.objects if o.type=='MESH'];imgs=set()
    for o in meshes:
        for m in o.data.materials:
            if m and m.use_nodes:
                imgs.update(n.image for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
    missing=[i.name for i in imgs if not i.packed_file and not os.path.exists(bpy.path.abspath(i.filepath))]
    usage=[o for o in s.objects if o.get('source_asset')]
    for o in usage:report['asset_usage'].setdefault(o['source_asset'],[]).append([sn,o.name])
    report['rooms'][p]={'scene':sn,'objects':len(s.objects),'mesh_objects':len(meshes),'triangles':sum(sum(len(poly.vertices)-2 for poly in o.data.polygons) for o in meshes),'source_asset_placements':len(usage),'texture_count':len(imgs),'missing_textures':missing,'cameras':[o.name for o in s.objects if o.type=='CAMERA'],'decorative_doors':[o.name for o in usage if o.get('purpose')=='wall_decoration']}
    assert not missing,missing
    for o in usage:
        assert not o.hide_render and not o.hide_viewport,o.name
    camera_roots={p+'_Overview':[p+'_CombatStage',p+'_MagicInputBoard']}
    if p.endswith('B'):
        camera_roots['CAM_F05_RewardSelection']=['F05B_RewardSelection']
        camera_roots['CAM_F05_DescentDoor']=['F05B_DescentStele','F05B_DescentInputPedestal','F05B_DescentPlatform']
        camera_roots[p+'_Overview']+=['F05B_RewardSelection','F05B_DescentStele','F05B_DescentPlatform']
        scrolls=[o for o in s.objects if 'RewardScroll' in o.name]
        report['checks']['reward_scroll_models_removed']=len(scrolls)==0
        slots=[o for o in s.objects if o.name.startswith('ANCHOR_F05_RewardSlot_')]
        report['checks']['three_empty_future_reward_anchors']=len(slots)==3 and all(o.type=='EMPTY' and not o.animation_data for o in slots)
        report['reward_scroll_objects']=[o.name for o in scrolls]
    for cn,roots in camera_roots.items():
        cam=s.objects[cn];row={}
        for name in roots:
            pts=F['allpts'](bpy.data.objects[name]);pr=[world_to_camera_view(s,cam,v) for v in pts]
            lo=[min(v[i] for v in pr) for i in range(3)];hi=[max(v[i] for v in pr) for i in range(3)]
            row[name]={'min':lo,'max':hi,'in_frame':lo[2]>0 and lo[0]>=0 and lo[1]>=0 and hi[0]<=1 and hi[1]<=1}
        report['camera_checks'][cn]=row
    # Eye rays to points across gameplay targets, reporting intervening decorative props.
    if p.endswith('B'):
        report['sightline_obstructions']={}
        dg=bpy.context.evaluated_depsgraph_get()
        for cn,names in [('CAM_F05_RewardSelection',['F05B_RewardSelection']),('CAM_F05_DescentDoor',['F05B_DescentStele','F05B_DescentPlatform','F05B_DescentInputPedestal'])]:
            cam=s.objects[cn]
            for name in names:
                root=s.objects[name];lo,hi=F['bounds'](root)
                targets=[(lo+hi)/2,Vector(((lo.x+hi.x)/2,lo.y+.02,lo.z+(hi.z-lo.z)*.3)),Vector(((lo.x+hi.x)/2,lo.y+.02,lo.z+(hi.z-lo.z)*.7))]
                hits=[]
                for t in targets:
                    delta=t-cam.location;hit,loc,normal,idx,obj,matrix=s.ray_cast(dg,cam.location,delta.normalized(),distance=delta.length-.02)
                    if hit:
                        parent=obj
                        while parent and not parent.get('source_asset'):parent=parent.parent
                        if parent and parent!=root:hits.append(parent.name)
                report['sightline_obstructions'][cn+'/'+name]=sorted(set(hits))
    s.camera=s.objects[p+'_Overview']
expected={k[:-4] for k in F['PATHS'] if k.startswith('floor5-')}
report['checks']['all_20_floor5_assets_used']=expected<=set(report['asset_usage']) and len(expected)==20
report['checks']['interaction_targets_in_frame']=all(row['in_frame'] for cam in report['camera_checks'].values() for row in cam.values())
report['checks']['no_decorative_prop_blocks_interaction_rays']=not any(report.get('sightline_obstructions',{}).values())
(OUT/'AUDIT_floor5_v040.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({'checks':report['checks'],'obstructions':report.get('sightline_obstructions'),'counts':{p:r['triangles'] for p,r in report['rooms'].items()}},ensure_ascii=False))
