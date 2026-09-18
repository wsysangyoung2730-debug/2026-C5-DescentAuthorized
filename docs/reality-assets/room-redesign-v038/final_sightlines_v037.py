import bpy,math
from mathutils import Vector
from pathlib import Path
OUT=Path(bpy.data.filepath).parent
# The reward camera must frame the fully emerged scrolls (frame 66).
for p in ['F06','F07']:
 cam=bpy.data.objects['CAM_'+p+'_RewardSelection'];cam.data=cam.data.copy();cam.data.lens=26
 cam.location.z=2.6;cam.rotation_euler=(Vector((-7.2,2.3,1.95))-cam.location).to_track_quat('-Z','Y').to_euler()
# Stop the 7F galleries ahead of the descent approach.
for o in bpy.data.collections['F07B_Redesign'].objects:
 if any(k in o.name for k in ['GalleryDeck','GalleryFascia','GalleryHandrail','GalleryMidRail']):o.location.y=2;o.dimensions.y=10
 if any(k in o.name for k in ['GalleryRailPost','GallerySupport','GalleryBrace','GalleryCollar','MastBase']) and o.location.y>7:o.hide_render=True;o.hide_viewport=True
# Relocate obstructing props rather than omit them.
o=bpy.data.objects['ControlConsole_R_02'];o.location=(10.15,10.4,0);o.rotation_euler.z=-math.pi/2
# Keep data pillars separated along the right wall.
bpy.data.objects['DataPillar_1'].location=(10.5,.1,0)
o=bpy.data.objects['DeskTerminal_R03'];o.location=(9.8,4.6,.008);o.rotation_euler.z=-math.pi/2
for sign in [-1,1]:
 o=bpy.data.objects['F06B_SideArchive_'+str(sign)];o.location=(sign*8.4,-3.2,0);o.rotation_euler.z=-sign*math.radians(66)
# Preserve a clear inspection state in all scenes.
for s in bpy.data.scenes:
 if s.name.startswith('DA_F'):
  bpy.context.window.scene=s;s.frame_set(1);bpy.context.view_layer.update()
bpy.context.window.scene=bpy.data.scenes['DA_F08_AdministratorObservatory'];bpy.context.scene.camera=bpy.data.objects['F08B_DomeReview']
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'DA_F06_F07_F08_F09_F10_Combined_v037_dome_clearance.blend'))
print('Final sightlines saved')
