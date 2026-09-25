import bpy,runpy,math
from pathlib import Path
from mathutils import Vector
OUT=Path(bpy.data.filepath).parent
R=runpy.run_path(str(OUT/'redesign_f06_f07_v035.py'),run_name='helpers')
# Finish perimeter behind the sideways field of view and light the side collections.
for p in ['F06A','F06B','F07A','F07B']:
 s=bpy.data.scenes[R['SCENES'][p]];bpy.context.window.scene=s
 h=4.9 if p=='F06A' else 8 if p=='F06B' else 5.8 if p=='F07A' else 12
 mat=bpy.data.objects[p+'_SideWall'].data.materials[0]
 R['box'](p,'FrontReturnWall',(0,-9.25,h/2),(24.4,.4,h),mat)
 for sign in [-1,1]:
  R['light'](p,'SideCabinetWash',(sign*6.8,-5.8,4.2),(sign*9.6,-5.2,1.7),420,(1,.72,.46) if p.startswith('F06') else (.54,.8,1),3)
 if p=='F06B':
  for sign in [-1,1]:
   o=bpy.data.objects[p+'_SideArchive_'+str(sign)];o.location=(sign*8.8,-3.9,0);o.rotation_euler.z=-sign*math.pi*.75
# Frame complete descent pedestal, stele and gate together.
for f in ['F06','F07','F08','F09','F10']:
 cam=bpy.data.objects['CAM_'+f+'_DescentDoor'];x=8.35 if f=='F07' else 8.2 if f=='F08' else 8.15
 cam.data=cam.data.copy();cam.data.lens=21
 cam.location=(x,4.9,2.9)
 cam.rotation_euler=(Vector((x,13,2.05))-cam.location).to_track_quat('-Z','Y').to_euler()
# Final floor's existing interaction is the instructor desk, not a scroll pedestal.
cam=bpy.data.objects['CAM_F10_RewardSelection'];cam.data=cam.data.copy();cam.data.lens=26;cam.location=(-5,5.3,3.3)
cam.rotation_euler=(Vector((-7.1,10,1.8))-cam.location).to_track_quat('-Z','Y').to_euler()
cam['interaction_subject']='Existing instructor desk; this scene has no reward-scroll rig'
for sn in R['SCENES'].values():
 bpy.context.window.scene=bpy.data.scenes[sn];bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
bpy.context.window.scene=bpy.data.scenes['DA_F08_AdministratorObservatory'];bpy.context.scene.camera=bpy.data.objects['F08B_DomeReview'];bpy.context.scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'DA_F06_F07_F08_F09_F10_Combined_v037_dome_clearance.blend'))
print('Camera framing and side lighting saved')
