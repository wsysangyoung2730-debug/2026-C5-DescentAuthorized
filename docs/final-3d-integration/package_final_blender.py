"""Offline only: pack seven editable floor copies with animated actor previews and moving doors."""
import bpy,json,sys,argparse,hashlib
from pathlib import Path
from mathutils import Matrix,Vector
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--raw',type=Path,required=True);p.add_argument('--doors',type=Path,required=True);a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parent
rows=json.loads((root/'room-contracts.json').read_text());manifest=json.loads((root.parents[1]/'DescentAuthorized/Resources/Reality/FinalSceneManifest.json').read_text());reports=[]
for floor in range(1,8):
 bpy.ops.wm.open_mainfile(filepath=str(a.raw/f'Floor{floor:02d}_Final.blend'))
 library=root/'authoring'/('Floors21_FinalActors.blend' if floor<=2 else 'Floors43_FinalActors.blend' if floor<=4 else 'Floors75_FinalActors.blend')
 floorrows=[r for r in rows if r['floor']==floor]
 with bpy.data.libraries.load(str(library),link=False) as (src,dst):dst.scenes=['DA_ACTOR_'+r['name'] for r in floorrows]
 for r in floorrows:
  scene=bpy.data.scenes[r['scene']];bpy.context.window.scene=scene
  actor_scene=bpy.data.scenes['DA_ACTOR_'+r['name']];actor_scene.frame_set(1);objects=list(actor_scene.objects)
  container=bpy.data.objects.new('RuntimePreview_'+r['name'],None);scene.collection.objects.link(container);container['runtime_actor_preview']=True
  spawn=scene.objects[r['anchors']['enemySpawn']]
  for o in objects:
   if o.type not in {'MESH','ARMATURE','EMPTY'}:continue
   scene.collection.objects.link(o)
   if o.parent is None:o.parent=container
   o['runtime_actor_preview']=True
  # Same height and center normalization as the runtime loader.
  points=[o.matrix_world@Vector(c)for o in objects if o.type=='MESH' and not o.hide_render and len(o.data.vertices)>1000 for c in o.bound_box]
  lo=Vector([min(v[i]for v in points)for i in range(3)]);hi=Vector([max(v[i]for v in points)for i in range(3)])
  center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));scale=r['targetHeight']/(hi.z-lo.z)
  container.matrix_world=spawn.matrix_world@Matrix.Scale(scale,4)@Matrix.Translation(-center)
  scene.frame_start=1;scene.frame_end=actor_scene.frame_end;scene.render.fps=30;scene.frame_set(1)
  bpy.data.scenes.remove(actor_scene)
  scene.camera=scene.objects[r['cameras']['battle']]
  if r['role']=='administrator':
   m=next(x for x in manifest if x['resource']==r['resource']);gate=scene.objects.get(m['anchors']['descentDoor'])
   if gate:
    for o in [gate]+list(gate.children_recursive):bpy.data.objects.remove(o,do_unlink=True)
   bpy.ops.wm.usd_import(filepath=str(a.doors/f'Floor{floor:02d}_Door.usdc'),import_cameras=False,import_lights=False)
   # Door motion remains separate from the actor timeline; keyed 1=closed, 61=open.
   for suffix,sign in [('LeftPanel',-1),('RightPanel',1)]:
    leaf=bpy.data.objects.get(m['doorAnimationPrefix']+'_Door_'+suffix)
    if leaf:
     leaf.location.x=0;leaf.keyframe_insert(data_path='location',frame=1)
     leaf.location.x=sign*m['doorTravel'];leaf.keyframe_insert(data_path='location',frame=61)
     action=leaf.animation_data.action;action.name=leaf.name+'_Open';action.use_fake_user=True
     leaf.animation_data.action=None
     leaf.location.x=0
  scene.frame_set(1)
 for image in bpy.data.images:
  if image.source=='FILE' and not image.packed_file:
   try:image.pack()
   except RuntimeError as e:raise RuntimeError(f'Missing texture: {image.filepath}')from e
 bpy.ops.file.pack_all()
 destination=a.output/f'Floor{floor:02d}_Final_Animated.blend'
 bpy.context.window.scene=bpy.data.scenes[floorrows[0]['scene']]
 bpy.ops.wm.save_as_mainfile(filepath=str(destination),compress=True)
 external=[im.filepath for im in bpy.data.images if im.source=='FILE' and not im.packed_file]
 assert not external,external
 reports.append({'floor':floor,'file':str(destination),'bytes':destination.stat().st_size,'sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),'rooms':[r['scene']for r in floorrows],'packedTextures':sum(bool(im.packed_file)for im in bpy.data.images),'runtimePreviewExcludedFromExport':True})
 print('PACKAGED_FLOOR',floor,flush=True)
(a.output/'blender-delivery.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2))
