"""All-floor side-view coverage; reuse supplied GLBs and clear interaction views.
Apply once to v035. v035 remains a rollback checkpoint.
"""
import bpy,math,runpy,json,unicodedata
from pathlib import Path
from mathutils import Vector,Matrix
OUT=Path(bpy.data.filepath).parent
R=runpy.run_path(str(OUT/'redesign_f06_f07_v035.py'),run_name='helpers')
R['SCENES'].update({'F08A':'DA_F08A_ResidueIsolation','F08B':'DA_F08_AdministratorObservatory','F09':'DA_F09_Archive_Redesign','F10':'DA_F10_ClosedOffice'})
root=next(p for p in Path('/Users/sangyoung/Desktop').glob('C5*/*/5.*') if '🔥' in str(p))
files=list(root.rglob('*.glb'))
norm=lambda x:unicodedata.normalize('NFC',str(x))

def source_file(name):return next(p for p in files if norm(p.name)==name)
def import_asset(p,file,name,loc,size,rz=0):
    s=bpy.data.scenes[R['SCENES'][p]];bpy.context.window.scene=s
    before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(file))
    obs=set(bpy.data.objects)-before
    roots=[o for o in obs if o.parent not in obs]
    points=[o.matrix_world@Vector(v) for o in obs if o.type=='MESH' for v in o.bound_box]
    lo=Vector([min(v[i] for v in points) for i in range(3)]);hi=Vector([max(v[i] for v in points) for i in range(3)])
    center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));factor=size/max(hi-lo)
    c=R['coll'](p,'SideProps');wrapper=bpy.data.objects.new(name,None);c.objects.link(wrapper)
    for o in obs:
        for oldc in list(o.users_collection):oldc.objects.unlink(o)
        c.objects.link(o)
    for o in roots:
        world=o.matrix_world.copy();o.parent=wrapper;o.matrix_world=Matrix.Translation(-center)@world
    wrapper.location=loc;wrapper.scale=(factor,)*3;wrapper.rotation_euler.z=rz;wrapper['source_glb']=str(file)
    bpy.context.view_layer.update();return wrapper

def dup(src,p,name,loc,size=None,rz=None):
    return R['duplicate'](bpy.data.objects[src],p,name,loc,size,rz)

# Previously unused supplied props, placed as visible set dressing.
R['move']('floor6-pendulum-calibration-rack',(-10,-1.8,0),3.4,math.pi/2)
import_asset('F06A',source_file('floor6-causality-archive-gate.glb'),'F06A_ArchiveVault',(-5.5,11,0),4.45)
import_asset('F06A',source_file('floor6-sequence-seal-tag-set.glb'),'F06A_SequenceSealTools',(-7.2,-1.4,1.39),.9)
gate=bpy.data.objects.new('F07A_SealedCalibrationGate',None)
gate.instance_type='COLLECTION';gate.instance_collection=bpy.data.collections['F07_ASSET_two-stage-descent-gate']
R['coll']('F07A','SideProps').objects.link(gate);gate.location=(10.1,0,0);gate.scale=(4.3,)*3;gate.rotation_euler.z=-math.pi/2
gate['source_glb']=str(source_file('floor7-two-stage-descent-gate.glb'));gate['role']='sealed calibration service bay, decorative'
import_asset('F08B',source_file('8층_대형 다중 관측 링 2.glb'),'F08B_ForwardObservationRing',(0,-5,7.1),4.8)
import_asset('F08B',source_file('8층_천장 지지 프레임.glb'),'F08B_ForwardSuspensionFrame',(0,-5,8.65),6.2)

# Side equipment near the player's yaw pivot, with clear central combat lanes.
for p in ['F06A','F06B']:
    for sign in [-1,1]:
        src='floor6-clockwork-evidence-cabinet' if sign<0 else 'floor6-event-spool-cabinet'
        dup(src,p,p+'_SideArchive_'+str(sign),(sign*(9.5 if p.endswith('A') else 10.5),-5.8,0),3.4,sign*-math.pi/2)
    if p.endswith('B'):
        dup('floor6-timeline-strip-table',p,p+'_SideTimeline',(-10,0,0),3,math.pi/2)
        dup('floor6-event-capsule-transport-crate',p,p+'_SideCapsules',(10,-1.5,0),1.8,-math.pi/2)
        dup('floor6-split-time-monitor-cluster',p,p+'_SideMonitor',(11.3,3,2.8),2.3,-math.pi/2)

for p in ['F07A','F07B']:
    for sign in [-1,1]:
        dup('F07A_LogCabinet',p,p+'_SideLogCabinet_'+str(sign),(sign*9.7,-7.6 if p.endswith('B') else -5.7,0),2.25 if p.endswith('B') else 3.2,sign*-math.pi/2)
    if p.endswith('B'):
        dup('F07A_SurveyRack',p,p+'_SideSurveyRack',(-10.4,-.3,0),3.1,math.pi/2)
        dup('F07A_ProjectorBench',p,p+'_SideProjector',(10.4,2,0),2.5,-math.pi/2)
        dup('F07A_SampleCrate',p,p+'_SideSampleCrate',(-10.4,4,0),2.2,math.pi/2)
        dup('F07A_CableSpool',p,p+'_SideCableCart',(10.4,6.3,0),1.9,-math.pi/2)

dup('F08A_EquipmentCabinet','F08A','F08A_ForwardEquipmentCabinet',(-7.5,-5.9,0),None,math.pi/2)
dup('IsolationMonitor','F08A','F08A_SideMonitor',(8.65,-4.5,3.2),None,-math.pi/2)
dup('MonitorWall_L','F08B','F08B_LeftSideMonitor',(-11,-3.5,3.4),None,math.pi/2)
dup('MonitorWall_R','F08B','F08B_RightSideMonitor',(11,-3.5,3.4),None,-math.pi/2)
dup('NarrowAuxShelf','F09','F09_ForwardLeftShelf',(-10.6,-8.2,0),None,math.pi/2)
dup('SmallWallMonitor','F09','F09_ForwardRightMonitor',(10.8,-6.5,2.5),None,-math.pi/2)
dup('BrokenMonitor_R','F10','F10_ForwardRightMonitor',(10.9,-6.5,2.5),None,-math.pi/2)

# Three descent objects form one unobstructed bay, as on the established floors.
for p in ['F06B','F07B']:
    floor=p[:3]
    if p=='F07B':
        R['move']('F07B_DescentDoor',(8.35,16.2,0),5.5,0)
        R['move']('F07B_CalibrationGantry',(-4.9,16.1,0),5,0)
        R['move']('F07B_CalibrationGantry_Right',(4.9,16.1,0),5,0)
        # End galleries before the interaction bay; upper door remains visible.
        for o in R['coll'](p).objects:
            if any(k in o.name for k in ['GalleryDeck','GalleryFascia','GalleryHandrail','GalleryMidRail']):
                o.location.y=3.2;o.dimensions.y=12.4
            if any(k in o.name for k in ['GalleryRailPost','GallerySupport','GalleryBrace','GalleryCollar','MastBase']) and o.location.y>9.5:
                o.hide_render=True;o.hide_viewport=True
    else:
        R['move']('floor6-two-stage-descent-gate',(8.15,14.8,0),5.4,0)
        R['move']('floor6-verdict-seal-press',(10.8,5.4,0),2.5,-math.pi/2)
        R['move']('floor6-sequence-verification-console.001',(10.6,1.7,0),2.4,-math.pi/2)
        R['move']('floor6-dual-clock-causality-pillar.001',(4.6,13,0),5.4,-.08)
    x=8.35 if p=='F07B' else 8.15
    R['move'](p+'_DescentStele',(x,12.8,0),2.7,0)
    R['move'](p+'_DescentPedestal',(x,10.55,0),2.7,math.pi/2)
    cam=bpy.data.objects['CAM_'+floor+'_DescentDoor'];cam.location=(x,6.3,2.1);cam.data=cam.data.copy();cam.data.lens=22
    cam.rotation_euler=(Vector((x,13.5,2.05))-cam.location).to_track_quat('-Z','Y').to_euler()
    R['move']('anchor_'+floor+'_descent_interaction',(x,8.9,0))
    cam=bpy.data.objects['CAM_'+floor+'_RewardSelection'];cam.data=cam.data.copy();cam.data.lens=28
    cam.rotation_euler=(Vector((-7.2,2.3,1.35))-cam.location).to_track_quat('-Z','Y').to_euler()

# Existing 8F side machinery was intruding into reward / descent sightlines.
R['move']('PrismRack_R',(-10,0,0))
R['move']('TripodLens_R',(-5.9,6.8,0))
R['move']('DataPillar_0',(-10.1,15.9,0))
R['move']('DataPillar_1',(10.5,7,0))

# Persist source provenance for linked 7F collection instances.
for s in bpy.data.scenes:
    if s.name.startswith('DA_F07'):
        for o in s.objects:
            if o.instance_collection and o.instance_collection.name.startswith('F07_ASSET_'):
                slug=o.instance_collection.name.replace('F07_ASSET_','')
                f=next((p for p in files if p.stem.replace('(1500)','')=='floor7-'+slug),None)
                if f:o['source_glb']=str(f)

# Side inspection cameras use the real gameplay pivot and a +/- 70 degree yaw.
for p,sn in R['SCENES'].items():
    s=bpy.data.scenes[sn]
    main=next((o for o in s.objects if o.type=='CAMERA' and ('iPad_MainCamera' in o.name or 'iPadCamera' in o.name)),s.camera)
    for sign,label in [(-1,'Left'),(1,'Right')]:
        d=bpy.data.cameras.new(p+'_SideCheck_'+label);d.lens=22
        o=bpy.data.objects.new(d.name,d);R['coll'](p,'ReviewCameras').objects.link(o);o.location=main.matrix_world.translation
        direction=Vector((sign*math.sin(math.radians(70)),math.cos(math.radians(70)),-.015))
        o.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()
    s['side_coverage_revision']='v036';s['interaction_view_clearance_required']=True
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'DA_F06_F07_F08_F09_F10_Combined_v036_side_coverage.blend'))
print('Side coverage, missing assets, and interaction bays saved')
