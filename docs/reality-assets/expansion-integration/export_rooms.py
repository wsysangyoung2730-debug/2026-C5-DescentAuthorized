"""Export latest authored 5–7F scenes with runtime interaction anchors, preserving source blend."""
import bpy, json, sys, argparse, re, runpy, math
from pathlib import Path
from mathutils import Vector
ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--tools',type=Path,required=True)
a=ap.parse_args(sys.argv[sys.argv.index('--')+1:]);a.output.mkdir(parents=True,exist_ok=True)
rooms=[(7,False,'CoordinateResidue','DA_F07A_CoordinateResidue'),(7,True,'CoordinateAdministrator','DA_F07_CoordinateAdministrator'),(6,False,'CausalityResidue','DA_F06A_ResultDelayResidue'),(6,True,'CausalityAdministrator','DA_F06B_CausalityAdministrator'),(5,False,'MemoryOmissionResidue','DA_F05A_MemoryOmissionResidue'),(5,True,'OriginalMemoryAdministrator','DA_F05B_OriginalMemoryAdministrator')]
def snake(s):return re.sub(r'(?<!^)(?=[A-Z])','_',s).lower()
def descendants(o):return [o]+[v for c in o.children for v in descendants(c)]
# One reusable scroll resource; the room files contain only empty placement anchors.
s=bpy.data.scenes['DA_F09_Archive_Redesign'];bpy.context.window.scene=s;s.frame_set(66)
scroll=bpy.data.objects.get('F09_RewardScroll_Center_Idle')
if scroll:
 members=descendants(scroll);bpy.ops.object.select_all(action='DESELECT')
 for o in members:o.hide_set(False);o.hide_viewport=False;o.hide_render=False;o.select_set(True)
 dest=a.output/'RewardScroll';dest.mkdir(exist_ok=True)
 bpy.ops.wm.usd_export(filepath=str(dest/'reward_scroll.usdc'),selected_objects_only=True,export_animation=False,export_materials=True,export_uvmaps=True,export_normals=True,export_textures_mode='NEW',relative_paths=True,root_prim_path='/reward_scroll',convert_scene_units='METERS',meters_per_unit=1.0)
# Convert shared procedural surfaces to portable PBR, retaining imported prop UVs.
ns=runpy.run_path(str(a.tools/'repair_portable_surfaces.py'))
fn=ns['repair'];fn.__globals__['SCENES']=[room[3] for room in rooms];fn.__globals__['SIZE']=1024
surface=a.output/'baked-surfaces';surface.mkdir(exist_ok=True);fn.__globals__['OUT']=surface
fn()
report=[]
for floor,boss,name,sceneName in rooms:
 scene=bpy.data.scenes[sceneName];bpy.context.window.scene=scene;scene.frame_set(1)
 prefix=f'F0{floor}'+('B' if boss else 'A');asset=f'floor0{floor}_'+snake(name);dest=a.output/name;dest.mkdir(exist_ok=True)
 if boss:
  for slot in ['Left','Center','Right']:
   anchorName=f'ANCHOR_F0{floor}_RewardSlot_{slot}'
   anchor=scene.objects.get(anchorName)
   if not anchor:
    idle=next((o for o in scene.objects if o.name.endswith(f'RewardScroll_{slot}_Idle')),None)
    assert idle, (sceneName,slot)
    anchor=bpy.data.objects.new(anchorName,None);scene.collection.objects.link(anchor)
    anchor.matrix_world=idle.matrix_world.copy();anchor.rotation_euler=(0,0,0);anchor.scale=(1,1,1)
  remove=[o for o in list(scene.objects) if 'RewardScroll_' in o.name]
  for o in remove:bpy.data.objects.remove(o,do_unlink=True)
 # Select actual geometry and only required cameras; hidden helper stages never exported.
 bpy.ops.object.select_all(action='DESELECT')
 cams=([f'F0{floor}_iPad_MainCamera',f'CAM_F0{floor}_RewardSelection',f'CAM_F0{floor}_DescentDoor'] if boss else [f'F0{floor}A_iPadCamera' if floor!=5 else 'F05A_iPad_MainCamera',f'CAM_F0{floor}A_BossAccessDoor' if floor!=5 else 'CAM_F05A_BossAccess'])
 selected=[]
 for o in scene.objects:
  if o.type=='CAMERA' and o.name not in cams:continue
  if o.type=='LIGHT':continue # Captured environment + bounded runtime spots.
  if o.hide_render:continue
  o.hide_set(False);o.hide_viewport=False;o.select_set(True);selected.append(o.name)
  if o.type=='CAMERA':o.data.name=o.name
  if o.type=='MESH':
   for mat in o.data.materials:
    if mat and mat.use_nodes:
     for n in mat.node_tree.nodes:
      if n.type=='TEX_IMAGE' and n.image and max(n.image.size)>2048:
       im=n.image;ratio=2048/max(im.size);im.scale(round(im.size[0]*ratio),round(im.size[1]*ratio))
 for cam in cams:assert cam in selected,(sceneName,cam)
 bpy.ops.wm.usd_export(filepath=str(dest/(asset+'.usdc')),selected_objects_only=True,export_animation=False,export_uvmaps=True,export_normals=True,export_materials=True,generate_preview_surface=True,export_textures_mode='NEW',overwrite_textures=True,relative_paths=True,export_lights=False,export_cameras=True,use_instancing=False,root_prim_path='/'+asset,convert_scene_units='METERS',meters_per_unit=1.0)
 report.append({'scene':sceneName,'asset':asset,'floor':floor,'boss':boss,'cameras':cams,'objects':len(selected),'source':bpy.data.filepath})
 print('ROOM_DONE',asset,flush=True)
 # Render low resolution reflection panorama from the room's occupied area.
 oldcam=scene.camera
 data=bpy.data.cameras.new('ExpansionReflectionCapture');data.type='PANO';data.panorama_type='EQUIRECTANGULAR'
 camera=bpy.data.objects.new('ExpansionReflectionCapture',data);scene.collection.objects.link(camera);camera.location=(0,3,3);camera.rotation_euler=(math.pi/2,0,0);scene.camera=camera
 scene.render.engine='CYCLES';scene.cycles.samples=8;scene.cycles.use_denoising=True
 scene.render.resolution_x=512;scene.render.resolution_y=256;scene.render.resolution_percentage=100
 scene.render.image_settings.file_format='HDR';scene.render.filepath=str(dest/'environment.hdr')
 bpy.ops.render.render(write_still=True);scene.camera=oldcam;bpy.data.objects.remove(camera,do_unlink=True)
(a.output/'room-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
