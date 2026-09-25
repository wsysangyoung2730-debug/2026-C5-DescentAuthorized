"""Apply once to v036: shallow observation dome and perimeter columns."""
import bpy,math,runpy
from mathutils import Vector
from pathlib import Path
OUT=Path(bpy.data.filepath).parent
R=runpy.run_path(str(OUT/'redesign_f06_f07_v035.py'),run_name='helpers')
R['SCENES']['F08B']='DA_F08_AdministratorObservatory'
s=bpy.data.scenes[R['SCENES']['F08B']];bpy.context.window.scene=s
c=R['coll']('F08B','DomeArchitecture')
steel=bpy.data.materials['F08B_WornStructuralSteel'];iron=bpy.data.materials['F08_TechnicalFrame.001']
# Continuous ceiling with a real circular opening, not a dome hidden behind a flat slab.
old=bpy.data.objects['Ceiling.001'];old.hide_render=True;old.hide_viewport=True
cx,cy,z,rise,radius=0,8,11.09,3.8,7.0
N=128
v=[];f=[]
for i in range(N):
 a=math.tau*i/N;dx,dy=math.cos(a),math.sin(a)
 t=min(11.5/abs(dx) if abs(dx)>1e-8 else 1e9,(17-cy)/dy if dy>1e-8 else (-13-cy)/dy if dy<-1e-8 else 1e9)
 v.extend([(radius*dx,cy+radius*dy,z),(t*dx,cy+t*dy,z)])
for i in range(N):f.append((2*i,2*((i+1)%N),2*((i+1)%N)+1,2*i+1))
def mesh(name,verts,faces,mat):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.materials.append(mat)
 o=bpy.data.objects.new(name,me);c.objects.link(o);return o
ceiling=mesh('F08B_CeilingAroundDome',v,f,steel)
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
dome=mesh('F08B_ObservationDome',v,f,bpy.data.materials['F08B_WeatheredConcrete'])
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
 tube('F08B_DomeRib_%02d'%k,[(radius*math.cos(t)*math.cos(a),cy+radius*math.cos(t)*math.sin(a),z+rise*math.sin(t)-.06) for t in [j*math.pi/2/48 for j in range(49)]],.055,iron)
for rr,zz in [(radius,z-.05),(radius*.72,z+rise*math.sqrt(1-.72**2)-.04)]:
 tube('F08B_DomeRing',[(rr*math.cos(math.tau*i/128),cy+rr*math.sin(math.tau*i/128),zz) for i in range(129)],.075,iron)
# Clip straight ceiling beams at the circular opening.
for o in list(s.objects):
 if o.name.startswith('CeilingBeam_') and abs(o.location.y-cy)<radius:
  half=math.sqrt(radius**2-(o.location.y-cy)**2)+.08
  o.hide_render=True;o.hide_viewport=True
  for sign in [-1,1]:R['box']('F08B','DomeEdgeBeam',(sign*(11.25+half)/2,o.location.y,o.location.z),(11.25-half,.24,.55),iron)
R['light']('F08B','DomeUplight',(0,8,10.6),(0,8,14.8),1100,(.58,.8,1),5)
# A review camera shows the ceiling; the gameplay camera remains intact.
d=bpy.data.cameras.new('F08B_DomeReview');d.lens=18
o=bpy.data.objects.new(d.name,d);c.objects.link(o);o.location=(0,-8.2,3.4)
o.rotation_euler=(Vector((0,8,7.4))-o.location).to_track_quat('-Z','Y').to_euler()
s['ceiling_revision']='v037 shallow dome: radius 7m, rise 3.8m'
# F06 columns from the screenshot: move all supports to perimeter, clear all cameras.
positions=[(11.5,5),(11.5,15),(3.4,18.4),(-11.5,15),(-11.5,5),(-11.5,-3),(-3.4,18.4),(11.5,-3)]
for i,(x,y) in enumerate(positions):
 suffix='' if i==0 else '.%03d'%i
 for stem in ['F06B_VerdictColumn','F06B_VerdictColumnFoot','F06B_VerdictColumnCap']:
  obj=bpy.data.objects[stem+suffix];obj.location.x=x;obj.location.y=y
# Avoid adjacent duplicate tall 8F data pillars, retain all as perimeter instruments.
bpy.data.objects['DataPillar_0'].location=(-10.4,9.5,0)
bpy.data.objects['DataPillar_1'].location=(10.5,7,0)
s.camera=bpy.data.objects['F08B_DomeReview']
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'DA_F06_F07_F08_F09_F10_Combined_v037_dome_clearance.blend'))
print('v037 saved')
