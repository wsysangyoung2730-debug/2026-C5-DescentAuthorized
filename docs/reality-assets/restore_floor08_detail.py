"""Recover silhouettes from v025; retain a bounded 120k triangle budget each."""
import bpy,sys
from pathlib import Path
source=Path(sys.argv[sys.argv.index('--')+1])
names=['tripo_node_935ff78e-c27c-4529-b03d-0432f6d31420','tripo_node_9771cc26-128d-4e01-bc64-4f606c8a1ea4']
bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(str(source),link=False) as (data,load):load.objects=names
for index,obj in enumerate(load.objects):
 bpy.context.scene.collection.objects.link(obj)
 obj.parent=None;obj.matrix_world.identity();obj.hide_set(False)
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
 before=sum(len(f.vertices)-2 for f in obj.data.polygons)
 modifier=obj.modifiers.new('Preserve close-up detail','DECIMATE');modifier.ratio=min(1,120000/before);modifier.use_collapse_triangulate=True
 bpy.ops.object.modifier_apply(modifier=modifier.name)
 obj.name=['RestoredPartition','RestoredCrate'][index]
 print(obj.name,before,sum(len(f.vertices)-2 for f in obj.data.polygons),flush=True)
for o in bpy.context.scene.objects:o.select_set(True)
bpy.ops.wm.usd_export(filepath='/private/tmp/c5-110-detail.usdc',selected_objects_only=True,export_materials=False,export_uvmaps=True,export_normals=True,export_animation=False,use_instancing=False)
