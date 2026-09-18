"""Visual refinement, after redesign_f06_f07_v035.py."""
import bpy,runpy,math
from mathutils import Vector
from pathlib import Path
R=runpy.run_path(str(Path(bpy.data.filepath).parent/'redesign_f06_f07_v035.py'),run_name='helpers')
box,beam,light,move=[R[k] for k in ['box','beam','light','move']]
m=R['materials']()
for key,color in [('wall',(.055,.07,.08)),('warmwall',(.085,.072,.055))]:
    n=next(n for n in m[key].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    n.inputs['Base Color'].default_value=(*color,1);m[key].diffuse_color=(*color,1)

for p,sn in R['SCENES'].items():
    s=bpy.data.scenes[sn];warm=p.startswith('F06');boss=p.endswith('B')
    s.view_settings.exposure=.1
    for n in s.world.node_tree.nodes:
        if n.type=='BACKGROUND':n.inputs['Strength'].default_value=.08
    for o in s.objects:
        if o.type=='LIGHT' and o.name.startswith(p):o.data.energy*=.7
    camera=s.camera;camera.location=(0,-5.9,3.15 if boss else 2.9);camera.data.lens=24
    camera.rotation_euler=(Vector((0,9,2.0) if boss else (0,7,1.5))-camera.location).to_track_quat('-Z','Y').to_euler()
    s.render.resolution_x=1280;s.render.resolution_y=800
    # Inset wall panels and ribs give the industrial shell thickness and scale.
    maxy=16 if boss else 10;h=12 if p=='F07B' else (8 if boss else (4.9 if warm else 5.8))
    for sign in [-1,1]:
        wallx=11.88 if boss else 10.88
        for y in range(-4,maxy,4):
            box(p,'WallInset',(sign*wallx,y,2.3),(.1,3.2,3.4),m['iron'])
            for dy in [-1.58,1.58]:box(p,'PanelEdge',(sign*(wallx-.07),y+dy,2.3),(.08,.055,3.5),m['brass'])
            box(p,'PanelLowerBand',(sign*(wallx-.08),y,.9),(.1,3.2,.06),m['brass'])
            box(p,'RibFoot',(sign*(wallx-.2),y-1.94,.22),(.65,.72,.44),m['iron'])
            box(p,'RibCapital',(sign*(wallx-.2),y-1.94,h-.42),(.65,.72,.38),m['iron'])
    if boss:
        o=bpy.data.objects[p+'_RewardBackdrop'];o.hide_render=True;o.hide_viewport=True
        for o in bpy.data.collections[p+'_Architecture'].objects:
            if any(k in o.name for k in ['RewardBayHeader','RewardBayPillar','DescentBayHeader','DescentBayPillar']):
                o.hide_render=True;o.hide_viewport=True
    if p=='F06A':
        o=bpy.data.objects[p+'_RearHeader'];o.location.z=4.55;o.dimensions.z=.7
        for o in s.objects:
            if o.name.startswith(p+'_ArchivePlinth'):o.location.z=.025;o.dimensions.z=.05
        # Dense banks return around the rear wall; shelves remain visibly separate.
        R['duplicate'](bpy.data.objects['floor6-clockwork-evidence-cabinet'],p,'F06A_BackEvidence',(-7.8,10.7,.05),3.5,0)
        R['duplicate'](bpy.data.objects['floor6-event-spool-cabinet'],p,'F06A_BackReels',(8,10.7,.05),3.5,0)
    if p=='F07B':
        # Structural braces, bolted deck edges and a three-line handrail.
        for sign in [-1,1]:
            for y in [-2,2,6,10,13]:
                beam(p,'GalleryBrace',(sign*10.5,y,2.5),(sign*8.3,y,3.85),.17,m['iron'])
                box(p,'GalleryCollar',(sign*10.5,y,3.5),(.8,.9,.18),m['brass'])
                box(p,'MastBase',(sign*7.6,y,4.15),(.8,.95,.3),m['iron'])
            box(p,'GalleryMidRail',(sign*8.2,5.5,4.85),(.05,17,.05),m['iron'])
        # Frame the gyroscope instead of obscuring it with the original tall gate.
        move('F07B_ReferenceAxisGate',(0,18.3,0),(9.8,1.3,9.8))
        move('F07B_DescentDoor',(8.9,16.2,0),5.5,-.25)
        move('F07B_DescentStele',(8.9,11.7,0),2.7,0)
        move('F07B_DescentPedestal',(8.6,14.2,0),2.7,math.pi/2)
        move('anchor_F07_descent_interaction',(8.9,10.3,0))
        c=bpy.data.objects['CAM_F07_DescentDoor'];c.location=(8.9,8,1.8);c.rotation_euler=(Vector((8.9,16.2,2))-c.location).to_track_quat('-Z','Y').to_euler()
        light(p,'RightGateKey',(8.2,12,6.5),(8.9,16,2.5),750,(.55,.85,1),4)
    if p=='F06B':
        # Keep tall side assets forward of the octagonal corner walls.
        move('floor6-two-stage-descent-gate',(8.1,14.2,0),5.4,-.3)
        move('floor6-delay-chamber-hourglass',(-8.1,14.2,0),4.8,.3)
        move('floor6-dual-clock-causality-pillar',(-4.9,12.3,0),5.6,.08)
        move('floor6-dual-clock-causality-pillar.001',(4.9,12.3,0),5.6,-.08)
        move('F06B_DescentStele',(9.4,11.4,0),2.7,0)
        move('F06B_DescentPedestal',(7.8,11.5,0),2.7,math.pi/2)
        for i in range(8):
            a=math.tau*i/8;x=9.8*math.cos(a);y=6+10.3*math.sin(a)
            box(p,'VerdictColumn',(x,y,3.85),(.55,.55,7.7),m['iron'])
            box(p,'VerdictColumnFoot',(x,y,.28),(.95,.95,.56),m['brass'])
            box(p,'VerdictColumnCap',(x,y,7.25),(.9,.9,.35),m['brass'])
        # Existing clock/chain machinery remains the focus of the radial hall.
        for radius in [5.4,7.5]:R['ring'](p,'VaultRing',(0,8.8,7.35),radius,.14,m['brass'],96)
        light(p,'GateKey',(8,10,6),(8.1,14.2,2.5),900,(1,.75,.43),4)
        light(p,'HourglassKey',(-8,10,6),(-8.1,14.2,2.5),900,(1,.75,.43),4)
    s['redesign_refinement']='darker concrete, industrial panel ribs, closer composition'
bpy.context.view_layer.update()
print('Refinement applied')
