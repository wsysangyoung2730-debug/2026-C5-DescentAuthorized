"""Add only encounter cameras/targets to current v067; save as a new v068.
Run Blender --background SOURCE --python this_file -- --output OUTPUT --evidence DIR.
"""
import argparse, hashlib, json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent
NAMES = {9:'DA_F09_Archive_Redesign',8:'DA_F08_AdministratorObservatory',7:'DA_F07_CoordinateAdministrator',6:'DA_F06B_CausalityAdministrator',5:'DA_F05B_OriginalMemoryAdministrator',4:'DA_F04_ResponsibilityAdministrator',3:'DA_F03_VoluntaryIsolationAdministrator',2:'DA_F02_SealHeartAdministrator',1:'DA_F01_FinalApproval'}
# Explicit, reviewed camera positions and object-relative aim offsets. No mesh modification.
SHOTS = {
9:[((-4.8,-3.5,2.9),'LongDrawer_L',(1.9,2.35,2.7)),((0,-7.2,3.5),'BossStage',(0,0,2.8)),((4.8,-2.6,2.9),'BrokenGlassCabinet_R',(-1.6,0,2.7))],
8:[((-4.4,-1.8,3.0),'TripodLens_L',(0,0,2.5)),((0,-6.8,3.8),'PrimaryObservationGate',(0,0,4)),((4.3,2.6,3.4),'MonitorWall_R',(2.5,-4,0))],
7:[((-3.7,0.2,2.9),'F07B_PhasePrism',(0,0,2.6)),((0,-6.5,3.7),'F07B_ReferenceAxisGate',(0,0,4)),((3.7,0.2,2.9),'F07B_PhasePrism.001',(0,0,2.6))],
6:[((-4.8,-0.3,3.0),'floor6-split-time-monitor-cluster',(1,0,2.8)),((0,-6.5,3.8),'floor6-cause-effect-chain-loom',(0,0,4)),((4.8,-0.5,3.0),'floor6-sequence-verification-console.001',(-1,2.5,2.6))],
5:[((-5.4,-2.7,3.0),'F05B_IdentityConsole',(0,0,2.6)),((0,-6.5,3.7),'F05B_DonorChair',(0,0,3.6)),((5.2,-3.2,3.0),'F05B_MemoryCasket',(0,0,2.5))],
4:[((-7,-3,3.5),'F04C_v058_EvidenceAllocation_P08',(1.8,3.7,2.8)),((0,-5.8,5.6),'F04C_P13_01',(0,0,3)),((8,-2.6,3.4),'F04C_v058_RightRegistry1_P14',(-2.9,2.1,2.96))],
3:[((-5.3,0,3.4),'F03C_BoundaryWing_Open',(.8,0,3.1)),((0,-7,4.3),'F03C_ConsentLockHub',(0,0,3)),((5.3,.1,3.4),'F03C_BoundaryWing_Open.001',(-.6,0,3.1))],
2:[((-5.8,.2,3.2),'F02C_P52',(1.1,1.1,3)),((0,-7.6,4.4),'F02C_SealMaintenanceHeart',(0,0,4)),((6.8,-.5,3.2),'F02C_P53.001',(1.3,-2,2.5))],
1:[((-10,2,3.6),'F01C_IdentityAuthorityPillar',(3,0,3.5)),((0,-12,5),'F01C_CrownApprovalNexus',(0,0,4)),((7.5,-6,3.4),'F01C_HandoverAuthorityPillar',(-1,0,3))],
}
INTERIOR_RETURN={1:(0,-15,4.8),2:(0,-8.4,4.8),3:(0,-7.5,4.2)}
SPAWNS={9:'SPAWN_RecordAdministrator',8:'SPAWN_ObservationAdministrator',7:'SPAWN_CoordinateAdministrator',6:'SPAWN_CausalityAdministrator',5:'SPAWN_OriginalMemoryAdministrator',4:'SPAWN_ResponsibilityAdministrator',3:'F03C_EnemySpawn',2:'F02C_EnemySpawn',1:'F01C_EnemySpawn'}
FRAMES=[1,103,217,337]

def signature(values=False):
    # Original datablock transforms/topology/material references, independent of camera additions.
    d={}
    for o in bpy.data.objects:
        if o.name.startswith(('CAM_F','TARGET_F')) and o.get('encounter_sweep_version'):continue
        d[o.name]={'type':o.type,'location':list(o.location),'rotation':list(o.rotation_euler),'scale':list(o.scale),'parent':o.parent.name if o.parent else None,'data':o.data.name if o.data else None,'hidden':o.hide_render,'collections':sorted(set(c.name for c in o.users_collection))}
        if o.type=='MESH':d[o.name].update(vertices=len(o.data.vertices),polygons=len(o.data.polygons),materials=[m.name if m else None for m in o.data.materials])
        if o.type=='CAMERA':d[o.name].update(lens=o.data.lens,shift=[o.data.shift_x,o.data.shift_y],clip=[o.data.clip_start,o.data.clip_end])
    return d if values else hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest()

def quat(p,t):return (Vector(t)-Vector(p)).to_track_quat('-Z','Y')
def rounded(v):return [round(float(a),6) for a in v]
def enum_set(owner,prop,wanted):
    values=[e.identifier for e in owner.bl_rna.properties[prop].enum_items]
    if wanted not in values:raise RuntimeError((prop,wanted,values))
    setattr(owner,prop,wanted)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True);parser.add_argument('--evidence',required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);out=Path(args.output).resolve();ev=Path(args.evidence).resolve();ev.mkdir(parents=True,exist_ok=True)
    assert not out.exists(),'Refuse overwrite; choose a fresh output.'
    source=Path(bpy.data.filepath);source_hash=hashlib.file_digest(source.open('rb'),'sha256').hexdigest();before=signature();before_values=signature(values=True)
    manifest={'source':str(source),'source_sha256':source_hash,'source_bytes':source.stat().st_size,'output':str(out),'blender_version':bpy.app.version_string,'fps':30,'duration_seconds':12,'coordinates':'meters, Z-up; quaternion WXYZ','rooms':[]}
    original_scene=bpy.context.window.scene
    for floor,name in NAMES.items():
        scene=bpy.data.scenes[name];bpy.context.window.scene=scene;bpy.context.view_layer.update()
        main_name=f'F{floor:02d}C_MainCamera' if floor<=3 else f'F{floor:02d}_iPad_MainCamera';main_cam=scene.objects[main_name]
        collection=bpy.data.collections.new(f'F{floor:02d}_EncounterCameras_v068');scene.collection.children.link(collection)
        collection['purpose']='Object-anchored encounter room reveal; cameras/targets only'
        poses=[]
        for idx,(pos,anchor_name,offset) in enumerate(SHOTS[floor]):
            anchor=scene.objects[anchor_name];aim=anchor.matrix_world.translation+Vector(offset)
            poses.append((Vector(pos),quat(pos,aim),24.0,anchor_name,Vector(offset),aim))
        if floor in INTERIOR_RETURN:
            anchor=scene.objects[SPAWNS[floor]];aim=anchor.matrix_world.translation+Vector((0,0,2));pos=Vector(INTERIOR_RETURN[floor])
            poses.append((pos,quat(pos,aim),28.0,anchor.name,Vector((0,0,2)),aim))
        else:
            pos=main_cam.matrix_world.translation.copy();q=main_cam.matrix_world.to_quaternion();aim=pos+q@Vector((0,0,-15));anchor=scene.objects[SPAWNS[floor]]
            poses.append((pos,q,main_cam.data.lens,anchor.name,aim-anchor.matrix_world.translation,aim))
        room={'floor':floor,'scene':name,'collection':collection.name,'existing_main_camera':main_name,'original_active_camera':scene.camera.name if scene.camera else None,'return_uses_interior_pose':floor in INTERIOR_RETURN,'render_settings':{'resolution_x':scene.render.resolution_x,'resolution_y':scene.render.resolution_y,'pixel_aspect_x':scene.render.pixel_aspect_x,'pixel_aspect_y':scene.render.pixel_aspect_y},'poses':[],'samples':[]}
        for i,(label,pose) in enumerate(zip(['Left','Wide','Right','Return'],poses)):
            pos,q,lens,anchor,offset,aim=pose;prefix=f'F{floor:02d}_Encounter_{label}'
            target=bpy.data.objects.new('TARGET_'+prefix,None);collection.objects.link(target);target.location=aim;target.empty_display_size=.25;target['encounter_sweep_version']=68;target['source_object']=anchor;target['world_offset_from_source']=list(offset)
            data=main_cam.data.copy();data.name='CAM_'+prefix;data.lens=lens;data.shift_x=0;data.shift_y=0;data.clip_start=.08;data.clip_end=max(main_cam.data.clip_end,150)
            if label=='Return' and floor not in INTERIOR_RETURN:data.shift_x=main_cam.data.shift_x;data.shift_y=main_cam.data.shift_y
            data.dof.use_dof=False
            camera=bpy.data.objects.new('CAM_'+prefix,data);collection.objects.link(camera);camera.location=pos;enum_set(camera,'rotation_mode','QUATERNION');camera.rotation_quaternion=q
            camera['encounter_sweep_version']=68;camera['source_object']=anchor;camera['target_object']=target.name;camera['time_seconds']=(FRAMES[i]-1)/30
            room['poses'].append({'name':camera.name,'frame':FRAMES[i],'position':rounded(pos),'quaternion_wxyz':rounded(q),'lens_mm':lens,'source_object':anchor,'target':rounded(aim),'target_offset':rounded(offset),'camera_settings':{k:getattr(data,k) for k in ['sensor_width','sensor_height','sensor_fit','shift_x','shift_y','clip_start','clip_end']}})
        data=main_cam.data.copy();data.name=f'CAM_F{floor:02d}_Encounter_Preview';data.clip_start=.08;data.clip_end=max(data.clip_end,150);data.dof.use_dof=False
        preview=bpy.data.objects.new(data.name,data);collection.objects.link(preview);enum_set(preview,'rotation_mode','QUATERNION');preview['encounter_sweep_version']=68;preview['preview_frames']='1-361 at 30fps';preview['runtime_connected']=False
        for frame in range(1,362):
            seg=next((i for i in range(3) if frame<=FRAMES[i+1]),2);u=max(0,min(1,(frame-FRAMES[seg])/(FRAMES[seg+1]-FRAMES[seg])));ease=u*u*u*(u*(u*6-15)+10)
            a,b=poses[seg],poses[seg+1];p=a[0].lerp(b[0],ease);q=a[1].slerp(b[1],ease);q=(q@Vector((0,0,-1))).to_track_quat('-Z','Y');lens=a[2]+(b[2]-a[2])*ease
            preview.location=p;preview.rotation_quaternion=q;data.lens=lens;data.shift_x=main_cam.data.shift_x*ease if seg==2 and floor not in INTERIOR_RETURN else 0;data.shift_y=main_cam.data.shift_y*ease if seg==2 and floor not in INTERIOR_RETURN else 0
            preview.keyframe_insert('location',frame=frame);preview.keyframe_insert('rotation_quaternion',frame=frame);data.keyframe_insert('lens',frame=frame);data.keyframe_insert('shift_x',frame=frame);data.keyframe_insert('shift_y',frame=frame)
            room['samples'].append({'frame':frame,'seconds':(frame-1)/30,'position':rounded(p),'quaternion_wxyz':rounded(q),'lens_mm':round(lens,6),'shift_x':data.shift_x,'shift_y':data.shift_y})
        room['preview_camera']=preview.name
        # Do not bind timeline markers or change original frame range, FPS, or active camera.
        preview_scene=scene.copy();preview_scene.use_fake_user=True;preview_scene.name=f'PREVIEW_F{floor:02d}_EncounterSweep';preview_scene.camera=preview;preview_scene.frame_start=1;preview_scene.frame_end=361;preview_scene.render.fps=30;preview_scene.frame_set(1)
        room['preview_scene']=preview_scene.name
        room['preview_instructions']='Open preview scene and play frames 1-361 at 30fps. Source geometry is linked; original scene settings retained.'
        manifest['rooms'].append(room)
    bpy.context.window.scene=bpy.data.scenes['PREVIEW_F09_EncounterSweep'];bpy.context.view_layer.update()
    after_values=signature(values=True)
    differences={k:{'before':v,'after':after_values.get(k)} for k,v in before_values.items() if v!=after_values.get(k)}
    Path('/tmp/c5-camera-original-differences.json').write_text(json.dumps(differences,indent=2))
    assert before==signature(),'Existing objects changed'
    manifest['original_object_signature']=before;manifest['added_cameras']=45;manifest['added_targets']=36
    out.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(out),check_existing=True)
    (ev/'camera-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
    print('CAMERA_AUTHORING_COMPLETE',out,flush=True)

if __name__=='__main__':main()
