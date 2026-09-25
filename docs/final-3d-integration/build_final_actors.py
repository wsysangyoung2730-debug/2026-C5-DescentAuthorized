"""Editable articulated actor library. Source GLBs are read only.

Uses supplied Mixamo weights when present; otherwise creates an anatomical rig.
Equipment is assigned to rigid bones instead of blending across the torso.
"""
import argparse, json, math, sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector, Matrix, Quaternion

ROOT=Path(__file__).resolve().parent
ap=argparse.ArgumentParser()
ap.add_argument('--output',type=Path,required=True)
ap.add_argument('--floors',default='4,3,2,1')
ap.add_argument('--final-motion',action='store_true')
ap.add_argument('--only')
args=ap.parse_args(sys.argv[sys.argv.index('--')+1:])
args.output.mkdir(parents=True,exist_ok=True)
configs=[r for r in json.loads((ROOT/'actor-contracts.json').read_text()) if str(r['floor']) in args.floors.split(',') and (not args.only or r['name']==args.only)]

def smooth(t):
    t=max(0,min(1,t));return t*t*(3-2*t)

def anatomical_config(row, width):
    name=row['name']
    head=2.72; shoulder=2.33; half=min(.47,width*.24); hip=1.32
    if name=='FinalAuthorizationAdministrator': head=2.26; shoulder=1.94; half=.43; hip=1.12
    if name in ['RejectionExecutionResidual','OverloadResidual','BackflowBlockerResidual']:
        head=2.5; shoulder=2.25; half=.48
    if name=='ResponsibilityAuditAdministrator': shoulder=2.4;head=2.78
    book=any(x in name for x in ['SignatureMimic','ConsentCustodian','IdentityComparison'])
    specs={'root':((0,0,0),(0,0,.3),None),
        'pelvis':((0,0,hip-.25),(0,0,hip),'root'),
        'spine':((0,0,hip),(0,0,(hip+shoulder)/2),'pelvis'),
        'chest':((0,0,(hip+shoulder)/2),(0,0,shoulder),'spine'),
        'neck':((0,0,shoulder),(0,0,head-.16),'chest'),
        'head':((0,0,head-.16),(0,0,head+.15),'neck')}
    for side, sign in [('L',1),('R',-1)]:
        elbow=(sign*(half+.12),-.04,shoulder-.43)
        hand=(sign*(half+.12),-.16,shoulder-.85)
        if book:
            elbow=(sign*(half+.10),-.02,shoulder-.42)
            hand=(sign*.14,-.26,shoulder-.28)
            if name=='SignatureMimicResidual' and sign<0:hand=(-half-.12,-.20,shoulder-.06)
            if name=='IdentityComparisonResidual' and sign<0:hand=(-.10,-.22,shoulder+.08)
        if row['boss']:
            hand=(sign*(half+.26),-.25,shoulder-.4)
        specs['upper_arm_'+side]=((sign*half,0,shoulder),elbow,'chest')
        specs['forearm_'+side]=(elbow,hand,'upper_arm_'+side)
        specs['hand_'+side]=(hand,(hand[0],hand[1]-.10,hand[2]-.10),'forearm_'+side)
        specs['thigh_'+side]=((sign*.19,0,hip-.12),(sign*.22,0,.65),'root')
        specs['shin_'+side]=((sign*.22,0,.65),(sign*.23,0,.15),'thigh_'+side)
        specs['foot_'+side]=((sign*.23,0,.15),(sign*.23,-.2,.07),'shin_'+side)
    return specs,head,shoulder,half

def equipment_regions(row, points, width, head):
    x,y,z=points.T;name=row['name'];regions=[]
    # Long staffs stay grounded. Their attached hand is held with a two-bone IK target.
    staffs={'ResponsibilityAuditAdministrator':(-1,.65),'SealMaintenanceAdministrator':(-1,.62),
            'FinalAuthorizationAdministrator':(1,.79)}
    if name in staffs:
        sign,threshold=staffs[name]
        regions.append(('equipment_staff',(sign*x>threshold)&(y<.28)&(z<head-.08),'root','L' if sign>0 else 'R'))
    if name in ['RejectionExecutionResidual','BackflowBlockerResidual','ExitReviewResidual']:
        threshold={'RejectionExecutionResidual':.66,'BackflowBlockerResidual':.60,'ExitReviewResidual':.46}[name]
        regions.append(('equipment_shield',(x>threshold)&(y<.14)&(z>.30)&(z<2.35),'hand_L',None))
    if name in ['ConsentCustodianResidual','IdentityComparisonResidual','SignatureMimicResidual']:
        regions.append(('equipment_book',(abs(x)<.25)&(y<-.18)&(z>1.76)&(z<2.24),'chest',None))
    if row['boss'] or name in ['QuarantineEnforcerResidual','BackflowBlockerResidual','OverloadResidual']:
        regions.append(('equipment_back',(y>.28)&(z>1.72),'chest',None))
    return [(n,m,p,side) for n,m,p,side in regions if np.count_nonzero(m)>30]

def create_rig(scene, mesh, row):
    points=np.array([v.co[:] for v in mesh.data.vertices]);width=np.ptp(points[:,0])
    specs,head,shoulder,half=anatomical_config(row,width)
    data=bpy.data.armatures.new(row['name']+'_Skeleton')
    rig=bpy.data.objects.new('ACTOR_'+row['name'],data);scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig;rig.select_set(True);mesh.select_set(False)
    bpy.ops.object.mode_set(mode='EDIT')
    for name,(h,t,parent) in specs.items():
        bone=data.edit_bones.new(name);bone.head=h;bone.tail=t
        if parent:bone.parent=data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    # Distance-to-segment weights with anatomical domains prevent robe/weapon influence
    # from an unrelated arm. Equal-position vertices receive identical weights across UV seams.
    names=list(specs);distances=[]
    for name,(h,t,parent) in specs.items():
        h=np.array(h);v=np.array(t)-h
        u=np.clip(np.sum((points-h)*v,axis=1)/np.dot(v,v),0,1)
        distances.append(np.linalg.norm(points-(h+u[:,None]*v),axis=1))
    d=np.array(distances).T
    x,y,z=points.T
    for i,name in enumerate(names):
        if any(v in name for v in ['arm','hand']):
            sign=1 if name.endswith('_L') else -1
            d[:,i]+=np.where(sign*x<half*.4,2.,0.)
            d[:,i]+=np.where((z<1.2)|(z>shoulder+.25),4.,0.)
        elif name in ['head','neck']:
            d[:,i]+=np.where((abs(x)>half*.8)|(y>.25),2.,0.)
        elif any(v in name for v in ['thigh','shin','foot']):
            d[:,i]+=np.where(z>1.15,4.,0.)
    nearest=np.argsort(d,axis=1)[:,:3]
    weights=1/np.maximum(np.take_along_axis(d,nearest,axis=1),.035)**4
    weights/=weights.sum(axis=1,keepdims=True)
    groups={n:mesh.vertex_groups.new(name=n) for n in names}
    for vi in range(len(points)):
        if z[vi]<.45:
            groups['root'].add([vi],1,'REPLACE');continue
        for ni,w in zip(nearest[vi],weights[vi]):
            if w>.001:groups[names[ni]].add([vi],float(w),'REPLACE')
    modifier=mesh.modifiers.new('FinalArticulatedSkin','ARMATURE');modifier.object=rig
    mesh.parent=rig
    return rig,equipment_regions(row,points,width,head),False

def add_equipment(scene,mesh,rig,regions,preserved):
    bpy.context.view_layer.objects.active=rig;rig.select_set(True);mesh.select_set(False)
    bpy.ops.object.mode_set(mode='EDIT')
    effective=[]
    for name,mask,parent,side in regions:
        indices=np.flatnonzero(mask).tolist()
        center=sum((mesh.data.vertices[i].co for i in indices),Vector())/len(indices)
        b=rig.data.edit_bones.new(name);b.head=center;b.tail=center+Vector((0,0,.15))
        parent_name=('mixamorig:Spine2' if parent=='chest' else 'mixamorig:Hips') if preserved else parent
        if parent_name in rig.data.edit_bones:b.parent=rig.data.edit_bones[parent_name]
        effective.append((name,indices,side))
    bpy.ops.object.mode_set(mode='OBJECT')
    for name,indices,side in effective:
        for group in mesh.vertex_groups:group.remove(indices)
        mesh.vertex_groups.new(name=name).add(indices,1.,'REPLACE')
        if side and not preserved:
            target=bpy.data.objects.new(row['name']+'_Grip_'+side,None);scene.collection.objects.link(target)
            target.parent=rig;target.location=rig.data.bones['hand_'+side].head_local
            constraint=rig.pose.bones['forearm_'+side].constraints.new('IK')
            constraint.target=target;constraint.chain_count=2;constraint.use_stretch=False
            rig.pose.bones['upper_arm_'+side].ik_stretch=0;rig.pose.bones['forearm_'+side].ik_stretch=0
    return [n for n,_,_ in effective]

def rotate_world(rig,name,angles):
    p=rig.pose.bones.get(name)
    if not p:return
    q=Quaternion()
    basis=p.bone.matrix_local.to_quaternion().inverted()
    for axis,angle in zip([(1,0,0),(0,1,0),(0,0,1)],angles):
        q=q@Quaternion(basis@Vector(axis),angle)
    p.rotation_quaternion=q

def animate(scene,rig,row,preserved):
    mix={'spine':'mixamorig:Spine','chest':'mixamorig:Spine2','head':'mixamorig:Head',
        'upper_arm_L':'mixamorig:LeftArm','upper_arm_R':'mixamorig:RightArm',
        'forearm_L':'mixamorig:LeftForeArm','forearm_R':'mixamorig:RightForeArm',
        'hand_L':'mixamorig:LeftHand','hand_R':'mixamorig:RightHand'}
    def turn(name,angles):rotate_world(rig,mix.get(name,name) if preserved else name,angles)
    for p in rig.pose.bones:p.rotation_mode='QUATERNION'
    cursor=1;ranges={}
    clips=[('idle',120),('appear',30),('telegraph',36),('attack',30),('heavyAttack',39),('special',60),('hit',24),('death',54)]
    for clip,length in clips:
        start=cursor;end=start+length
        ranges[clip]={'start':(start-1)/30,'end':(end-1)/30,'duration':length/30}
        if clip in ['attack','heavyAttack']:
            ranges[clip].update(impact=.62 if clip=='heavyAttack' else .46,settledAt=1.28 if clip=='heavyAttack' else .96)
        for frame in range(start,end+1):
            t=(frame-start)/length;seconds=(frame-start)/30
            for p in rig.pose.bones:p.rotation_quaternion=Quaternion();p.location=(0,0,0)
            if clip=='idle':
                cycle=math.sin(2*math.pi*t);soft=1-math.cos(2*math.pi*t)
                turn('spine',(.012*soft,0,.012*cycle));turn('chest',(.009*cycle,0,0))
                turn('head',(.012*soft,0,.035*cycle))
                turn('forearm_R',(.018*cycle,0,0));turn('hand_L',(0,.018*cycle,0))
            elif clip in ['attack','heavyAttack']:
                heavy=clip=='heavyAttack';impact=.62 if heavy else .46;settled=1.28 if heavy else .96
                pull_end=impact-(.17 if heavy else .13)
                release=smooth((seconds-pull_end)/(impact-pull_end))
                pull=smooth(seconds/pull_end)*(1-release)
                strike=release*(1-smooth((seconds-impact-.06)/(settled-impact-.06)))
                power=(1.2 if heavy else 1.)*(1. if args.final_motion else .45)
                book=any(n in row['name'] for n in ['Custodian','Mimic','Comparison'])
                floor=row['floor'];side='L' if row['name'] in ['ResponsibilityAuditAdministrator','SealMaintenanceAdministrator'] else 'R'
                turn('spine',(-.035*pull+.07*strike*power,0,.035*pull-.065*strike*power))
                turn('chest',(-.03*pull+.07*strike*power,0,.035*pull-.045*strike))
                turn('head',(-.025*pull+.04*strike,0,-.045*strike))
                amplitude=.20 if book else .42
                turn('upper_arm_'+side,(amplitude*(.6*pull-strike)*power, .12*strike*power, .06*pull))
                turn('forearm_'+side,((.20*pull-.32*strike)*power,0,0))
                turn('hand_'+side,(.10*strike*power,.06*strike,0))
                other='R' if side=='L' else 'L'
                turn('upper_arm_'+other,(-.08*strike*power,0,.03*strike))
                if floor==7:turn('chest',(.06*strike,0,.09*pull-.15*strike*power))
                if floor==6:turn('upper_arm_'+side,(.30*pull-.50*strike*power,0,0))
                if floor==5:turn('forearm_'+side,(-.18*strike,.12*pull-.25*strike*power,0))
            elif clip=='telegraph':
                wave=math.sin(math.pi*t);turn('head',(-.04*wave,0,.025*wave));turn('forearm_R',(.10*wave,0,0))
            elif clip=='special':
                wave=math.sin(math.pi*t);turn('head',(-.04*wave,0,.05*math.sin(2*math.pi*t)))
                turn('forearm_L',(-.15*wave,0,0));turn('hand_R',(0,.12*wave,0))
            elif clip=='appear':turn('spine',(-.06*(1-t),0,0))
            elif clip=='hit':
                recoil=math.sin(math.pi*t)*math.exp(-2*t)
                turn('spine',(-.12*recoil,0,-.04*recoil));turn('head',(.10*recoil,0,0))
            elif clip=='death':
                q=smooth((seconds-.12)/1.45);lag=smooth((seconds-.3)/1.45)
                turn('spine',(.23*q,0,.055*q));turn('chest',(.22*q,0,.045*q))
                turn('head',(.23*lag,0,.10*lag));turn('upper_arm_L',(.12*lag,0,.08*lag))
                turn('upper_arm_R',(.18*lag,0,-.08*lag));turn('forearm_L',(.10*lag,0,0));turn('forearm_R',(.15*lag,0,0))
            if args.final_motion:
                for p in rig.pose.bones:
                    if p.name=='equipment_back':
                        rotate_world(rig,p.name,(.012*math.sin(2*math.pi*t),0,.009*math.sin(2*math.pi*t)))
            for p in rig.pose.bones:
                p.keyframe_insert('rotation_quaternion',frame=frame)
                p.keyframe_insert('location',frame=frame)
        scene.timeline_markers.new(clip,frame=start)
        if 'impact' in ranges[clip]:scene.timeline_markers.new(clip+'_IMPACT',frame=round(start+ranges[clip]['impact']*30))
        cursor=end+3
    scene.frame_start=1;scene.frame_end=cursor-3;scene.frame_set(1)
    rig.animation_data.action.name=row['name']+'_FinalCombat'
    return ranges

reports=[]
for row in configs:
    scene=bpy.data.scenes.new('DA_ACTOR_'+row['name']);scene.use_fake_user=True
    bpy.context.window.scene=scene;scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=row['path']);bpy.context.view_layer.update()
    meshes=[o for o in scene.objects if o.type=='MESH' and len(o.data.vertices)>1000 and not o.hide_render]
    rigs=[o for o in scene.objects if o.type=='ARMATURE']
    pts=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)])
    center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    normal=Matrix.Scale(3/(hi.z-lo.z),4)@Matrix.Translation(-center)
    for obj in meshes+rigs:
        matrix=normal@obj.matrix_world;obj.parent=None;obj.matrix_world=matrix
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes+rigs:obj.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    mesh=meshes[0];mesh.name=row['name']+'_Skin'
    if rigs:
        rig=rigs[0];rig.name='ACTOR_'+row['name'];mesh.parent=rig
        points=np.array([v.co[:] for v in mesh.data.vertices])
        # The supplied rig has 35,653/38,633 vertices on Hips; its skin must be repaired.
        # Retain all 55 original joints and rebuild continuous anatomical weights.
        mesh.vertex_groups.clear()
        temp,_,_=create_rig(scene,mesh,row)
        mapping={'root':'Hips','pelvis':'Hips','spine':'Spine','chest':'Spine2','neck':'Neck','head':'Head',
            'upper_arm_L':'LeftArm','forearm_L':'LeftForeArm','hand_L':'LeftHand',
            'upper_arm_R':'RightArm','forearm_R':'RightForeArm','hand_R':'RightHand',
            'thigh_L':'LeftUpLeg','shin_L':'LeftLeg','foot_L':'LeftFoot',
            'thigh_R':'RightUpLeg','shin_R':'RightLeg','foot_R':'RightFoot'}
        assignments=[[(mapping[mesh.vertex_groups[g.group].name],g.weight) for g in v.groups] for v in mesh.data.vertices]
        mesh.vertex_groups.clear()
        groups={n:mesh.vertex_groups.new(name='mixamorig:'+n) for n in set(mapping.values())}
        for vi,weights in enumerate(assignments):
            total={}
            for n,w in weights:total[n]=total.get(n,0)+w
            for n,w in total.items():groups[n].add([vi],w,'REPLACE')
        for mod in list(mesh.modifiers):
            if mod.type=='ARMATURE' and mod.object==temp:mesh.modifiers.remove(mod)
        bpy.data.objects.remove(temp,do_unlink=True);rig.name='ACTOR_'+row['name'];mesh.parent=rig
        x,y,z=points.T
        regions=[('equipment_back',(abs(x)>.43)&(y>0)&(z>1.12),'chest',None)];preserved=True
    else:rig,regions,preserved=create_rig(scene,mesh,row)
    equipment=add_equipment(scene,mesh,rig,regions,preserved)
    ranges=animate(scene,rig,row,preserved)
    for mat in mesh.data.materials:
        if not mat or not mat.use_nodes:continue
        for n in mat.node_tree.nodes:
            if n.type=='TEX_IMAGE' and n.image and max(n.image.size)>2048:
                factor=2048/max(n.image.size);n.image.scale(round(n.image.size[0]*factor),round(n.image.size[1]*factor))
    dest=args.output/row['name'];dest.mkdir(exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);mesh.select_set(True)
    bpy.ops.wm.usd_export(filepath=str(dest/(row['asset']+'.usdc')),selected_objects_only=True,
        export_animation=True,export_armatures=True,export_materials=True,export_uvmaps=True,
        export_normals=True,generate_preview_surface=True,export_textures_mode='NEW',relative_paths=True,
        root_prim_path='/'+row['asset'],convert_scene_units='METERS',meters_per_unit=1.)
    (dest/'motion.json').write_text(json.dumps({'actor':row['name'],'fps':30,'clips':ranges,'rigVersion':2,
        'dissolveDuration':.65,'sourceRigPreserved':preserved,'rigidEquipment':equipment},indent=2))
    reports.append({'actor':row['name'],'bones':len(rig.data.bones),'preservedSourceRig':preserved,'repairedSourceWeights':preserved,
        'rigidEquipment':equipment,'source':row['path'],'finalMotion':args.final_motion})
    print('ACTOR_DONE',row['name'],flush=True)

# Pack edit-library textures while leaving source files unchanged.
for image in bpy.data.images:
    if image.type=='IMAGE' and image.size[0]:
        if max(image.size)>1024:
            factor=1024/max(image.size);image.scale(round(image.size[0]*factor),round(image.size[1]*factor))
        image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(args.output/'FinalActors_Rigged.blend'),compress=True)
(args.output/'actor-report.json').write_text(json.dumps(reports,indent=2))
print('ACTOR_LIBRARY_COMPLETE',flush=True)
