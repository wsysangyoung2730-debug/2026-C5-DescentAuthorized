"""Apply approved room compositions to live v034. Existing GLBs are reused.
Run once per phase in Blender; all additions are scoped to four target scenes.
"""
import bpy, math, json
from mathutils import Vector
from pathlib import Path

SCENES = {'F07A':'DA_F07A_CoordinateResidue','F07B':'DA_F07_CoordinateAdministrator',
          'F06A':'DA_F06A_ResultDelayResidue','F06B':'DA_F06B_CausalityAdministrator'}
OUT = Path(bpy.data.filepath).parent

def coll(p, suffix='Redesign'):
    name=p+'_'+suffix
    c=bpy.data.collections.get(name)
    if c is None:
        c=bpy.data.collections.new(name);bpy.data.scenes[SCENES[p]].collection.children.link(c)
    return c

def mat(name, source, color=None, emission=0):
    m=bpy.data.materials.get(name)
    if m:return m
    m=bpy.data.materials[source].copy();m.name=name
    n=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    if color:
        for link in list(n.inputs['Base Color'].links):m.node_tree.links.remove(link)
        n.inputs['Base Color'].default_value=(*color,1);m.diffuse_color=(*color,1)
    if emission:
        n.inputs['Emission Color'].default_value=(*color,1)
        n.inputs['Emission Strength'].default_value=emission
    return m

def materials():
    return {
      'wall':mat('DA35_Concrete','F08B_WeatheredConcrete',(.19,.21,.22)),
      'warmwall':mat('DA35_ArchiveConcrete','F08B_WeatheredConcrete',(.22,.19,.16)),
      'iron':mat('DA35_StructuralIron','F08A_Oxidised_Brass',(.055,.068,.075)),
      'brass':mat('DA35_CalibrationBrass','F08A_Oxidised_Brass',(.33,.22,.09)),
      'teal':mat('DA35_TealPractical','F07_Coordinate_Cyan',(.09,.55,.61),2),
      'amber':mat('DA35_AmberPractical','F07_Coordinate_Cyan',(.85,.37,.08),2),
      'paper':mat('DA35_ArchivePaper','F08B_WeatheredConcrete',(.55,.44,.26)),
      'red':mat('DA35_SealRed','F08A_Oxidised_Brass',(.19,.022,.013))}

def box(p,name,loc,dim,material,rz=0):
    verts=[(x*dim[0]/2,y*dim[1]/2,z*dim[2]/2) for x,y,z in
           [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]]
    mesh=bpy.data.meshes.new(p+'_'+name);mesh.from_pydata(verts,[],[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)])
    mesh.materials.append(material)
    o=bpy.data.objects.new(p+'_'+name,mesh);coll(p).objects.link(o);o.location=loc;o.rotation_euler.z=rz
    return o

def beam(p,name,a,b,width,material):
    a,b=Vector(a),Vector(b)
    o=box(p,name,(a+b)/2,(width,width,(b-a).length),material)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def ring(p,name,center,radius,width,material,segments=128):
    vs=[];fs=[]
    for i in range(segments):
        a=i*math.tau/segments
        for r in (radius-width/2,radius+width/2):vs.append((center[0]+r*math.cos(a),center[1]+r*math.sin(a),center[2]))
    for i in range(segments):fs.append((2*i,2*i+1,(2*i+3)%(2*segments),(2*i+2)%(2*segments)))
    me=bpy.data.meshes.new(p+'_'+name);me.from_pydata(vs,[],fs);me.materials.append(material)
    o=bpy.data.objects.new(p+'_'+name,me);coll(p).objects.link(o);return o

def light(p,name,loc,target,energy,color,size=4):
    d=bpy.data.lights.new(p+'_'+name,'AREA');d.energy=energy;d.color=color;d.shape='DISK';d.size=size
    o=bpy.data.objects.new(p+'_'+name,d);coll(p,'RedesignLights').objects.link(o);o.location=loc
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o

def move(name,loc,scale=None,rz=None):
    o=bpy.data.objects[name];o.location=loc
    if scale is not None:o.scale=(scale,scale,scale) if isinstance(scale,(int,float)) else scale
    if rz is not None:o.rotation_euler.z=rz
    return o

def duplicate(root,p,name,loc,scale=None,rz=None):
    mapping={}
    def cp(old):
        new=old.copy();new.name=name if old==root else name+'__'+old.name
        coll(p,'RedesignProps').objects.link(new);mapping[old]=new
        for ch in old.children:cp(ch)
    cp(root)
    for old,new in mapping.items():
        if old.parent in mapping:new.parent=mapping[old.parent]
        new.matrix_parent_inverse=old.matrix_parent_inverse.copy();new.matrix_basis=old.matrix_basis.copy()
    n=mapping[root];n.location=loc
    if scale is not None:n.scale=(scale,)*3 if isinstance(scale,(int,float)) else scale
    if rz is not None:n.rotation_euler.z=rz
    return n

def fix_common_transforms():
    # The earlier F06 duplication lost non-identity parent inverses.
    for dst in bpy.data.scenes[SCENES['F06A']].objects:
        if dst.name.startswith('F06A_BossAccessDoor'):
            src=bpy.data.objects.get(dst.name.replace('F06A_','F07A_',1))
            if src:dst.matrix_parent_inverse=src.matrix_parent_inverse.copy()
    for dst in bpy.data.scenes[SCENES['F06B']].objects:
        if dst.name.startswith('F06B_RewardSelection'):
            src=bpy.data.objects.get(dst.name.replace('F06B_','F07B_',1))
            if src:dst.matrix_parent_inverse=src.matrix_parent_inverse.copy()

def base(p,height):
    m=materials();s=bpy.data.scenes[SCENES[p]]
    warm=p.startswith('F06');wall=m['warmwall'] if warm else m['wall']
    arch=bpy.data.collections[p+'_Architecture']
    oldh=5.8 if p.endswith('A') else 9
    for o in arch.objects:
        if any(w in o.name for w in ['SideWall','RearWall','WallPilaster','AxialRearColumn']):
            if o.type=='MESH':o.dimensions.z=height;o.location.z=height/2
        if o.name.endswith('_Ceiling'):o.location.z=height+.16
        if 'CeilingCrossBeam' in o.name:o.location.z +=height-oldh
        if o.type=='MESH' and any(w in o.name for w in ['SideWall','RearWall','Ceiling','WallPilaster']):
            o.data=o.data.copy();o.data.materials.clear();o.data.materials.append(wall)
    s.world=s.world.copy();s.world.name=p+'_RedesignWorld'
    for n in s.world.node_tree.nodes:
        if n.type=='BACKGROUND':n.inputs['Color'].default_value=(.25,.28,.32,1);n.inputs['Strength'].default_value=.22
    for o in list(bpy.data.collections[p+'_Lighting'].objects):
        if o.type=='LIGHT':
            o.data=o.data.copy();o.data.energy*=1.3
            o.data.color=(1,.70,.42) if warm else (.64,.85,1)
    s.view_settings.exposure=.65
    s['redesign_version']='v035';s['uses_existing_floor_assets']=True
    return m,s

def center_residual_door(p):
    for suffix,x in [('RearWall',-6.5),('RearWall.001',6.5)]:
        o=bpy.data.objects[p+'_'+suffix];o.location.x=x;o.dimensions.x=9
    bpy.data.objects[p+'_RearHeader'].location.x=0
    for o in bpy.data.scenes[SCENES[p]].objects:
        if o.parent is None and ('Passage' in o.name or o.name.startswith('trigger_'+p) or o.name.startswith('anchor_'+p)):
            o.location.x-=7.5
    bpy.data.objects[p+'_BossAccessDoor'].location.x-=7.5
    bpy.data.objects['CAM_'+p+'_BossAccessDoor'].location.x=0

def camera(p,loc,target,lens=23):
    s=bpy.data.scenes[SCENES[p]];name=p+'_RedesignOverview'
    d=bpy.data.cameras.new(name);d.lens=lens;d.clip_end=200
    o=bpy.data.objects.new(name,d);coll(p,'Cameras').objects.link(o);o.location=loc
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();s.camera=o
    s.render.resolution_x=1200;s.render.resolution_y=850;s.render.resolution_percentage=100
    return o

def residual7():
    p='F07A';m,s=base(p,5.8);center_residual_door(p)
    move('F07A_FracturedMap',(-5.1,11.2,0),(3.85,1.85,3.85))
    move('F07A_LogCabinet',(6.5,10.7,0),3.3)
    move('F07A_ProjectorBench',(-6.4,4.2,0),2.7,0)
    move('F07A_LeftSurveyPartition',(-4.7,5.6,0),3.5,math.pi/2)
    move('F07A_RightSurveyPartition',(5.6,5.7,0),3.5,math.pi/2)
    move('F07A_Console',(7.6,5.6,0),2.6,-.25)
    move('F07A_Theodolite',(-3.6,8.8,0),2.4,.2)
    move('F07A_BackReference',(3.2,10.9,0),2.9)
    move('F07A_SurveyRack',(-9.3,8.8,0),3.4,.2)
    move('F07A_CableSpool',(8,.5,0),2.05,-.2)
    move('F07A_DriftBeacon',(-2.4,5.1,0),1.1)
    move('F07A_DriftBeacon.001',(2.4,5.1,0),1.1)
    for x in [-3.0,3.0]:
        box(p,'SurveyTrack',(x,4.2,.025),(.085,13,.03),m['brass'])
        for y in range(-2,11):box(p,'TrackTick',(x,y,.045),(.38 if y%2==0 else .22,.035,.02),m['brass'])
    for y in [1,6,10]:
        box(p,'HorizontalSurveyBeam',(0,y,5.32),(21,.32,.45),m['iron'])
        for x in [-6,6]:
            box(p,'CeilingPractical',(x,y,5.07),(4.6,.12,.08),m['teal'])
            light(p,'SurveyWash',(x,y,4.9),(x,y+1,0),500,(.57,.84,1),4)
    light(p,'MapKey',(-5.1,8.7,4.4),(-5.1,11,2),650,(.45,.88,1),3)
    light(p,'FrontSoftbox',(0,-5,4.6),(0,5,1),1000,(.81,.88,1),7)
    camera(p,(0,-8,3.5),(0,6.2,1.4),23)
    s['room_identity']='Coordinate survey room / low horizontal workshop'

def residual6():
    p='F06A';m,s=base(p,4.9);center_residual_door(p)
    move('floor6-clockwork-evidence-cabinet',(-8.8,8.5,0),3.8,math.pi/2)
    move('floor6-clockwork-evidence-cabinet.001',(-8.8,4.9,0),3.8,math.pi/2)
    duplicate(bpy.data.objects['floor6-clockwork-evidence-cabinet'],p,'F06A_EvidenceBank03',(-8.8,1.3,0),3.8,math.pi/2)
    move('floor6-event-spool-cabinet',(8.9,8.8,0),3.8,-math.pi/2)
    move('floor6-event-spool-cabinet.001',(8.9,5.6,0),3.8,-math.pi/2)
    duplicate(bpy.data.objects['floor6-event-spool-cabinet'],p,'F06A_ReelBank03',(8.9,2.4,0),3.8,-math.pi/2)
    move('floor6-pendulum-calibration-rack',(-4.7,11.1,0),3.8,0)
    move('floor6-delayed-impact-test-target',(5,10.7,0),3.1,0)
    move('floor6-timeline-strip-table',(-5,4.8,0),4,math.pi/2)
    move('floor6-consequence-ledger-printer',(-5,-.3,0),2.2,.1)
    move('floor6-sequence-verification-console',(5.2,3.6,0),2.7,-.15)
    move('floor6-event-capsule-transport-crate',(-7.2,-1.4,0),1.6,0)
    move('floor6-cause-marker-stake-set',(-5.4,8.1,0),1.8,0)
    # Maintain a shallow encounter node and an unobstructed central aisle.
    o=move('floor6-broken-chronometer-floor-node',(0,5.1,.01));o.scale.z*=.3
    move('SPAWN_CausalityResidue',(0,5.1,.34))
    move('floor6-causal-cable-bridge-panel',(0,8.8,.01));bpy.data.objects['floor6-causal-cable-bridge-panel'].scale.z*=.18
    for y in [-1,3.5,8,11]:
        box(p,'ArchiveCrossBeam',(0,y,4.55),(21,.48,.36),m['iron'])
        for x in [-5.5,5.5]:
            box(p,'ArchiveStrip',(x,y,4.32),(4,.14,.1),m['amber'])
            light(p,'ArchiveReading',(x,y,4.1),(x,y+1,0),480,(1,.73,.45),3.5)
    for x in [-7.6,7.6]:
        box(p,'ArchivePlinth',(x,5.2,.13),(3.1,12.8,.26),m['iron'])
        box(p,'ArchiveFascia',(x,5.2,4.25),(3,12.8,.24),m['brass'])
    for y in [1,4,7,10]:
        for x in [-2.6,2.6]:box(p,'SequenceMarker',(x,y,.035),(.3,.1,.025),m['brass'])
    light(p,'FrontSoftbox',(0,-5,4.3),(0,5,1),1100,(1,.84,.67),6)
    camera(p,(0,-8,3.15),(0,6.2,1.1),23)
    s['room_identity']='Event archive / low dense evidence and reel banks'

def boss7():
    p='F07B';m,s=base(p,12)
    move('F07B_GyroscopicAnchor',(0,15.4,.05),6.8,0)
    move('F07B_ReferenceAxisGate',(0,18.1,0),(9.8,1.796,9.8),0)
    move('F07B_CalibrationGantry',(-6.5,13.7,0),6.4,0)
    duplicate(bpy.data.objects['F07B_CalibrationGantry'],p,'F07B_CalibrationGantry_Right',(6.5,13.7,0),6.4,0)
    move('F07B_PhasePrism',(-5.7,8.7,0),3.4)
    move('F07B_PhasePrism.001',(5.7,8.7,0),3.4)
    move('F07B_AxisTotem',(-5.7,3.1,0),3.7)
    move('F07B_AxisTotem.001',(5.7,3.1,0),3.7)
    move('F07B_PlumbSensor',(0,15.4,8),3.2)
    for o in bpy.data.collections[p+'_Architecture'].objects:
        if 'SensorSuspension' in o.name:o.hide_render=True;o.hide_viewport=True
    beam(p,'SensorDrop',(0,15.4,11.8),(0,15.4,11),.055,m['iron'])
    for sign in [-1,1]:
        x=sign*9.7
        box(p,'GalleryDeck',(x,5.5,4),(3.1,17,.3),m['iron'])
        box(p,'GalleryFascia',(sign*8.18,5.5,4.03),(.14,17,.48),m['brass'])
        for y in [-2,2,6,10,13]:
            box(p,'GallerySupport',(sign*10.5,y,1.9),(.45,.6,3.8),m['wall'])
            box(p,'GalleryRailPost',(sign*8.2,y,4.65),(.08,.08,1.1),m['iron'])
        for z in [4.55,5.15]:box(p,'GalleryHandrail',(sign*8.2,5.5,z),(.07,17,.07),m['brass'])
        for i in range(16):box(p,'GalleryStair',(sign*9.7,-6.4+i*.25,(i+1)*.24/2),(2.4,.27,(i+1)*.24),m['wall'])
        for y in [1,7,13]:
            box(p,'CalibrationMast',(sign*7.6,y,7.65),(.35,.55,7.4),m['iron'])
            box(p,'MastLight',(sign*7.39,y-.3,7.8),(.09,.06,5),m['teal'])
    for y in [3,10,16]:
        box(p,'OverheadGantry',(0,y,11.3),(23,.7,.7),m['iron'])
        box(p,'GantryTrack',(0,y-.39,10.98),(19,.06,.1),m['teal'])
    for x in [-2.6,2.6]:box(p,'AxialTrack',(x,6,.026),(.09,24,.025),m['brass'])
    light(p,'GyroKey',(0,11,8),(0,15.4,3.4),1700,(.36,.83,1),5)
    light(p,'FrontSoftbox',(0,-5,7),(0,8,1),2200,(.75,.86,1),8)
    for x in [-7,7]:light(p,'GalleryWash',(x,6,10),(x,8,1),1400,(.6,.85,1),5)
    camera(p,(0,-8.5,4.1),(0,9,3),22)
    s['room_identity']='Reference axis hall / tall gantries and elevated galleries'

def boss6():
    p='F06B';m,s=base(p,8)
    arch=bpy.data.collections[p+'_Architecture']
    for o in arch.objects:
        if any(k in o.name for k in ['CentralFloorRail','CoordinateTick','SensorSuspension','AxialRearColumn']):o.hide_render=True;o.hide_viewport=True
    # Chamfered wall inserts form an octagonal chamber within the existing envelope.
    for a,b in [((-12,-3),(-6,-9)),((6,-9),(12,-3)),((-12,13),(-6,19)),((6,19),(12,13))]:
        center=((a[0]+b[0])/2,(a[1]+b[1])/2,4)
        length=math.dist(a,b);ang=math.atan2(b[1]-a[1],b[0]-a[0])
        box(p,'OctagonalWall',center,(length,.4,8),m['warmwall'],ang)
        box(p,'OctagonalWainscot',(center[0],center[1],.8),(length,.5,1.6),m['iron'],ang)
    for r in [4.8,5.2,6.9,7.3]:ring(p,'CausalityCircuit',(0,8.8,.036),r,.085,m['brass'])
    for i in range(48):
        a=math.tau*i/48;r=7.1
        box(p,'SequenceIndex',(r*math.cos(a),8.8+r*math.sin(a),.055),(.4 if i%4==0 else .2,.05,.024),m['brass'],a)
    move('floor6-cause-effect-chain-loom',(0,16.8,0),7.2,0)
    move('floor6-dual-clock-causality-pillar',(-5.6,12.5,0),5.6,.08)
    move('floor6-dual-clock-causality-pillar.001',(5.6,12.5,0),5.6,-.08)
    move('floor6-delay-chamber-hourglass',(-8.6,15.5,0),4.8,.25)
    move('floor6-two-stage-descent-gate',(8.2,15.8,0),5.4,-.3)
    move('floor6-verdict-seal-press',(9.4,9.3,0),2.7,-.35)
    move('floor6-sequence-verification-console.001',(9,4,0),2.6,-.3)
    move('floor6-event-warning-beacon',(-5.9,4.2,0),2.6)
    move('floor6-event-warning-beacon.001',(5.9,4.2,0),2.6)
    move('floor6-causal-cable-bridge-panel.001',(0,2.8,.01));bpy.data.objects['floor6-causal-cable-bridge-panel.001'].scale.z*=.2
    duplicate(bpy.data.objects['F07B_DescentStele'],p,'F06B_DescentStele',(10.1,13.2,0),2.7,0)
    duplicate(bpy.data.objects['F07B_DescentPedestal'],p,'F06B_DescentPedestal',(7.8,13.3,0),2.7,math.pi/2)
    move('anchor_F06_descent_interaction',(8.2,11.2,0))
    cam=bpy.data.objects['CAM_F06_DescentDoor'];cam.location=(8.2,8.3,1.8);cam.rotation_euler=(Vector((8.2,15.8,2))-cam.location).to_track_quat('-Z','Y').to_euler()
    for x in [-7,7]:
        box(p,'RadialBeam',(x,6,7.55),(.5,22,.5),m['iron'])
        for y in [0,7,14]:light(p,'AmberVault',(x,y,7.2),(x*.7,y+2,1),950,(1,.70,.36),4)
    light(p,'VerdictKey',(0,8,7.3),(0,15.5,2.5),1600,(1,.63,.29),5)
    light(p,'FrontSoftbox',(0,-5,6),(0,8,1.5),2100,(1,.85,.66),8)
    camera(p,(0,-8.5,4),(0,9,2.2),22)
    s['room_identity']='Causality verdict chamber / octagonal perimeter and radial circuits'

def run(phase):
    if phase=='common':fix_common_transforms()
    else:globals()[phase]()
    bpy.context.view_layer.update()
    print('Completed',phase)

if __name__=='__main__':
    for phase in ['common','residual7','residual6','boss7','boss6']:run(phase)
