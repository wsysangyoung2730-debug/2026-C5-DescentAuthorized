import bpy,json,runpy
from pathlib import Path
OUT=Path(__file__).parent
F=runpy.run_path(str(OUT/'build_floor5_v039.py'))
for p,name in F['SCENES'].items():
    s=bpy.data.scenes[name];s.frame_set(1);s.camera=bpy.data.objects[p+'_Overview']
bpy.context.window.scene=bpy.data.scenes[F['SCENES']['F05B']]
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'DA_F05_F06_F07_F08_F09_F10_Combined_v040_side_dressing.blend'))
bpy.data.libraries.write(str(OUT/'DA_F05_TwoRooms_v040.blend'),{bpy.data.scenes[n] for n in F['SCENES'].values()},fake_user=True)
report={'integrated':'DA_F05_F06_F07_F08_F09_F10_Combined_v040_side_dressing.blend','floor5_only':'DA_F05_TwoRooms_v040.blend','added':{}}
for p,name in F['SCENES'].items():
    s=bpy.data.scenes[name];report['added'][p]=[o.name for o in s.objects if o.get('side_dressing')]
(OUT/'SAVE_floor5_v040.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print('v040 saved', {k:len(v) for k,v in report['added'].items()})
