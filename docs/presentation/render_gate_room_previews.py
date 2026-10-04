import bpy,json,sys
from pathlib import Path
root=Path(sys.argv[sys.argv.index('--')+1]);rows=json.loads((root/'docs/final-3d-integration/room-contracts.json').read_text());out=Path('/tmp/c5-gate-room-previews');out.mkdir(exist_ok=True)
plans=[]
for r in rows:
 if not r['role'].startswith('residual'):continue
 role='residualB' if r['role']=='residualA' and r['floor']<=4 else 'administrator'
 dest=next(x for x in rows if x['floor']==r['floor'] and x['role']==role)
 plans.append((r['resource'],dest['scene'],dest['cameras']['battle']))
plans.append(('floor08_residue_isolation','DA_F08B_AdministratorObservatory',''))
report=json.loads((out/"manifest.json").read_text()) if (out/"manifest.json").exists() else []
if "--floor8-only" in sys.argv: plans=[p for p in plans if p[0].startswith("floor08")]
for source,name,cam in plans:
 scene=bpy.data.scenes.get(name)
 if scene is None:
  if source.startswith('floor08'):
   scene=next((s for s in bpy.data.scenes if 'F08' in s.name and ('Observatory' in s.name or 'Boss' in s.name)),None)
  if scene is None: print('MISSING_SCENE',source,name,flush=True);continue
 bpy.context.window.scene=scene
 camera=scene.objects.get(cam) if cam else None
 if not camera:camera=next((o for o in scene.objects if o.type=='CAMERA' and ('MainCamera' in o.name or 'iPad' in o.name)),scene.camera)
 scene.camera=camera;scene.frame_set(1)
 scene.render.engine='CYCLES';scene.cycles.samples=12;scene.cycles.use_denoising=True
 scene.render.resolution_x=720;scene.render.resolution_y=960;scene.render.resolution_percentage=100
 scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
 # A narrow doorway view using the room's actual entry/battle camera.
 camera.data.lens=32
 scene.render.filepath=str(out/(source+'.png'))
 bpy.ops.render.render(write_still=True)
 report.append({'sourceRoom':source,'destinationScene':scene.name,'camera':camera.name,'file':source+'.png'})
 (out/'manifest.json').write_text(json.dumps(report,indent=2))
 print('PREVIEW_DONE',source,scene.name,flush=True)
