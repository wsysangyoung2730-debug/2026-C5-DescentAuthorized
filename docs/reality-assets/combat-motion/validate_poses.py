"""Blender whole-clip pose checks.
Usage: blender -b CombatActors_Rigged.blend --python validate_poses.py -- --report checks.json
"""
import bpy,json,argparse,sys
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--report',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
report=json.loads(Path(__file__).with_name('actor-report.json').read_text());checks=[]
for row in report:
 scene=bpy.data.scenes['DA_ACTOR_'+row['name']];bpy.context.window.scene=scene
 mesh=scene.objects[row['name']+'_Skin'];rig=scene.objects['ACTOR_'+row['name']];root=rig.pose.bones['root']
 anchored=[v.index for v in mesh.data.vertices if v.co.z<.65]
 actor={'actor':row['name'],'clips':{}}
 for clip in ['attack','heavyAttack','death']:
  data=row['clips'][clip];start=1+round(data['start']*30);end=1+round(data['end']*30);minz=1e9;maxroot=0;maxfoot=0
  for frame in range(start,end+1):
   scene.frame_set(frame);bpy.context.view_layer.update();evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
   minz=min(minz,min(v.co.z for v in evaluated.data.vertices));maxroot=max(maxroot,root.location.length)
   if row['boss']:maxfoot=max(maxfoot,max((evaluated.data.vertices[i].co-mesh.data.vertices[i].co).length for i in anchored))
  actor['clips'][clip]={'samples':end-start+1,'minimumZ':minz,'maximumRootTranslation':maxroot,'maximumAnchoredVertexDisplacement':maxfoot if row['boss'] else None}
  assert minz>=-.035,(row['name'],clip,minz)
  if row['boss']:assert maxroot<1e-6 and maxfoot<1e-5,(row['name'],clip,maxroot,maxfoot)
 assert row['motionChecks']['death']['maxZ']<3
 checks.append(actor)
args.report.write_text(json.dumps(checks,indent=2)+'\n')
print('PASS',len(checks),'actors, all attack/heavyAttack/death frames; grounded managers and no floor penetration')
