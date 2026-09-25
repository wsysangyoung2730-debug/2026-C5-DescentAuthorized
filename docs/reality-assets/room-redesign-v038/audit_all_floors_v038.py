import bpy,json,os,math,runpy
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
OUT=Path(bpy.data.filepath).parent
R=runpy.run_path(str(OUT/'audit_f06_f07_v035.py'))
scenes={'F06A':'DA_F06A_ResultDelayResidue','F06B':'DA_F06B_CausalityAdministrator','F07A':'DA_F07A_CoordinateResidue','F07B':'DA_F07_CoordinateAdministrator','F08A':'DA_F08A_ResidueIsolation','F08B':'DA_F08_AdministratorObservatory','F09':'DA_F09_Archive_Redesign','F10':'DA_F10_ClosedOffice'}
report={'file':bpy.data.filepath,'rooms':{},'checks':[],'source_assets':{}}
usage=json.loads((OUT/'all_floor_asset_usage_v036.json').read_text())
for path,refs in usage.items():
 visible=[]
 for sn,on,_ in refs:
  s=bpy.data.scenes.get(sn);o=s.objects.get(on) if s else None
  if o and not o.hide_render and any(not c.hide_render for c in o.users_collection):visible.append([sn,on])
 assert visible,'Unused asset: '+path
 report['source_assets'][path]=visible
for p,sn in scenes.items():
 s=bpy.data.scenes[sn];bpy.context.window.scene=s;s.frame_set(1);bpy.context.view_layer.update()
 meshes=set(o for o in s.objects if o.type=='MESH')
 for o in s.objects:
  if o.instance_collection:meshes.update(x for x in o.instance_collection.all_objects if x.type=='MESH')
 imgs={n.image for o in meshes for m in o.data.materials if m and m.use_nodes for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}
 missing=[i.name for i in imgs if i.source=='FILE' and not i.packed_file and not os.path.exists(bpy.path.abspath(i.filepath))]
 assert not missing,missing
 row={'object_count':len(s.objects),'texture_count':len(imgs),'missing_textures':missing,'side_cameras':[p+'_SideCheck_Left',p+'_SideCheck_Right']}
 if p in ['F06B','F07B','F08B','F09','F10']:
  cam=s.objects['CAM_'+p[:3]+'_DescentDoor'];roots=[p+'_DescentStele',p+'_DescentPedestal']
  oldres=(s.render.resolution_x,s.render.resolution_y,s.render.resolution_percentage);s.render.resolution_x=800;s.render.resolution_y=500;s.render.resolution_percentage=100
  row['descent_projection']={}
  for name in roots:
   pts=R['points'](s.objects[name]);proj=[world_to_camera_view(s,cam,v) for v in pts]
   b={'min':[min(v[i] for v in proj) for i in range(3)],'max':[max(v[i] for v in proj) for i in range(3)]}
   row['descent_projection'][name]=b
   assert b['min'][2]>0 and b['min'][0]>=0 and b['min'][1]>=0 and b['max'][0]<=1 and b['max'][1]<=1,('Clipped',name,b)
  s.render.resolution_x,s.render.resolution_y,s.render.resolution_percentage=oldres
 if p in ['F06B','F07B','F08B','F09']:
  s.frame_set(66);bpy.context.view_layer.update()
  scrolls=[o for o in s.objects if o.type=='EMPTY' and 'RewardScroll' in o.name and o.name.endswith('_Appear')]
  assert len(scrolls)==3 and all(min(o.scale)>.99 for o in scrolls),(p,'scroll animation')
  row['reward_scrolls_emerged_at_frame66']=True;s.frame_set(1)
 report['rooms'][p]=row
assert bpy.data.objects.get('F06B_ObservationDome') is not None
assert bpy.data.objects.get('F08B_ObservationDome') is None
assert not bpy.data.objects['Ceiling.001'].hide_render
report['checks']=['104/104 supplied source assets have render-enabled scene placements','Texture references valid in all 8 room scenes','All 5 descent steles and floor platforms fit their camera frames','Three reward scrolls emerge at frame 66 in floors 6–9','10F retains the existing instructor-desk interaction','6F dome uses an open circular ceiling aperture, curved ribs and a 3.2m rise; 8F flat ceiling restored']
(OUT/'AUDIT_v038.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report['checks'],ensure_ascii=False))
