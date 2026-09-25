import bpy,os,math,sys,argparse
parser=argparse.ArgumentParser()
parser.add_argument("--output",required=True)
args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
os.makedirs(os.path.dirname(os.path.abspath(args.output)),exist_ok=True)
s=bpy.data.scenes['DA_F09_Archive_Redesign'];bpy.context.window.scene=s
d=bpy.data.cameras.new('ReflectionCapture');d.type='PANO';d.panorama_type='EQUIRECTANGULAR'
o=bpy.data.objects.new('ReflectionCapture',d);s.collection.objects.link(o);o.location=(0,5,3);o.rotation_euler=(math.pi/2,0,0);s.camera=o
s.render.engine='CYCLES';s.cycles.samples=32;s.cycles.use_denoising=True
s.render.resolution_x=512;s.render.resolution_y=256;s.render.resolution_percentage=100
s.render.image_settings.file_format='HDR';s.render.filepath=os.path.abspath(args.output)
bpy.ops.render.render(write_still=True)
