"""Correct dome location to 6F. Restore the 8F ceiling; preserve prop changes."""
import bpy,math,runpy
from mathutils import Vector
from pathlib import Path
OUT=Path(bpy.data.filepath).parent
R=runpy.run_path(str(OUT/'redesign_f06_f07_v035.py'),run_name='helpers')
s8=bpy.data.scenes['DA_F08_AdministratorObservatory'];s8.camera=bpy.data.objects['F08_iPad_MainCamera']
c8=bpy.data.collections.get('F08B_DomeArchitecture')
if c8:
 for o in list(c8.objects):bpy.data.objects.remove(o,do_unlink=True)
 bpy.data.collections.remove(c8)
for o in list(s8.objects):
 if o.name.startswith(('F08B_DomeEdgeBeam','F08B_DomeUplight')):bpy.data.objects.remove(o,do_unlink=True)
for o in s8.objects:
 if o.name=='Ceiling.001' or o.name.startswith('CeilingBeam_'):o.hide_render=False;o.hide_viewport=False
if 'ceiling_revision' in s8:del s8['ceiling_revision']
s=bpy.data.scenes[R['SCENES']['F06B']];bpy.context.window.scene=s
c=R['coll']('F06B','DomeArchitecture')
steel=bpy.data.materials['DA35_ArchiveConcrete'];iron=bpy.data.materials['DA35_CalibrationBrass']
# Continuous ceiling with a real circular opening, not a dome hidden behind a flat slab.
old=bpy.data.objects['F06B_Ceiling'];old.hide_render=True;old.hide_viewport=True
cx,cy,z,rise,radius=0,8.8,8.0,3.2,6.7
N=128
v=[];f=[]
for i in range(N):
 a=math.tau*i/N;dx,dy=math.cos(a),math.sin(a)
 t=min(12/abs(dx) if abs(dx)>1e-8 else 1e9,(19-cy)/dy if dy>1e-8 else (-9-cy)/dy if dy<-1e-8 else 1e9)
 v.extend([(radius*dx,cy+radius*dy,z),(t*dx,cy+t*dy,z)])
for i in range(N):f.append((2*i,2*((i+1)%N),2*((i+1)%N)+1,2*i+1))
def mesh(name,verts,faces,mat):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.materials.append(mat)
 o=bpy.data.objects.new(name,me);c.objects.link(o);return o
ceiling=mesh('F06B_CeilingAroundDome',v,f,steel)
sol=ceiling.modifiers.new('CeilingThickness','SOLIDIFY');sol.thickness=.32
# Ellipsoidal dome, smooth curved silhouette with open underside.
v=[];f=[];levels=24
for j in range(levels):
 t=(math.pi/2)*j/levels
 for i in range(N):
  a=math.tau*i/N;v.append((radius*math.cos(t)*math.cos(a),cy+radius*math.cos(t)*math.sin(a),z+rise*math.sin(t)))
for j in range(levels-1):
 for i in range(N):
  a=j*N+i;b=j*N+(i+1)%N;f.append((a,a+N,b+N,b))
v.append((0,cy,z+rise));top=len(v)-1
for i in range(N):f.append(((levels-1)*N+i,top,(levels-1)*N+(i+1)%N))
dome=mesh('F06B_ObservationDome',v,f,bpy.data.materials['DA35_ArchiveConcrete'])
for p in dome.data.polygons:p.use_smooth=True
sol=dome.modifiers.new('ShellThickness','SOLIDIFY');sol.thickness=.2
# Curved ribs carry the dome visually, without columns across the combat lane.
def tube(name,pts,rad,mat):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.bevel_depth=rad;cu.bevel_resolution=3
 sp=cu.splines.new('POLY');sp.points.add(len(pts)-1)
 for p,xyz in zip(sp.points,pts):p.co=(*xyz,1)
 o=bpy.data.objects.new(name,cu);c.objects.link(o);cu.materials.append(mat);return o
for k in range(12):
 a=math.tau*k/12
 tube('F06B_DomeRib_%02d'%k,[(radius*math.cos(t)*math.cos(a),cy+radius*math.cos(t)*math.sin(a),z+rise*math.sin(t)-.06) for t in [j*math.pi/2/48 for j in range(49)]],.055,iron)
for rr,zz in [(radius,z-.05),(radius*.72,z+rise*math.sqrt(1-.72**2)-.04)]:
 tube('F06B_DomeRing',[(rr*math.cos(math.tau*i/128),cy+rr*math.sin(math.tau*i/128),zz) for i in range(129)],.075,iron)
# Clip straight ceiling beams at the circular opening.
for o in list(s.objects):
 if o.name.startswith('F06B_CeilingCrossBeam') and abs(o.location.y-cy)<radius:
  half=math.sqrt(radius**2-(o.location.y-cy)**2)+.08
  o.hide_render=True;o.hide_viewport=True
  for sign in [-1,1]:R['box']('F06B','DomeEdgeBeam',(sign*(12.0+half)/2,o.location.y,o.location.z),(12.0-half,.24,.55),iron)
R['light']('F06B','DomeUplight',(0,8.8,7.6),(0,8.8,11.2),700,(1,.72,.46),5)
# A review camera shows the ceiling; the gameplay camera remains intact.
d=bpy.data.cameras.new('F06B_DomeReview');d.lens=18
o=bpy.data.objects.new(d.name,d);c.objects.link(o);o.location=(0,-7.6,3.3)
o.rotation_euler=(Vector((0,8.8,5.5))-o.location).to_track_quat('-Z','Y').to_euler()
s['ceiling_revision']='v038 shallow dome: radius 6.7m, rise 3.2m'

for o in s.objects:
 if o.name.startswith('F06B_VaultRing'):o.hide_render=True;o.hide_viewport=True
 if o.name.startswith('F06B_HighLampCase'):o.location.z=7.72
 if o.name.startswith('F06B_HighLampStrip'):o.location.z=7.61
s.camera=bpy.data.objects['F06B_DomeReview'];s.frame_set(1);bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'DA_F06_F07_F08_F09_F10_Combined_v038_floor6_dome.blend'))
print('8F ceiling restored; 6F dome saved in v038')
# Keep the entire 8F descent platform perimeter clear.
bpy.data.objects['ControlConsole_R_02'].location=(-10.1,3,0)
bpy.data.objects['ControlConsole_R_02'].rotation_euler.z=math.pi/2
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'DA_F06_F07_F08_F09_F10_Combined_v038_floor6_dome.blend'))
