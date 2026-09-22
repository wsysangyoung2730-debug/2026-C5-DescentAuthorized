"""Blender: import supplied GLBs, add grounded deformation rigs and readable combat motion ranges.
Usage: blender -b --python build_actors.py -- --inventory paths.txt --output directory
The supplied source models are never modified.
"""
import bpy, math, json, argparse, sys, re, unicodedata
from pathlib import Path
from mathutils import Vector
ap=argparse.ArgumentParser();ap.add_argument('--inventory',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--legacy',action='store_true');ap.add_argument('--all',action='store_true',help='Export all nine actors in one library')
a=ap.parse_args(sys.argv[sys.argv.index('--')+1:]);a.output.mkdir(parents=True,exist_ok=True)
configs=[(7,False,'CoordinateResidue'),(7,True,'CoordinateAdministrator'),(6,False,'CausalityResidue'),(6,True,'CausalityAdministrator'),(5,False,'MemoryOmissionResidue'),(5,True,'OriginalMemoryAdministrator')]
legacy_configs=[(9,True,'RecordAdministrator'),(8,False,'ObservationResidue'),(8,True,'ObservationAdministrator')]
if a.all: configs+=legacy_configs
elif a.legacy: configs=legacy_configs
paths=[Path(p) for p in a.inventory.read_text().splitlines() if p.endswith('.glb')]
reports=[]
for floor,boss,name in configs:
 legacy=floor>=8
 clips=[('idle',120 if legacy else 60),('appear',30),('telegraph',36),('attack',30),('heavyAttack',39),('special',60),('hit',24),('death',54)]
 source=next(p for p in paths if unicodedata.normalize('NFC',p.name).startswith(str(floor)+'층') and ('관리자' in unicodedata.normalize('NFC',p.name))==boss)
 scene=bpy.data.scenes.new('DA_ACTOR_'+name);bpy.context.window.scene=scene
 scene.use_fake_user=True;scene.render.fps=30;scene.unit_settings.scale_length=1
 bpy.ops.import_scene.gltf(filepath=str(source))
 meshes=[o for o in scene.objects if o.type=='MESH']
 bpy.ops.object.select_all(action='DESELECT')
 for o in meshes:o.select_set(True)
 bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();mesh=bpy.context.object
 # Flatten imported transform into vertices, normalize to 3 m, facing -Y.
 matrix=mesh.matrix_world.copy()
 for v in mesh.data.vertices:v.co=matrix@v.co
 mesh.parent=None;mesh.matrix_world.identity()
 points=[v.co for v in mesh.data.vertices];lo=Vector([min(v[i] for v in points) for i in range(3)]);hi=Vector([max(v[i] for v in points) for i in range(3)])
 scale=3/(hi.z-lo.z);center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for v in mesh.data.vertices:v.co=(v.co-center)*scale
 width=(hi.x-lo.x)*scale
 mesh.name=name+'_Skin';mesh.data.name=mesh.name
 rigdata=bpy.data.armatures.new(name+'_Skeleton');rig=bpy.data.objects.new('ACTOR_'+name,rigdata);scene.collection.objects.link(rig)
 bpy.context.view_layer.objects.active=rig;rig.select_set(True);mesh.select_set(False);bpy.ops.object.mode_set(mode='EDIT')
 # Keep the pedestal/feet stable. Body, head and both arms have independent joints.
 specs={'root':((0,0,0),(0,0,.65),None),'spine':((0,0,1.1),(0,0,2.0),'root'),'head':((0,0,2.1),(0,0,2.8),'spine')}
 for side,sign in [('L',1),('R',-1)]:
  x=sign*width*.22; specs['arm_'+side]=((x,0,1.9),(sign*width*.37,0,1.25),'spine')
 for n,(h,t,parent) in specs.items():
  b=rigdata.edit_bones.new(n);b.head=h;b.tail=t
  if parent:b.parent=rigdata.edit_bones[parent]
 bpy.ops.object.mode_set(mode='OBJECT')
 groups={n:mesh.vertex_groups.new(name=n) for n in specs}
 def smooth(v):v=max(0,min(1,v));return v*v*(3-2*v)
 for v in mesh.data.vertices:
  x,y,z=v.co
  arm=smooth((abs(x)/max(width,.01)-.18)/.14)*smooth((z-.8)/.35)*(1-smooth((z-2.25)/.35))
  head=smooth((z-2.05)/.35)*(1-arm)
  spine=smooth((z-.7)/.5)*(1-arm-head)
  weights={'arm_L' if x>0 else 'arm_R':arm,'head':head,'spine':spine,'root':1-arm-head-spine}
  for n,w in weights.items():
   if w>.00001:groups[n].add([v.index],w,'REPLACE')
 mod=mesh.modifiers.new('AuthoredDeformation','ARMATURE');mod.object=rig;mesh.parent=rig
 for p in rig.pose.bones:p.rotation_mode='XYZ'
 cursor=1;ranges={};motion_checks={}
 for clip,length in clips:
  start=cursor;end=start+length;ranges[clip]={'start':(start-1)/30,'end':(end-1)/30,'duration':length/30}
  # Impact keys share the runtime's damage moment. Dense combat keys retain the
  # short strike and grounded collapse through USD's 30 fps export sampling.
  changed=clip in ('attack','heavyAttack','death')
  bpy.context.preferences.edit.keyframe_new_interpolation_type='LINEAR' if changed else 'BEZIER'
  frames=set(range(start,end+1,1 if changed else 3))
  if clip in ('attack','heavyAttack'):
   impact=.62 if clip=='heavyAttack' else .46
   ranges[clip]['impact']=impact
   ranges[clip]['settledAt']=1.28 if clip=='heavyAttack' else .96
   frames.add(start+impact*30)
  for frame in sorted(frames):
   t=(frame-start)/length;wave=math.sin(math.pi*t);cycle=math.sin(2*math.pi*t)
   for p in rig.pose.bones:p.rotation_euler=(0,0,0);p.location=(0,0,0);p.scale=(1,1,1)
   root=rig.pose.bones['root'];spine=rig.pose.bones['spine'];head=rig.pose.bones['head'];left=rig.pose.bones['arm_L'];right=rig.pose.bones['arm_R']
   strength=.8 if boss else 1
   if clip=='idle':
    spine.rotation_euler.y=.018*cycle;head.rotation_euler.z=.025*cycle
    left.rotation_euler.x=.025*cycle;right.rotation_euler.x=-.02*cycle
    if floor==5 and not boss:root.location.y=.025*math.sin(math.pi*t)**2
    if legacy:
     # Grounded administrators shift weight without lifting their feet.
     spine.rotation_euler.x=.012*(1-math.cos(2*math.pi*t))
     head.rotation_euler.z=.035*math.sin(2*math.pi*t)
     left.rotation_euler.x=.035*math.sin(2*math.pi*t+.5)-.035*math.sin(.5)
     right.rotation_euler.x=.025*math.sin(2*math.pi*t-.6)+.025*math.sin(.6)
     if not boss:root.location.y=.035*(1-math.cos(2*math.pi*t))
   elif clip=='appear':
    spine.rotation_euler.x=-.10*(1-t);left.rotation_euler.y=.10*wave;right.rotation_euler.y=-.10*wave
   elif clip=='telegraph':
    head.rotation_euler.x=-.06*wave;right.rotation_euler.x=.18*wave;spine.rotation_euler.x=-.045*wave
   elif clip in ('attack','heavyAttack'):
    # Distinct wind-up, quick release at damage time, then a complete recovery.
    seconds=(frame-start)/30;heavy=clip=='heavyAttack'
    impact=.62 if heavy else .46;settled=1.28 if heavy else .96
    windup_end=impact-(.17 if heavy else .13)
    release=smooth((seconds-windup_end)/(impact-windup_end))
    pull=smooth(seconds/windup_end)*(1-release)
    strike=release*(1-smooth((seconds-impact-.07)/(settled-impact-.07)))
    power=1.24 if heavy else 1
    spine.rotation_euler.x=-.18*pull+.26*strike*power
    head.rotation_euler.x=-.12*pull+.12*strike
    right.rotation_euler.x=.52*pull-.96*strike*power
    left.rotation_euler.x=.30*pull-.44*strike*power
    if floor==9:  # Long blade: shoulder draw, forward thrust, counterbalancing arm.
     right.rotation_euler.y=-.22*pull+.38*strike*power
     right.rotation_euler.z=.16*pull-.16*strike
     spine.rotation_euler.z=-.13*pull+.18*strike
     left.rotation_euler.x=.15*pull-.28*strike
    elif floor==8 and boss:  # Aim the cannon, then recoil from its firing pose.
     aim=smooth(seconds/max(.1,windup_end*.7))*(1-smooth((seconds-impact-.13)/(settled-impact-.13)))
     recoil=smooth((seconds-impact)/.065)*(1-smooth((seconds-impact-.065)/.23))
     left.rotation_euler.x=-.62*aim+.28*recoil*power
     right.rotation_euler.x=-.70*aim+.36*recoil*power
     right.rotation_euler.y=.16*aim;left.rotation_euler.y=-.12*aim
     spine.rotation_euler.x=.06*aim-.32*recoil*power
     head.rotation_euler.x=-.14*recoil
    elif floor==8:  # Talons cross the body with a broad asymmetric rake.
     left.rotation_euler.x=.38*pull-.83*strike*power
     left.rotation_euler.y=-.35*pull+.66*strike*power
     right.rotation_euler.y=.30*pull-.72*strike*power
     spine.rotation_euler.z=.18*pull-.34*strike
    elif floor==7:  # Diagonal strike follows the drifting coordinate silhouette.
     right.rotation_euler.y=-.24*pull+.46*strike*power
     right.rotation_euler.z=.25*pull-.40*strike
     left.rotation_euler.z=.28*strike
     spine.rotation_euler.z=.16*pull-.29*strike
    elif floor==6:  # Lift and hold; the last short release stamps down sharply.
     right.rotation_euler.x=.76*pull-1.04*strike*power
     left.rotation_euler.x=.66*pull-.88*strike*power
     spine.rotation_euler.x=-.23*pull+.39*strike*power
     head.rotation_euler.x=-.15*pull+.23*strike
    elif floor==5:  # The pedestal stays rooted while both arms sweep across it.
     right.rotation_euler.x=.38*pull-.60*strike*power
     right.rotation_euler.y=-.38*pull+.92*strike*power
     left.rotation_euler.y=.22*pull-.62*strike*power
     spine.rotation_euler.z=.18*pull-.31*strike
   elif clip=='special':
    left.rotation_euler.y=.14*wave;right.rotation_euler.y=-.14*wave;head.rotation_euler.z=.06*cycle
   elif clip=='hit':
    recoil=math.sin(math.pi*t)*math.exp(-2*t);spine.rotation_euler.x=-.18*recoil;head.rotation_euler.x=.1*recoil
   elif clip=='death':
    # A brief loss of support gives way to a deep, persistent slump. Rooted
    # administrators retain their feet/pedestal; residues also roll and fold.
    seconds=(frame-start)/30
    q=smooth((seconds-.12)/1.26);sag=smooth((seconds-.28)/1.25)
    spine.rotation_euler.x=(1.05 if boss else 1.16)*q
    spine.rotation_euler.z=(.10 if boss else -.20)*q
    head.rotation_euler.x=.48*sag;head.rotation_euler.z=.16*sag
    left.rotation_euler.x=.56*sag;right.rotation_euler.x=.68*sag
    left.rotation_euler.y=-.48*sag;right.rotation_euler.y=.52*sag
    left.rotation_euler.z=.18*sag;right.rotation_euler.z=-.22*sag
    if not boss:
     root.rotation_euler.x=.24*q;root.rotation_euler.z=-.12*q
     root.location.y=-.18*q
     # Local root Y is world Z. Correct only ground penetration, retaining the
     # residue's tilted collapse without pushing its lowest vertices below 0.
     bpy.context.view_layer.update()
     evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
     lowest=min((evaluated.matrix_world@v.co).z for v in evaluated.data.vertices)
     if lowest<0:root.location.y-=lowest
   for p in rig.pose.bones:
    p.keyframe_insert('rotation_euler',frame=frame);p.keyframe_insert('location',frame=frame)
  if clip in ('attack','heavyAttack','death'):
   check_frame=end if clip=='death' else start+ranges[clip]['impact']*30
   scene.frame_set(int(check_frame),subframe=check_frame-int(check_frame))
   bpy.context.view_layer.update()
   evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
   vertices=[evaluated.matrix_world@v.co for v in evaluated.data.vertices]
   motion_checks[clip]={'frame':check_frame,'minZ':min(v.z for v in vertices),'maxZ':max(v.z for v in vertices),'spineRadians':list(spine.rotation_euler),'rootTranslation':list(root.location)}
   assert motion_checks[clip]['minZ']>=-.035,(name,clip,'ground penetration',motion_checks[clip])
  scene.timeline_markers.new(clip,frame=start)
  if 'impact' in ranges[clip]:scene.timeline_markers.new(clip+'_IMPACT',frame=round(start+ranges[clip]['impact']*30))
  cursor=end+3
 rig.animation_data.action.name=name+'_CombatMotions';scene.frame_start=1;scene.frame_end=cursor-3;scene.frame_set(1)
 asset=re.sub(r'(?<!^)(?=[A-Z])','_',name).lower();dest=a.output/name;dest.mkdir(exist_ok=True)
 # Importers must not depend on unsupported Principled socket graphs.
 for mat in mesh.data.materials:
  if mat and mat.use_nodes:
   for node in mat.node_tree.nodes:
    if node.type=='TEX_IMAGE' and node.image and max(node.image.size)>2048:
     im=node.image;ratio=2048/max(im.size);im.scale(round(im.size[0]*ratio),round(im.size[1]*ratio))
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);mesh.select_set(True)
 bpy.ops.wm.usd_export(filepath=str(dest/(asset+'.usdc')),selected_objects_only=True,export_animation=True,export_armatures=True,export_materials=True,export_uvmaps=True,export_normals=True,generate_preview_surface=True,export_textures_mode='NEW',relative_paths=True,root_prim_path='/'+asset,convert_scene_units='METERS',meters_per_unit=1.0)
 (dest/'motion.json').write_text(json.dumps({'fps':30,'clips':ranges,'actor':name},indent=2))
 reports.append({'name':name,'floor':floor,'boss':boss,'source':str(source),'vertices':len(mesh.data.vertices),'triangles':sum(len(p.vertices)-2 for p in mesh.data.polygons),'bones':len(rig.pose.bones),'clips':ranges,'motionChecks':motion_checks})
 print('ACTOR_DONE',name,flush=True)
# A standalone editable rig library, no environment duplication.
(a.output/'actor-report.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2))
# Pack modest source-preview textures only after the full-quality USD export.
# This keeps the editable nine-actor library below repository file limits.
source_textures=a.output/'source-preview-textures';source_textures.mkdir(exist_ok=True)
for index,im in enumerate(bpy.data.images):
 if im.type!='IMAGE' or im.source not in ('FILE','GENERATED') or not im.size[0]:continue
 if max(im.size)>1024:
  ratio=1024/max(im.size);im.scale(round(im.size[0]*ratio),round(im.size[1]*ratio))
 im.filepath_raw=str(source_textures/(str(index)+'.png'));im.file_format='PNG';im.save()
 if im.packed_file:im.unpack(method='REMOVE')
 im.pack()
 im.filepath='//source-preview-textures/'+str(index)+'.png'
bpy.ops.wm.save_as_mainfile(filepath=str(a.output/'ExpansionActors_Rigged.blend'),compress=True)
