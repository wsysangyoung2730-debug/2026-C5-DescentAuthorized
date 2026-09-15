import bpy, math
from pathlib import Path
out=Path('/private/tmp/c5-110-environments');out.mkdir(exist_ok=True)
for name,filename,position in [
 ('DA_F10_ClosedOffice','floor10_environment',(0,3,3)),
 ('DA_F08A_ResidueIsolation','floor08_residue_environment',(0,3,3)),
 ('DA_F08_AdministratorObservatory','floor08_boss_environment',(0,6,4))]:
 s=bpy.data.scenes[name];bpy.context.window.scene=s
 d=bpy.data.cameras.new('ReflectionCapture');d.type='PANO';d.panorama_type='EQUIRECTANGULAR'
 o=bpy.data.objects.new('ReflectionCapture',d);s.collection.objects.link(o)
 o.location=position;o.rotation_euler=(math.pi/2,0,0);s.camera=o
 s.render.engine='CYCLES';s.cycles.samples=16;s.cycles.use_denoising=True
 s.render.resolution_x=512;s.render.resolution_y=256;s.render.resolution_percentage=100
 s.render.image_settings.file_format='HDR';s.render.filepath=str(out/(filename+'.hdr'))
 bpy.ops.render.render(write_still=True)
 print('ENVIRONMENT',filename,flush=True)
