import bpy,runpy,math,json
from mathutils import Vector
from pathlib import Path
F=runpy.run_path(str(Path(__file__).parent/'build_floor5_v039.py'));m=F['mats']()
for p,sn in F['SCENES'].items():
    s=bpy.data.scenes[sn];bpy.context.window.scene=s
    s.view_settings.exposure=-.65
    for n in s.world.node_tree.nodes:
        if n.type=='BACKGROUND':n.inputs['Strength'].default_value=.10
    for o in s.objects:
        if o.type=='LIGHT':o.data.energy*=.85
    boss=p.endswith('B');w=14 if boss else 12;back=19 if boss else 16;h=8 if boss else 5.7
    # Warm stone lower wall panelling, black dado and finely inset brass borders.
    for sign in [-1,1]:
        F['box'](p,'DadoPanel',(sign*(w-.04),3,1.2),(.1,27 if boss else 26,2.15),m['iron'])
        for y in [-7,-3,1,5,9,13]:
            F['box'](p,'IvoryWallInset',(sign*(w-.105),y,3.65),(.07,3.15,2.6),m['stone'])
            for yy in [y-1.65,y+1.65]:F['box'](p,'InsetBorder',(sign*(w-.17),yy,3.65),(.075,.05,2.8),m['brass'])
            for z in [2.25,5.05]:F['box'](p,'InsetBorder',(sign*(w-.17),y,z),(.075,3.35,.05),m['brass'])
    # Back wall niches unify the equipment into an archive rather than isolated props.
    for x in ([-9,-6,-3.5,0,3.5,6] if boss else [-8,-5.6,-2.8,.2,3.7]):
        width=2.35 if boss else 2.2
        F['box'](p,'RearNiche',(x,back-.055,2.5),(width,.08,4.75),m['iron'])
        for xx in [x-width/2,x+width/2]:F['box'](p,'RearNicheTrim',(xx,back-.12,2.6),(.06,.09,4.9),m['brass'])
        F['box'](p,'RearNicheCrown',(x,back-.12,5.05),(width,.12,.1),m['brass'])
    F['box'](p,'RearCornice',(0,back-.08,5.5 if not boss else 6.0),(w*2,.15,.18),m['brass'])
    if not boss:
        # Close the semicircular tympanum under the barrel vault at the back.
        N=48;vs=[(-w,back,h),(w,back,h)]+[(w*math.cos(math.pi*i/N),back,h+1.8*math.sin(math.pi*i/N)) for i in range(N+1)]
        F['mesh'](p,'VaultEndTympanum',vs,[tuple(range(2,len(vs)))],m['stone'])
        for label in ['ReelBank01','ReelBank02','Portraits','SidePortraits']:
            bpy.data.objects[p+'_'+label].rotation_euler.z+=math.pi
        # Rear complementary records and right-hand side cabinet give equal side coverage.
        F['imported'](p,'floor5-memory-tape-reel-server',p+'_RearMasterReel',(.2,14.6,0),4.3,'z',math.pi)
        F['imported'](p,'floor5-memory-reliquary-cabinet',p+'_NearRightReliquary',(10.6,-3.2,0),3.7,'z',math.pi/2)
    else:
        for label in ['ReliquaryLeft','PortraitsLeft','ReelRight']:
            bpy.data.objects[p+'_'+label].rotation_euler.z+=math.pi
        # Move reward into the overview while keeping the approach separate from combat.
        bpy.data.objects['F05B_RewardSelection'].location.y+=2.6
        bpy.data.objects['anchor_F05_reward_interaction'].location.y+=2.6
        bpy.data.objects['F05B_RewardKey'].location.y+=2.6
    bpy.context.view_layer.update()
    # Place labels on crates above their real imported top rather than using estimated heights.
    crate=bpy.data.objects[p+('_CylinderCase' if boss else '_CylinderCrate')]
    tags=bpy.data.objects[p+('_BlankTags' if boss else '_LostTags')]
    tags.location.z=F['bounds'](crate)[1].z+.025
    bpy.data.objects[p+'_Overview'].data.lens=18.3
    # Display the common stage at the same height as its surface marker.
    s.frame_set(66 if boss else 1);bpy.context.view_layer.update()

def fit(p,name,roots,target=None,margin=.09,lens=28):
    from bpy_extras.object_utils import world_to_camera_view
    s=bpy.data.scenes[F['SCENES'][p]];bpy.context.window.scene=s;bpy.context.view_layer.update()
    cam=bpy.data.objects[name];cam.data.lens=lens
    pts=[v for root in roots for v in F['allpts'](bpy.data.objects[root])]
    lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)])
    center=Vector(target) if target else (lo+hi)/2
    direction=(cam.location-center).normalized()
    for i in range(120):
        cam.location=center+direction*(4+i*.12);cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();bpy.context.view_layer.update()
        pr=[world_to_camera_view(s,cam,v) for v in pts]
        if all(v.z>0 and margin<v.x<1-margin and margin<v.y<1-margin for v in pr):break
    print(name,'fitted',list(cam.location))

fit('F05B','CAM_F05_RewardSelection',['F05B_RewardSelection'],lens=32)
fit('F05B','CAM_F05_DescentDoor',['F05B_DescentStele','F05B_DescentInputPedestal','F05B_DescentPlatform'],target=(9,15.6,1.6),lens=25)
for p,sn in F['SCENES'].items():
    s=bpy.data.scenes[sn];s.camera=bpy.data.objects[p+'_Overview']
print('Lighting, wall detailing, source orientations, camera clearances refined')
