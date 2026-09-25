"""5F approved layout. Additive only; run setup, architecture, then prop batches.
Existing scenes and source assets remain untouched. Dimensions are in metres.
"""
import bpy, math, json, hashlib
from pathlib import Path
from mathutils import Vector, Matrix

OUT=Path(__file__).parent
PATHS=json.loads((OUT/'floor5_asset_paths.json').read_text())
SCENES={'F05A':'DA_F05A_MemoryOmissionResidue','F05B':'DA_F05B_OriginalMemoryAdministrator'}

def collection(p,part):
    name=p+'_'+part
    c=bpy.data.collections.get(name)
    if c is None:
        c=bpy.data.collections.new(name);bpy.data.scenes[SCENES[p]].collection.children.link(c)
    return c

def mesh(p,name,verts,faces,material,part='Architecture'):
    me=bpy.data.meshes.new(p+'_'+name);me.from_pydata(verts,[],faces);me.update()
    if material: me.materials.append(material)
    o=bpy.data.objects.new(me.name,me);collection(p,part).objects.link(o);return o

def box(p,name,loc,dim,mat,rz=0,part='Architecture',bevel=.035):
    o=mesh(p,name,[(x*dim[0]/2,y*dim[1]/2,z*dim[2]/2) for x,y,z in [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]],[(0,2,6,4),(1,5,7,3),(0,4,5,1),(2,3,7,6),(0,1,3,2),(4,6,7,5)],mat,part)
    o.location=loc;o.rotation_euler.z=rz
    if bevel:
        b=o.modifiers.new('Soft worn edges','BEVEL');b.width=min(bevel,min(dim)*.2);b.segments=2
    return o

def material(name,color,metal=.0,rough=.6,noise=False,emit=0):
    m=bpy.data.materials.get('DA39_'+name)
    if m:return m
    m=bpy.data.materials.new('DA39_'+name);m.use_nodes=True;m.diffuse_color=(*color,1)
    n=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    n.inputs['Base Color'].default_value=(*color,1);n.inputs['Metallic'].default_value=metal;n.inputs['Roughness'].default_value=rough
    if emit:n.inputs['Emission Color'].default_value=(*color,1);n.inputs['Emission Strength'].default_value=emit
    if noise:
        tex=m.node_tree.nodes.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=7;tex.inputs['Detail'].default_value=3
        ramp=m.node_tree.nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(*(v*.65 for v in color),1);ramp.color_ramp.elements[1].color=(*(v*1.22 for v in color),1)
        m.node_tree.links.new(tex.outputs['Fac'],ramp.inputs[0]);m.node_tree.links.new(ramp.outputs['Color'],n.inputs['Base Color'])
        bump=m.node_tree.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.2;bump.inputs['Distance'].default_value=.07
        m.node_tree.links.new(tex.outputs['Fac'],bump.inputs['Height']);m.node_tree.links.new(bump.outputs[0],n.inputs['Normal'])
    return m

def mats():
    return {'stone':material('Warm limestone',(.29,.265,.23),noise=True),'floor':material('Archive basalt',(.09,.095,.093),rough=.65,noise=True),'iron':material('Black iron',(.035,.042,.044),.72,.38,True),'brass':material('Aged brass',(.30,.20,.08),.75,.37,True),'ivory':material('Porcelain ivory',(.64,.58,.43),.05,.5,True),'red':material('Wax red',(.19,.014,.02),.1,.45),'lamp':material('Ivory light',(1,.77,.45),emit=3),'violet':material('Memory violet',(.30,.09,.64),emit=2)}

def empty(p,name,loc=(0,0,0),part='Gameplay'):
    o=bpy.data.objects.new(name,None);collection(p,part).objects.link(o);o.location=loc;return o

def camera(p,name,loc,target,lens=23):
    d=bpy.data.cameras.new(name);d.lens=lens;d.clip_start=.08;d.clip_end=180
    o=bpy.data.objects.new(name,d);collection(p,'Cameras').objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o

def light(p,name,loc,target,power,color=(1,.84,.67),size=5):
    d=bpy.data.lights.new(p+'_'+name,'AREA');d.energy=power;d.color=color;d.size=size
    o=bpy.data.objects.new(d.name,d);collection(p,'Lighting').objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o

def tube(p,name,pts,r,mat,part='Architecture',sides=8):
    vs=[];fs=[]
    for i,pt in enumerate(pts):
        tangent=Vector(pts[min(i+1,len(pts)-1)])-Vector(pts[max(0,i-1)])
        q=tangent.to_track_quat('Z','Y')
        for j in range(sides):vs.append(Vector(pt)+q@Vector((r*math.cos(j*math.tau/sides),r*math.sin(j*math.tau/sides),0)))
    for i in range(len(pts)-1):
        for j in range(sides):a=i*sides+j;b=i*sides+(j+1)%sides;fs.append((a,b,b+sides,a+sides))
    return mesh(p,name,vs,fs,mat,part)

def ring(p,name,center,r,width,mat,z=None):
    pts=[(center[0]+r*math.cos(i*math.tau/128),center[1]+r*math.sin(i*math.tau/128),center[2]) for i in range(129)]
    return tube(p,name,pts,width,mat)

def fingerprint(s):
    data=[(o.name,list(sum((list(r) for r in o.matrix_world),[])),o.hide_render,o.hide_viewport) for o in s.objects]
    return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()

def setup():
    assert not any(n in bpy.data.scenes for n in SCENES.values()),'Already created; do not run setup twice'
    (OUT/'floor5_original_scene_fingerprints.json').write_text(json.dumps({s.name:fingerprint(s) for s in bpy.data.scenes},indent=2))
    base=bpy.data.scenes['DA_F06B_CausalityAdministrator']
    for p,n in SCENES.items():
        s=bpy.data.scenes.new(n);s.world=base.world.copy();s.world.name=p+'_World'
        for node in s.world.node_tree.nodes:
            if node.type=='BACKGROUND':node.inputs['Color'].default_value=(.34,.37,.42,1);node.inputs['Strength'].default_value=.27
        s.render.engine=base.render.engine;s.cycles.samples=32;s.cycles.use_denoising=True
        s.render.resolution_x=1440;s.render.resolution_y=900;s.render.resolution_percentage=100
        s.render.image_settings.file_format='PNG';s.view_settings.view_transform=base.view_settings.view_transform;s.view_settings.exposure=.7
        s.frame_end=90;s['layout_version']='v039';s['floor']=5;s['source']='Approved floor5 concept, supplied GLBs';s['doors']='Decorative sealed wall displays; open architecture passages are gameplay exits'
        s['room_identity']='기억 누락 잔류체 방' if p.endswith('A') else '기억 원본 관리자 방'
    print('Two floor5 scenes initialized')

def architecture(p):
    s=bpy.data.scenes[SCENES[p]];bpy.context.window.scene=s;m=mats();boss=p.endswith('B')
    w=14 if boss else 12;back=19 if boss else 16;front=-11;h=8 if boss else 5.7
    box(p,'Foundation',(0,(front+back)/2,-.23),(w*2,back-front,.45),m['iron'])
    for ix in range(-w,w,2):
        for iy in range(front,back,2):box(p,'FloorTile',(ix+1,iy+1,-.025),(1.985,1.985,.06),m['floor'],bevel=.01)
    for sign in [-1,1]:
        box(p,'SideWall',(sign*(w+.16),(front+back)/2,h/2),(.32,back-front,h),m['stone'])
        for z in [.2,1.1,h-.3]:box(p,'SideCornice',(sign*(w-.035),(front+back)/2,z),(.12,back-front,.12),m['brass'])
        for y in range(-9,back,4):
            box(p,'WallPilaster',(sign*(w-.14),y,h/2),(.26,.4,h),m['iron'])
            box(p,'PilasterCapital',(sign*(w-.16),y,h-.5),(.38,.62,.17),m['brass'])
    # Rear wall has a real opening, distinct from the decorative door meshes.
    exitx=10 if boss else 8.3;gap=4.1;left=exitx-gap/2;right=exitx+gap/2
    box(p,'RearWallLeft',((-w+left)/2,back+.16,h/2),(left+w,.32,h),m['stone'])
    box(p,'RearWallRight',((right+w)/2,back+.16,h/2),(w-right,.32,h),m['stone'])
    box(p,'ExitHeader',(exitx,back+.12,(h+4.8)/2),(gap,.4,h-4.8),m['stone'])
    for x in [left-.1,right+.1]:box(p,'ExitJamb',(x,back-.03,2.4),(.25,.55,4.8),m['iron'])
    box(p,'ExitLintel',(exitx,back-.06,4.75),(gap+.45,.6,.24),m['brass'])
    # A short lit recessed passage; no visible fake door in the interaction lane.
    box(p,'PassageFloor',(exitx,back+2,-.04),(gap,4,.12),m['floor'])
    for x in [left-.1,right+.1]:box(p,'PassageSide',(x,back+2,2.4),(.2,4,4.8),m['stone'])
    box(p,'PassageEnd',(exitx,back+4.1,2.4),(gap,.2,4.8),m['iron'])
    light(p,'ExitWash',(exitx,back+1,4.4),(exitx,back,0),700,(.68,.69,1),3)
    for y in [-6,0,6,12,back-1]:
        if boss:
            box(p,'CeilingCrossBeam',(0,y,h-.15),(w*2,.28,.42),m['iron'])
        for x in [-w+3,w-3]:
            box(p,'LightHousing',(x,y,h-.55),(2.4,.5,.22),m['iron'])
            box(p,'LightDiffuser',(x,y,h-.68),(2.1,.36,.06),m['lamp'])
            light(p,'ReadingPool',(x,y,h-.8),(x,y,0),800 if boss else 550,size=4)
    if boss:
        box(p,'Ceiling',(0,4,h+.28),(28,30,.4),m['stone'])
        for x in [-10,-5,0,5,10]:box(p,'CofferLongBeam',(x,4,h-.1),(.24,30,.4),m['brass'])
        for x in [-7.5,-2.5,2.5,7.5]:
            for y in [-3,3,9,15]:box(p,'CofferInset',(x,y,h+.025),(4.65,5.55,.14),m['ivory'])
        box(p,'CentralLightWell',(0,6,h-.05),(5.4,10,.25),m['iron'])
        box(p,'CentralLightGlass',(0,6,h-.2),(5.0,9.6,.08),m['lamp'])
        for y in [2,4,6,8,10]:box(p,'SkylightCrossbar',(0,y,h-.28),(5.2,.08,.08),m['brass'])
        light(p,'Skylight',(0,6,7.4),(0,6,0),2100,(1,.88,.7),7)
    else:
        # Segmental barrel vault; a shallow curved ceiling with no columns inside the arena.
        vs=[];fs=[];N=48
        for y in [front,back]:
            for i in range(N+1):
                t=math.pi*i/N;vs.append((w*math.cos(t),y,h+1.8*math.sin(t)))
        for i in range(N):fs.append((i,i+1,N+2+i,N+1+i))
        roof=mesh(p,'IvoryBarrelVault',vs,fs,m['ivory']);sol=roof.modifiers.new('Vault shell','SOLIDIFY');sol.thickness=.22
        for y in [-9,-4,1,6,11,15.8]:
            tube(p,'VaultRib',[(w*math.cos(math.pi*i/N),y,h+1.8*math.sin(math.pi*i/N)-.10) for i in range(N+1)],.10,m['brass'])
        for x in [-8,-4,0,4,8]:
            z=h+1.8*math.sqrt(1-(x/w)**2)
            box(p,'VaultLongitudinalRib',(x,2.5,z-.1),(.1,27,.15),m['iron'])
    light(p,'FrontFill',(0,-7,5.2),(0,8,1.5),2200 if boss else 1700,(.85,.88,1),8)
    light(p,'RearHero',(0,12,6.6 if boss else 5.1),(0,15,1.4),1700 if boss else 1000,size=6)
    for x in [-6,6]: light(p,'SideFill',(x,-3,4.8),(x,6,1.3),1100,(1,.83,.6),6)
    s.camera=camera(p,p+'_Overview',(0,-10,4.5 if boss else 3.7),(0,7.5,2.2 if boss else 1.85),20)
    camera(p,'F05_iPad_MainCamera' if boss else 'F05A_iPad_MainCamera',(0,-5.8,2.7),(0,6,1.9),23)
    for side,sign in [('Left',-1),('Right',1)]:camera(p,p+'_SideCheck_'+side,(0,-5.8,2.7),(sign*10,0,2.0),23)
    camera(p,p+'_CeilingReview',(0,-7,3.5),(0,8,5.8),18)
    spawn=empty(p,'SPAWN_OriginalMemoryAdministrator' if boss else 'SPAWN_MemoryOmissionResidue',(0,6 if boss else 5,.36))
    spawn['role']='combat_spawn'
    empty(p,'anchor_'+p+'_entry',(0,-7,0))
    empty(p,'trigger_'+p+('_to_Floor04' if boss else '_to_OriginalMemoryAdministrator'),(exitx,back+1,1))
    empty(p,'anchor_'+p+'_exit',(exitx,back-2,0))
    camera(p,'CAM_F05_DescentDoor' if boss else 'CAM_F05A_BossAccess',(8.3,7.8,3.3) if boss else (8.3,10,2.4),(9,16,1.3) if boss else (8.3,16,2.0),23)
    print(p,'architecture complete',len(s.objects))

def allpts(root):
    return [o.matrix_world@Vector(v) for o in [root]+list(root.children_recursive) if o.type=='MESH' for v in o.bound_box]

def bounds(root):
    pts=allpts(root);return Vector([min(v[i] for v in pts) for i in range(3)]),Vector([max(v[i] for v in pts) for i in range(3)])

def imported(p,key,name,loc,size,axis='z',rz=0):
    s=bpy.data.scenes[SCENES[p]];bpy.context.window.scene=s
    source=PATHS[key+'.glb'];proto=next((o for o in bpy.data.objects if o.get('source_glb')==source),None)
    if proto:
        mapping={old:old.copy() for old in [proto]+list(proto.children_recursive)}
        for old,new in mapping.items():
            collection(p,'Props').objects.link(new);new.name=name if old==proto else name+'__'+old.name.split('__')[-1]
            new.parent=mapping.get(old.parent);new.matrix_parent_inverse=old.matrix_parent_inverse.copy();new.matrix_basis=old.matrix_basis.copy()
        root=mapping[proto];root.location=(0,0,0);root.rotation_euler=(0,0,0);root.scale=(1,1,1)
    else:
        before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=source)
        added=set(bpy.data.objects)-before;bpy.context.view_layer.update()
        root=empty(p,name,part='Props')
        for i,o in enumerate(sorted(added,key=lambda x:x.name)):
            world=o.matrix_world.copy()
            for c in list(o.users_collection):c.objects.unlink(o)
            collection(p,'Props').objects.link(o)
            o.parent=root;o.matrix_world=world;o.name=name+'__Mesh%02d'%i
        bpy.context.view_layer.update();lo,hi=bounds(root)
        offset=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
        for o in root.children:o.location-=offset
        root['source_glb']=source;root['source_asset']=key
    bpy.context.view_layer.update();lo,hi=bounds(root);k=size/(hi-lo)['xyz'.index(axis)]
    root.scale=(k,k,k);root.rotation_euler.z=rz;root.location=loc;root['purpose']='wall_decoration' if 'gate' in key or key in ['닫힌 문','중간문'] else 'floor5_environment'
    bpy.context.view_layer.update()
    return root

# [asset, label, location, dimension, axis, rotation]. All 20 supplied F05 assets used.
LAYOUT={
'F05A':[
('memory-tape-reel-server','ReelBank01',(-10.4,1.5,0),3.9,'z',math.pi/2),
('memory-tape-reel-server','ReelBank02',(-10.4,6,0),3.9,'z',math.pi/2),
('memory-reliquary-cabinet','Reliquary',(-8,12.2,0),4.0,'z',.25),
('redacted-portrait-cabinet','Portraits',(-10.3,-4.6,0),3.7,'z',math.pi/2),
('echo-playback-terminal','Playback',(-6.8,3.4,0),2.6,'z',.2),
('cracked-echo-mirror','EchoMirror',(3.8,13.5,0),4.6,'z',-.15),
('archive-data-spine-panel','DataSpine',(-3,14.5,0),4.7,'z',0),
('original-signature-light-table','SignatureTable',(8.4,5.7,0),2.6,'z',-.55),
('memory-scroll-cylinder-crate','CylinderCrate',(8.7,1,0),2.0,'x',-.25),
('missing-name-tag-set','LostTags',(8.7,1,1.12),.7,'x',0),
('sealed-memory-casket','SealedCasket',(10,-4.5,0),2.3,'x',-math.pi/2),
('porcelain-mask-shard-set','MaskShards',(6.2,8.6,0),1.4,'x',0),
('redacted-portrait-cabinet','SidePortraits',(10.5,10.5,0),3.5,'z',-math.pi/2),
('memory-archive-gate','DecorativeArchiveGate',(-5.6,15.5,0),4.8,'z',0),
('중간문','DecorativeMiddleDoor',(-10.8,10.8,0),3.8,'z',math.pi/2),
],
'F05B':[
('memory-donor-chair','DonorChair',(0,15.5,.22),4.4,'z',0),
('blank-mask-display-rack','MaskRackLeft',(-3.5,16.5,0),5.3,'z',.1),
('blank-mask-display-rack','MaskRackRight',(3.5,16.5,0),5.3,'z',-.1),
('archive-data-spine-panel','SpineLeft',(-6,17.8,0),5.3,'z',0),
('archive-data-spine-panel','SpineRight',(6,17.8,0),5.3,'z',0),
('mnemonic-extraction-helmet','ExtractionHelmet',(-2.6,13.7,.2),2.4,'z',.2),
('identity-collation-console','IdentityConsole',(-9.6,6.4,0),3.25,'z',.35),
('handwriting-comparison-desk','ComparisonDesk',(-11.7,1,0),4.0,'x',math.pi/2),
('memory-reliquary-cabinet','ReliquaryLeft',(-12.5,8.7,0),4.4,'z',math.pi/2),
('redacted-portrait-cabinet','PortraitsLeft',(-12.5,-4.8,0),4.0,'z',math.pi/2),
('memory-tape-reel-server','ReelRight',(12.4,-5,0),4.2,'z',-math.pi/2),
('mnemonic-vial-carousel','VialCarousel',(11.5,6.5,0),4.5,'z',0),
('wax-imprint-seal-press','WaxPress',(10.5,.8,0),2.8,'z',-.3),
('sealed-memory-casket','MemoryCasket',(8.4,5.5,0),2.3,'x',-.3),
('memory-scroll-cylinder-crate','CylinderCase',(-11.7,4,0),2.0,'x',math.pi/2),
('missing-name-tag-set','BlankTags',(-11.7,4,1.12),.8,'x',0),
('porcelain-mask-shard-set','IdentityFragments',(-5.6,13,0),1.4,'x',0),
('original-signature-light-table','SignatureEvidence',(11.5,10.3,0),2.5,'z',-.5),
('echo-playback-terminal','PlaybackEvidence',(-9.7,10.3,0),2.7,'z',.4),
('cracked-echo-mirror','EchoArchive',(-1.7,18.5,0),4.8,'z',0),
('two-stage-descent-gate','DecorativeSealedGate',(-9,17.9,0),5.4,'z',0),
('닫힌 문','DecorativeClosedDoor',(-13,13.8,0),4.8,'z',math.pi/2),
('발판_비활성','DescentPlatform',(10.4,15.9,.03),3.4,'x',0),
]}

def props(p,start=0,end=None):
    for key,label,loc,size,axis,rz in LAYOUT[p][start:end]:
        key=key if key in ['중간문','닫힌 문','발판_비활성'] else 'floor5-'+key
        name=p+'_'+label
        assert name not in bpy.data.objects,'Already placed '+name
        root=imported(p,key,name,loc,size,axis,rz)
        print(name,[round(v,2) for v in bounds(root)[1]-bounds(root)[0]])

def common_copy(p,source,name,loc,xy_size=None):
    s=bpy.data.scenes[SCENES[p]];bpy.context.window.scene=s
    root=bpy.data.objects[source];mapping={o:o.copy() for o in [root]+list(root.children_recursive)}
    wrapper=empty(p,name,part='Gameplay')
    for old,new in mapping.items():
        new.name=name+'__'+old.name.replace('F06B_','').replace('F09_','')
        collection(p,'Gameplay').objects.link(new);new.parent=mapping.get(old.parent,wrapper)
        new.matrix_parent_inverse=old.matrix_parent_inverse.copy();new.matrix_basis=old.matrix_basis.copy()
    bpy.context.view_layer.update();lo,hi=bounds(wrapper)
    k=xy_size/max((hi-lo).x,(hi-lo).y) if xy_size else 1
    wrapper.scale=(k,k,k);wrapper.location=Vector(loc)-k*Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    wrapper['common_source']=source;bpy.context.view_layer.update();return wrapper

def finish(p):
    boss=p.endswith('B');s=bpy.data.scenes[SCENES[p]];bpy.context.window.scene=s;s.frame_set(1);m=mats()
    common_copy(p,'F06B_MagicInputBoard',p+'_MagicInputBoard',(0,-2.5,.03),4.8)
    common_copy(p,'BossStage_F06',p+'_CombatStage',(0,6 if boss else 5,0),8.3 if boss else 7.0)
    for r in ([4.4,4.65,5.0] if boss else [3.65,3.9,4.2]):ring(p,'ArenaCircuit',(0,6 if boss else 5,.028),r,.022,m['brass'])
    for sign in [-1,1]:
        x=sign*(5.3 if boss else 4.5)
        for y in [-5,-3,-1,1,3,5,7,9,11]:box(p,'WayfindingTick',(x,y,.035),(.22,.065,.025),m['brass'])
    # Decorative doors are explicitly cordoned off; no interaction anchors attached.
    roots=[o for o in s.objects if o.get('purpose')=='wall_decoration']
    for root in roots:
        lo,hi=bounds(root);rz=root.rotation_euler.z;center=(lo+hi)/2
        direction=Vector((math.cos(rz),math.sin(rz),0));forward=Vector((math.sin(rz),-math.cos(rz),0))
        span=max((hi-lo).x,(hi-lo).y)*.55
        center.z=0;center+=forward*.8
        for sign in [-1,1]:
            pt=center+direction*span*sign
            box(p,'SealPost',(pt.x,pt.y,.55),(.075,.075,1.1),m['brass'])
        tube(p,'SealedDisplayCord',[center+direction*(span*(2*i/24-1))+Vector((0,0,1-.18*math.sin(math.pi*i/24))) for i in range(25)],.034,m['red'])
    if boss:
        common_copy(p,'F06B_RewardSelection','F05B_RewardSelection',(-7.1,-1.2,0))
        empty(p,'anchor_F05_reward_interaction',(-7.1,-3.5,0))
        camera(p,'CAM_F05_RewardSelection',(-7.1,-6.6,2.5),(-7.1,-1.2,1.55),32)
        light(p,'RewardKey',(-7.1,-2.5,4.8),(-7.1,-1.2,1.2),950,size=3)
        common_copy(p,'F06B_DescentStele','F05B_DescentStele',(7.25,15,0))
        common_copy(p,'F06B_DescentPedestal','F05B_DescentInputPedestal',(7.25,12.8,0),2.3)
        empty(p,'anchor_F05_descent_interaction',(8.3,11,0))
        light(p,'DescentKey',(8.8,12.4,5.7),(8.8,15,1.2),1300,size=4)
        box(p,'DonorDais',(0,15.3,.10),(5,4,.2),m['iron'])
    s.frame_set(66 if boss else 1);bpy.context.view_layer.update()
    s.camera=bpy.data.objects[p+'_Overview']
    print(p,'finished',len(s.objects))

def save():
    for image in bpy.data.images:
        if image.users and image.source=='FILE' and not image.packed_file:
            try:image.pack()
            except RuntimeError:pass
    out=OUT/'DA_F05_F06_F07_F08_F09_F10_Combined_v039_floor5.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    bpy.data.libraries.write(str(OUT/'DA_F05_TwoRooms_v039.blend'),{bpy.data.scenes[n] for n in SCENES.values()},fake_user=True)
    print('Saved integrated and floor5-only Blender files')
