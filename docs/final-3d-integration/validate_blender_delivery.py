"""Read-only reopen check for the seven self-contained Blender deliveries."""
import bpy,json,argparse,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--directory',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);root=Path(__file__).resolve().parent;rows=json.loads((root/'room-contracts.json').read_text());results=[]
for floor in range(1,8):
 file=a.directory/f'Floor{floor:02d}_Final_Animated.blend';bpy.ops.wm.open_mainfile(filepath=str(file))
 missing=[];scenes=[]
 for r in [r for r in rows if r['floor']==floor]:
  scene=bpy.data.scenes[r['scene']];bpy.context.window.scene=scene
  for name in set(r['cameras'].values())|set(r['anchors'].values()):
   if name not in scene.objects:missing.append(name)
  rigs=[o for o in scene.objects if o.type=='ARMATURE' and o.get('runtime_actor_preview')]
  assert len(rigs)==1,(floor,scene.name,len(rigs))
  assert rigs[0].animation_data and rigs[0].animation_data.action,(floor,'motion missing')
  scenes.append({'scene':scene.name,'bones':len(rigs[0].data.bones),'motion':rigs[0].animation_data.action.name,'cameras':len(set(r['cameras'].values()))})
 external=[im.filepath for im in bpy.data.images if im.source=='FILE' and not im.packed_file]
 assert not missing and not external,(floor,missing,external)
 results.append({'floor':floor,'reopened':True,'missingObjects':missing,'externalTextures':external,'scenes':scenes})
 print('DELIVERY_OK',floor,flush=True)
a.report.write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
