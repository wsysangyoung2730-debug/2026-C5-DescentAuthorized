import bpy,json,traceback
from pathlib import Path
OUT=Path(bpy.data.filepath).parent/'review_v038';OUT.mkdir(exist_ok=True)
scenes={'F06A':'DA_F06A_ResultDelayResidue','F06B':'DA_F06B_CausalityAdministrator','F07A':'DA_F07A_CoordinateResidue','F07B':'DA_F07_CoordinateAdministrator','F08A':'DA_F08A_ResidueIsolation','F08B':'DA_F08_AdministratorObservatory','F09':'DA_F09_Archive_Redesign','F10':'DA_F10_ClosedOffice'}
queue=[('F06B','F06B_DomeReview',1),('F06B','F06_iPad_MainCamera',1),('F08B','F08_iPad_MainCamera',1)]
for p in ['F06B','F07B','F08B','F09','F10']:
 for typ in ['RewardSelection','DescentDoor']:queue.append((p,'CAM_'+p[:3]+'_'+typ,66 if typ=='RewardSelection' else 1))
for p in scenes:
 for side in ['Left','Right']:queue.append((p,p+'_SideCheck_'+side,1))
for p in ['F06A','F06B','F07A','F07B']:queue.append((p,p+'_RedesignOverview',1))
status={'total':len(queue),'done':[],'errors':[]}
def tick():
 p,cn,frame=queue.pop(0);s=bpy.data.scenes[scenes[p]]
 bpy.context.window.scene=s
 old=(s.camera,s.frame_current,s.render.resolution_x,s.render.resolution_y,s.render.resolution_percentage,s.cycles.samples,s.render.filepath)
 try:
  s.camera=bpy.data.objects[cn];s.frame_set(frame);bpy.context.view_layer.update()
  s.render.resolution_x=1280 if 'DomeReview' in cn else 800;s.render.resolution_y=800 if 'DomeReview' in cn else 500;s.render.resolution_percentage=100;s.cycles.samples=24 if 'DomeReview' in cn else 12;s.cycles.use_denoising=True
  s.render.filepath=str(OUT/(cn+'.png'))
  bpy.ops.render.render(write_still=True,scene=s.name)
  status['done'].append(cn)
 except Exception:status['errors'].append([cn,traceback.format_exc()])
 finally:
  s.camera=old[0];s.frame_set(old[1]);s.render.resolution_x=old[2];s.render.resolution_y=old[3];s.render.resolution_percentage=old[4];s.cycles.samples=old[5];s.render.filepath=old[6]
 (OUT/'status.json').write_text(json.dumps(status,indent=2))
 return 1 if queue else None
bpy.app.timers.register(tick,first_interval=2)
print('Scheduled',len(queue),'camera renders')
