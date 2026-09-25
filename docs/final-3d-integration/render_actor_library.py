import bpy,sys,math,json
from pathlib import Path
from mathutils import Vector
base=Path(sys.argv[sys.argv.index('--')+1]);base.mkdir(exist_ok=True)
reports=[]
scenes=[s for s in bpy.data.scenes if s.name.startswith('DA_ACTOR_')]

for scene in scenes:
    out=base/scene.name;out.mkdir(exist_ok=True)
    bpy.context.window.scene=scene
    scene.render.engine='CYCLES';scene.cycles.samples=8
    scene.render.resolution_x=300;scene.render.resolution_y=400;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('PreviewWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.12,.12,.12,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.4
    for loc,power,size in [((3,-4,5),550,4),((-3,-2,3),350,3),((0,3,4),600,3)]:
     d=bpy.data.lights.new('Preview','AREA');d.energy=power;d.shape='DISK';d.size=size;o=bpy.data.objects.new('Preview',d);scene.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,1.5))-o.location).to_track_quat('-Z','Y').to_euler()
    c=bpy.data.cameras.new('Preview');o=bpy.data.objects.new('PreviewCamera',c);scene.collection.objects.link(o);o.location=(.3,-6,2);o.rotation_euler=(Vector((0,0,1.5))-o.location).to_track_quat('-Z','Y').to_euler();c.type='ORTHO';c.ortho_scale=3.6;scene.camera=o
    markers={m.name:m.frame for m in scene.timeline_markers}
    for label,frame in [('idle',1),('attack',markers['attack_IMPACT']),('death',scene.frame_end)]:
     scene.frame_set(frame);scene.render.filepath=str(out/(label+'.png'));bpy.ops.render.render(write_still=True)
    
    heights=[]
    for frame in range(1,scene.frame_end+1,15):
     scene.frame_set(frame);dg=bpy.context.evaluated_depsgraph_get()
     pts=[obj.matrix_world@v.co for obj in scene.objects if obj.type=='MESH' and len(obj.data.vertices)>1000 and not obj.hide_render for v in obj.evaluated_get(dg).data.vertices]
     heights.append(min(p.z for p in pts))
    reports.append({'actor':scene.name,'minFootZ':min(heights),'maxFootZ':max(heights),'sampleCount':len(heights)})

(base/'grounding.json').write_text(json.dumps(reports,indent=2))
