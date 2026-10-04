"""Convert supplied GLBs to centered Z-up, one-meter USD effects. Run in Blender.
Source meshes remain unchanged; textures are resized for transient mobile VFX.
"""
import bpy, sys, argparse, json, hashlib
from pathlib import Path
from mathutils import Vector
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--preview',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);a.output.mkdir(parents=True,exist_ok=True);a.preview.mkdir(parents=True,exist_ok=True)
report=[]
for src in sorted(a.source.glob('*.glb')):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(src))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
 bpy.ops.object.select_all(action='DESELECT')
 for o in meshes:o.select_set(True)
 bpy.context.view_layer.objects.active=meshes[0]
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 verts=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
 lo=Vector([min(v[i] for v in verts) for i in range(3)]);hi=Vector([max(v[i] for v in verts) for i in range(3)])
 center=(lo+hi)/2;size=hi-lo;scale=1/max(size)
 for o in meshes:
  for v in o.data.vertices:v.co=(o.matrix_world@v.co-center)*scale
  o.matrix_world.identity();o.name='FX_'+src.stem.replace('-','_')
 for o in list(bpy.context.scene.objects):
  if o.type!='MESH':bpy.data.objects.remove(o,do_unlink=True)
 folder=a.output/src.stem;folder.mkdir(parents=True,exist_ok=True)
 textures=[]
 for image in bpy.data.images:
  if image.size[0]==0:continue
  original=list(image.size);limit=1024
  if max(image.size)>limit:image.scale(round(image.size[0]*limit/max(image.size)),round(image.size[1]*limit/max(image.size)))
  image.pack();textures.append({'name':image.name,'original':original,'size':list(image.size)})
 bpy.ops.wm.usd_export(filepath=str(folder/'effect.usdc'),export_animation=False,export_materials=True,export_textures_mode='NEW',export_uvmaps=True,export_normals=True,generate_preview_surface=True,convert_scene_units='METERS',meters_per_unit=1.0,relative_paths=True)
 for o in meshes:o.data.calc_loop_triangles()
 row={'id':src.stem,'sourceSHA256':hashlib.sha256(src.read_bytes()).hexdigest(),'sourceBytes':src.stat().st_size,'sourceBounds':list(size),'normalizedBounds':list(size*scale),'triangles':sum(len(o.data.loop_triangles) for o in meshes),'textures':textures,'meshes':len(meshes)}
 report.append(row)
 # Render the imported geometry rather than the reference PNG.
 sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=12;sc.render.resolution_x=450;sc.render.resolution_y=450;sc.render.resolution_percentage=100
 sc.world=bpy.data.worlds.new('World');sc.world.use_nodes=True;sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.11,.13,.17,1);sc.world.node_tree.nodes['Background'].inputs[1].default_value=.5
 sc.view_settings.view_transform='AgX'
 def point(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.camera_add(location=(1.05,-1.9,.8));cam=bpy.context.object;point(cam,(0,0,0));cam.data.type='ORTHO';cam.data.ortho_scale=1.3;sc.camera=cam
 for pos,power,size in [((1,-2,3),280,3),((-2,-1,1),200,2),((1,2,2),350,2)]:
  bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;point(light,(0,0,0))
 sc.render.filepath=str(a.preview/(src.stem+'.png'));bpy.ops.render.render(write_still=True)
 print('CONVERTED',src.stem,flush=True)
(a.output/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
