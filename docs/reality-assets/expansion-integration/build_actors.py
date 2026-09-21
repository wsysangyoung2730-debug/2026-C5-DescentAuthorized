"""Blender: import supplied GLBs, add conservative deformation rigs and named motion ranges.
Usage: blender -b --python build_actors.py -- --inventory paths.txt --output directory
The supplied source models are never modified.
"""
import bpy, math, json, argparse, sys, re, unicodedata
from pathlib import Path
from mathutils import Vector
ap=argparse.ArgumentParser();ap.add_argument('--inventory',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--legacy',action='store_true')
a=ap.parse_args(sys.argv[sys.argv.index('--')+1:]);a.output.mkdir(parents=True,exist_ok=True)
configs=[(7,False,'CoordinateResidue'),(7,True,'CoordinateAdministrator'),(6,False,'CausalityResidue'),(6,True,'CausalityAdministrator'),(5,False,'MemoryOmissionResidue'),(5,True,'OriginalMemoryAdministrator')]
if a.legacy: configs=[(9,True,'RecordAdministrator'),(8,False,'ObservationResidue'),(8,True,'ObservationAdministrator')]
paths=[Path(p) for p in a.inventory.read_text().splitlines() if p.endswith('.glb')]
clips=[('idle',120 if a.legacy else 60),('appear',30),('telegraph',36),('attack',30),('heavyAttack',48),('special',60),('hit',24),('death',54)]
reports=[]
for floor,boss,name in configs:
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
 cursor=1;ranges={}
 for clip,length in clips:
  start=cursor;end=start+length;ranges[clip]={'start':(start-1)/30,'end':(end-1)/30,'duration':length/30}
  # Key every few frames to preserve deliberate holds (6F) and drifting recovery (7F).
  for frame in range(start,end+1,3):
   t=(frame-start)/length;wave=math.sin(math.pi*t);cycle=math.sin(2*math.pi*t)
   for p in rig.pose.bones:p.rotation_euler=(0,0,0);p.location=(0,0,0);p.scale=(1,1,1)
   root=rig.pose.bones['root'];spine=rig.pose.bones['spine'];head=rig.pose.bones['head'];left=rig.pose.bones['arm_L'];right=rig.pose.bones['arm_R']
   strength=.8 if boss else 1
   if clip=='idle':
    spine.rotation_euler.y=.018*cycle;head.rotation_euler.z=.025*cycle
    left.rotation_euler.x=.025*cycle;right.rotation_euler.x=-.02*cycle
    if floor==5 and not boss:root.location.y=.025*math.sin(math.pi*t)**2
    if a.legacy:
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
    # 6F pauses in anticipation, then stamps down; 7F thrusts diagonally; 5F sweeps.
    u=0 if floor==6 and t<.3 else (t-.3)/.7 if floor==6 else t
    punch=math.sin(math.pi*u)**2
    amount=.32 if clip=='heavyAttack' else .19
    right.rotation_euler.x=-amount*punch*strength;left.rotation_euler.x=-amount*.55*punch
    spine.rotation_euler.x=.065*punch
    if floor==7:spine.rotation_euler.z=-.07*punch
    if floor==5:right.rotation_euler.y=.13*punch
    if a.legacy:
     if floor==9:
      spine.rotation_euler.z=.045*punch
      right.rotation_euler.y=.12*punch
     elif boss:
      left.rotation_euler.x=-.16*punch
      spine.rotation_euler.x=-.045*punch
     else:
      left.rotation_euler.y=.12*punch
      right.rotation_euler.y=-.12*punch
   elif clip=='special':
    left.rotation_euler.y=.14*wave;right.rotation_euler.y=-.14*wave;head.rotation_euler.z=.06*cycle
   elif clip=='hit':
    recoil=math.sin(math.pi*t)*math.exp(-2*t);spine.rotation_euler.x=-.18*recoil;head.rotation_euler.x=.1*recoil
   elif clip=='death':
    q=smooth(t);spine.rotation_euler.x=.32*q;head.rotation_euler.x=.2*q
    left.rotation_euler.y=-.17*q;right.rotation_euler.y=.17*q;root.location.y=-.12*q
   for p in rig.pose.bones:
    p.keyframe_insert('rotation_euler',frame=frame);p.keyframe_insert('location',frame=frame)
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
 reports.append({'name':name,'floor':floor,'boss':boss,'source':str(source),'vertices':len(mesh.data.vertices),'triangles':sum(len(p.vertices)-2 for p in mesh.data.polygons),'bones':len(rig.pose.bones),'clips':ranges})
 print('ACTOR_DONE',name,flush=True)
# A standalone editable rig library, no environment duplication.
(a.output/'actor-report.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(a.output/'ExpansionActors_Rigged.blend'))
