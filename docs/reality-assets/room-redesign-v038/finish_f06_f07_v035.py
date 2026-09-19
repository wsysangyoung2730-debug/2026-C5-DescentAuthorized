"""Final composition and render settings, after refine_f06_f07_v035.py."""
import bpy,runpy,math
from pathlib import Path
from mathutils import Vector
R=runpy.run_path(str(Path(bpy.data.filepath).parent/'redesign_f06_f07_v035.py'),run_name='helpers')
move=R['move'];m=R['materials']()
for p,sn in R['SCENES'].items():
    s=bpy.data.scenes[sn];c=s.camera
    c.location=(0,-7.6,3.0);c.data.lens=20
    c.rotation_euler=(Vector((0,8,1.45))-c.location).to_track_quat('-Z','Y').to_euler()
    s.render.resolution_x=1280;s.render.resolution_y=800;s.render.resolution_percentage=100
    s.render.image_settings.file_format='PNG';s.render.filepath=str(Path(bpy.data.filepath).parent/(p+'_v035_final.png'))
    s.cycles.samples=40;s.cycles.use_denoising=True
    if p.endswith('B'):
        root=bpy.data.objects[p+'_RewardSelection'];root.location+=Vector((1.45,-4.2,0))
        move('anchor_'+p[:3]+'_reward_interaction',(-7.2,-.5,0))
        cam=bpy.data.objects['CAM_'+p[:3]+'_RewardSelection'];cam.location=(-7.2,-3.3,2.15)
        cam.rotation_euler=(Vector((-7.2,2.3,.85))-cam.location).to_track_quat('-Z','Y').to_euler()
        R['light'](p,'RewardKey',(-7.2,-.5,4.6),(-7.2,2.3,.7),550,(1,.82,.57),3)
    # Subtle bevels prevent featureless razor edges on new architecture.
    for o in R['coll'](p).objects:
        if o.type=='MESH' and len(o.data.vertices)==8 and min(o.dimensions)>.12:
            mod=o.modifiers.new('Soft fabricated edges','BEVEL');mod.width=.025;mod.segments=2
    s['redesign_finalized']=True
move('F07B_CalibrationGantry',(-5.4,15.4,0),5.4,0)
move('F07B_CalibrationGantry_Right',(5.4,15.4,0),5.4,0)
move('F07B_DescentStele',(7.2,3,0),2.7,0)
move('F07B_AxisTotem',(-5.7,6.3,0),3.2)
move('F07B_AxisTotem.001',(5.7,6.3,0),3.2)
# Place the main descent interaction next to its gate; the foreground stele is its remote input.
move('F06B_DescentStele',(7.2,2.5,0),2.7,0)
move('floor6-sequence-verification-console.001',(10,5.5,0),2.4,-.4)
bpy.context.view_layer.update()
print('Final camera and interaction compositions ready')
