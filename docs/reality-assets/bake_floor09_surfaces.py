import bpy,os,json
from pathlib import Path
out=Path('/private/tmp/c5-surfaces');out.mkdir(exist_ok=True)
s=bpy.data.scenes.new('C5_SurfaceBake');bpy.context.window.scene=s
s.render.engine='CYCLES';s.cycles.samples=8;s.cycles.use_denoising=False
s.render.bake.margin=16
bpy.ops.mesh.primitive_plane_add(size=8,location=(4,4,0));plane=bpy.context.object
records=[]
for name in ['F09_Worn_Concrete','F09_Aged_Plaster','F09_Service_Iron','F09_Faded_Marking']:
 mat=bpy.data.materials[name].copy();plane.data.materials.clear();plane.data.materials.append(mat)
 nodes=mat.node_tree.nodes;links=mat.node_tree.links;bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL');emit=nodes.new('ShaderNodeEmission');target=nodes.new('ShaderNodeTexImage');nodes.active=target
 for channel in ['basecolor','roughness','normal']:
  img=bpy.data.images.new(name+'_'+channel,width=2048,height=2048,alpha=False)
  img.colorspace_settings.name='sRGB' if channel=='basecolor' else 'Non-Color';target.image=img
  for l in list(output.inputs['Surface'].links):links.remove(l)
  if channel=='normal':links.new(bs.outputs['BSDF'],output.inputs['Surface'])
  else:
   for l in list(emit.inputs['Color'].links):links.remove(l)
   src=bs.inputs['Base Color' if channel=='basecolor' else 'Roughness']
   if src.is_linked:links.new(src.links[0].from_socket,emit.inputs['Color'])
   else:emit.inputs['Color'].default_value=src.default_value if channel=='basecolor' else (src.default_value,)*3+(1,)
   links.new(emit.outputs[0],output.inputs['Surface'])
  bpy.ops.object.bake(type='NORMAL' if channel=='normal' else 'EMIT')
  img.file_format='PNG';img.filepath_raw=str(out/(name+'_'+channel+'.png'));img.save()
  records.append({'material':name,'channel':channel,'file':name+'_'+channel+'.png'})
  bpy.data.images.remove(img)
  print('BAKED',name,channel,flush=True)
(out/'manifest.json').write_text(json.dumps(records))
print('COMPLETE',flush=True)
