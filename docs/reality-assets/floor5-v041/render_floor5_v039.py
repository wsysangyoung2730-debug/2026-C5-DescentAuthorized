import bpy,json,traceback
from pathlib import Path
OUT=Path(__file__).parent/'review_floor5_v039';OUT.mkdir(exist_ok=True)
SCENES={'F05A':'DA_F05A_MemoryOmissionResidue','F05B':'DA_F05B_OriginalMemoryAdministrator'}
queue=[('F05A','F05A_Overview',1),('F05B','F05B_Overview',1),('F05B','CAM_F05_RewardSelection',1),('F05B','CAM_F05_DescentDoor',1)]
for p in SCENES:
    for side in ['Left','Right']:queue.append((p,p+'_SideCheck_'+side,1))
queue += [('F05A','F05A_iPad_MainCamera',1),('F05B','F05_iPad_MainCamera',1)]
status={'total':len(queue),'done':[],'errors':[]}
def tick():
    p,cn,frame=queue.pop(0);s=bpy.data.scenes[SCENES[p]];bpy.context.window.scene=s
    old=(s.camera,s.frame_current,s.render.resolution_x,s.render.resolution_y,s.cycles.samples,s.render.filepath)
    try:
        s.camera=bpy.data.objects[cn];s.frame_set(frame);bpy.context.view_layer.update()
        overview=cn.endswith('Overview')
        s.render.resolution_x=1440 if overview else 960;s.render.resolution_y=900 if overview else 600;s.cycles.samples=32 if overview else 12
        s.render.filepath=str(OUT/(cn+'.png'));bpy.ops.render.render(write_still=True,scene=s.name)
        status['done'].append(cn)
    except Exception:status['errors'].append([cn,traceback.format_exc()])
    finally:
        s.camera=old[0];s.frame_set(old[1]);s.render.resolution_x=old[2];s.render.resolution_y=old[3];s.cycles.samples=old[4];s.render.filepath=old[5]
    (OUT/'status.json').write_text(json.dumps(status,indent=2))
    return 1 if queue else None
bpy.app.timers.register(tick,first_interval=1)
print('Scheduled ten final floor5 review renders')
