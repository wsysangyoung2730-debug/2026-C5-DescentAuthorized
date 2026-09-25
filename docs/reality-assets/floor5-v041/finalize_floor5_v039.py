"""Final orientations, source-preserving reduction, empty reward stand request."""
import bpy,runpy,math
from pathlib import Path
from mathutils import Vector
F=runpy.run_path(str(Path(__file__).parent/'build_floor5_v039.py'))
for n in ['F05A_ReelBank01','F05A_ReelBank02','F05A_Portraits','F05B_ReliquaryLeft','F05B_PortraitsLeft']:
    bpy.data.objects[n].rotation_euler.z=math.radians(45)
for n in ['F05A_SidePortraits','F05A_NearRightReliquary','F05B_ReelRight']:
    bpy.data.objects[n].rotation_euler.z=math.radians(-45)
bpy.data.objects['F05A_RearMasterReel'].rotation_euler.z=0
s=bpy.data.scenes[F['SCENES']['F05B']];bpy.context.window.scene=s;s.frame_set(1);bpy.context.view_layer.update()
roots=[o for o in s.objects if o.type=='EMPTY' and 'RewardScroll' in o.name and o.name.endswith('HoleAnchor')]
for root in roots:
    for child in list(root.children_recursive):bpy.data.objects.remove(child,do_unlink=True)
    bpy.data.objects.remove(root,do_unlink=True)
# Future visual spawn markers belong to the stand, not the old animated scroll hierarchy.
stand=s.objects['F05B_RewardSelection'];lo,hi=F['bounds'](stand);cx=(lo.x+hi.x)/2;cy=(lo.y+hi.y)/2
for side,dx,dy,dz in [('Left',-.8,0,-.23),('Center',0,.22,.04),('Right',.8,0,-.23)]:
    n='ANCHOR_F05_RewardSlot_'+side;o=bpy.data.objects.get(n)
    if o is None:o=F['empty']('F05B',n)
    o.parent=stand;o.matrix_world.translation=Vector((cx+dx,cy+dy,hi.z+dz))
    o['role']='Future scroll visual spawn marker; no mesh and no animation';o['placement']='Review when attaching runtime reward animation'
s['reward_state']='Empty stand; no three scroll meshes or appearance animation'
o=s.objects['F05B_DecorativeClosedDoor__Mesh00'];count=sum(len(p.vertices)-2 for p in o.data.polygons)
if count>40000:
    d=o.modifiers.new('Decorative door reduction','DECIMATE');d.ratio=35000/count
    bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.modifier_apply(modifier=d.name)
o['source_triangles']=1864382;o['target_triangles']=35000
# Keep the future scroll headroom in the dedicated reward camera.
for p,sn in F['SCENES'].items():
    room=bpy.data.scenes[sn];room.frame_set(1);room.camera=bpy.data.objects[p+'_Overview']
bpy.context.view_layer.update()
print('Final floor5 state: decorative doors, empty reward stand, supplied props')
