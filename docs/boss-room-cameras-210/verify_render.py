"""Reopen delivery, verify original objects and camera paths, render geometry previews.
Blender --background OUTPUT --python this_file -- --evidence DIR [--floors 9 8 ...] [--skip-render]
Preview render settings are temporary and are never saved back to the .blend.
"""
import argparse, hashlib, json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from author_cameras import signature, enum_set

def render_metadata(scene):
 r=scene.render
 return {'resolution_x':r.resolution_x,'resolution_y':r.resolution_y,'resolution_percentage':r.resolution_percentage,
         'pixel_aspect_x':r.pixel_aspect_x,'pixel_aspect_y':r.pixel_aspect_y,
         'display_aspect':r.resolution_x*r.pixel_aspect_x/(r.resolution_y*r.pixel_aspect_y),
         'fps':r.fps,'fps_base':r.fps_base,'effective_fps':r.fps/r.fps_base}

def camera_metadata(camera):
 d=camera.data
 return {'camera_type':d.type,'lens_mm':d.lens,'sensor_width_mm':d.sensor_width,'sensor_height_mm':d.sensor_height,
         'sensor_fit':d.sensor_fit,'shift_x':d.shift_x,'shift_y':d.shift_y,
         'clip_start_m':d.clip_start,'clip_end_m':d.clip_end}

def quaternion_error_degrees(actual,expected):
 # Normalize in Python double precision and treat q and -q as the same rotation.
 a=[float(v) for v in actual];b=[float(v) for v in expected]
 scale=math.sqrt(sum(v*v for v in a)*sum(v*v for v in b))
 assert scale>0,'Invalid zero-length quaternion'
 dot=min(1.0,max(0.0,abs(sum(x*y for x,y in zip(a,b)))/scale))
 return math.degrees(2*math.acos(dot))

p=argparse.ArgumentParser();p.add_argument('--evidence',required=True);p.add_argument('--floors',type=int,nargs='*');p.add_argument('--skip-render',action='store_true');args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
ev=Path(args.evidence).resolve();manifest=json.loads((ev/'camera-manifest.json').read_text());(ev/'frames').mkdir(exist_ok=True)
report={'file':bpy.data.filepath,'original_objects_unchanged':signature()==manifest['original_object_signature'],'source_sha256_unchanged':hashlib.file_digest(open(manifest['source'],'rb'),'sha256').hexdigest()==manifest['source_sha256'],'rooms':[],'render_skipped':args.skip_render,'render_mode':'Skipped; saved animation and path diagnostics only' if args.skip_render else 'Workbench solid geometry preview; not final game lighting'}
assert report['original_objects_unchanged'] and report['source_sha256_unchanged']
tolerances={'position_m':1e-4,'rotation_degrees':1e-3,'lens_mm':1e-4,'shift':1e-6}
report['sample_tolerances']=tolerances
report['path_diagnostic_scope']='Camera-center segment rays and 26 directions within 0.25 m; hits require review. No hits do not prove complete volume clearance.'
dirs=[Vector((a,b,c)).normalized() for a in [-1,0,1] for b in [-1,0,1] for c in [-1,0,1] if a or b or c]
for room in manifest['rooms']:
 if args.floors and room['floor'] not in args.floors:continue
 s=bpy.data.scenes[room['preview_scene']];bpy.context.window.scene=s;bpy.context.view_layer.update();cam=s.objects[room['preview_camera']];deps=bpy.context.evaluated_depsgraph_get()
 source_scene=bpy.data.scenes[room['scene']];assert source_scene.camera.name==room['original_active_camera']
 room['source_scene_render']=render_metadata(source_scene);room['preview_scene_render']=render_metadata(s)
 room['existing_main_camera_settings']=camera_metadata(source_scene.objects[room['existing_main_camera']])
 for pose in room['poses']:
  pose['camera_settings']=camera_metadata(s.objects[pose['name']])
  pose['shift_x']=pose['camera_settings']['shift_x'];pose['shift_y']=pose['camera_settings']['shift_y']
 s.frame_set(1);room['preview_camera_settings_at_frame_1']=camera_metadata(cam)
 authored_render=room['preview_scene_render']
 qa_render=dict(authored_render,resolution_x=900,resolution_y=max(1,round(authored_render['resolution_y']*900/authored_render['resolution_x'])),resolution_percentage=100)
 qa_render['display_aspect']=qa_render['resolution_x']*qa_render['pixel_aspect_x']/(qa_render['resolution_y']*qa_render['pixel_aspect_y'])
 room['verification_render']=qa_render
 rr={'floor':room['floor'],'cameras':sum(o.type=='CAMERA' for o in bpy.data.collections[room['collection']].objects),'targets':sum(o.type=='EMPTY' for o in bpy.data.collections[room['collection']].objects),'source_active_camera_unchanged':True,'samples_checked':0,'path_crossings':[],'near_surfaces':[],'rendered_frames':[],'sample_pose_max_error':0.0,'sample_rotation_max_error_degrees':0.0,'sample_lens_max_error_mm':0.0,'sample_shift_max_error':0.0,'source_render':authored_render,'verification_render':qa_render,'render_skipped':args.skip_render}
 previous=None
 for sample in room['samples']:
  f=sample['frame'];s.frame_set(f);pos=cam.matrix_world.translation.copy();expected=Vector(sample['position']);rr['sample_pose_max_error']=max(rr['sample_pose_max_error'],(pos-expected).length)
  rr['sample_rotation_max_error_degrees']=max(rr['sample_rotation_max_error_degrees'],quaternion_error_degrees(cam.matrix_world.to_quaternion(),sample['quaternion_wxyz']))
  rr['sample_lens_max_error_mm']=max(rr['sample_lens_max_error_mm'],abs(cam.data.lens-sample['lens_mm']))
  rr['sample_shift_max_error']=max(rr['sample_shift_max_error'],abs(cam.data.shift_x-sample['shift_x']),abs(cam.data.shift_y-sample['shift_y']))
  if previous is not None and (pos-previous).length>1e-6:
   hit,loc,normal,face,obj,matrix=s.ray_cast(deps,previous,(pos-previous).normalized(),distance=(pos-previous).length)
   if hit and not obj.hide_render:rr['path_crossings'].append({'frame':f,'object':obj.name,'position':list(loc)})
  for direction in dirs:
   hit,loc,normal,face,obj,matrix=s.ray_cast(deps,pos,direction,distance=.25)
   if hit and not obj.hide_render:
    rr['near_surfaces'].append({'frame':f,'object':obj.name,'distance':round((loc-pos).length,4)});break
  previous=pos;rr['samples_checked']+=1
 assert rr['cameras']==5 and rr['targets']==4
 rr['animation_samples_passed']=(rr['sample_pose_max_error']<=tolerances['position_m'] and rr['sample_rotation_max_error_degrees']<=tolerances['rotation_degrees'] and rr['sample_lens_max_error_mm']<=tolerances['lens_mm'] and rr['sample_shift_max_error']<=tolerances['shift'])
 rr['path_review_status']='needs_review' if rr['path_crossings'] or rr['near_surfaces'] else 'no_hits_detected'
 report_prefix='verification-animation' if args.skip_render else 'verification'
 if not rr['animation_samples_passed']:
  (ev/f'{report_prefix}-{room["floor"]:02d}.json').write_text(json.dumps(rr,indent=2))
 assert rr['animation_samples_passed'],f'Saved animation differs from samples on floor {room["floor"]}: {rr}'
 if not args.skip_render:
  s.render.engine='BLENDER_WORKBENCH';s.render.resolution_x=qa_render['resolution_x'];s.render.resolution_y=qa_render['resolution_y'];s.render.resolution_percentage=100
  enum_set(s.display.shading,'light','STUDIO');enum_set(s.display.shading,'color_type','MATERIAL');s.display.shading.show_shadows=True;s.display.shading.show_cavity=True
  enum_set(s.render.image_settings,'file_format','PNG')
  for frame in [1,52,103,160,217,277,337]:
   s.frame_set(frame);s.render.filepath=str(ev/'frames'/f'F{room["floor"]:02d}_{frame:03d}.png');bpy.ops.render.render(write_still=True);rr['rendered_frames'].append(frame)
 report['rooms'].append(rr);(ev/f'{report_prefix}-{room["floor"]:02d}.json').write_text(json.dumps(rr,indent=2));print('ROOM_ANIMATION_VERIFIED',room['floor'],'PATH_REVIEW_REQUIRED' if rr['path_review_status']=='needs_review' else 'NO_PATH_HITS_DETECTED','crossings',len(rr['path_crossings']),'near',len(rr['near_surfaces']),flush=True)
report['path_review_required']=any(r['path_review_status']=='needs_review' for r in report['rooms'])
(ev/('verification-animation.json' if args.skip_render else 'verification.json')).write_text(json.dumps(report,indent=2))
(ev/'camera-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
if not args.skip_render:
 bpy.data.libraries.write(str(ev/'EncounterCameraRigs_v068.blend'),{bpy.data.collections[r['collection']] for r in manifest['rooms']},fake_user=True,compress=True)
print('VERIFICATION_COMPLETE',flush=True)
