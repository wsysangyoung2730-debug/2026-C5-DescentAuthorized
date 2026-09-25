import bpy,runpy,math
from pathlib import Path
OUT=Path(__file__).parent
F=runpy.run_path(str(OUT/'build_floor5_v039.py'))
D=runpy.run_path(str(OUT/'dress_floor5_sides_v040.py'))
m=F['mats']();box=F['box'];part='SideDressing_v040'
assert not bpy.data.objects.get('F05A_FrontReturnWall_v040')
for p,sn in F['SCENES'].items():
    bpy.context.window.scene=bpy.data.scenes[sn]
    boss=p.endswith('B');w=14 if boss else 12;h=8 if boss else 5.7
    box(p,'FrontReturnWall_v040',(0,-17.16,h/2),(w*2+.64,.32,h),m['stone'],part=part)
    box(p,'FrontFoundation_v040',(0,-14,-.23),(w*2,6,.45),m['iron'],part=part)
    for ix in range(-w,w,2):
        for iy in [-17,-15,-13]:box(p,'FrontFloorTile_v040',(ix+1,iy+1,-.025),(1.985,1.985,.06),m['floor'],part=part,bevel=.01)
    for sign in [-1,1]:
        box(p,'SideReturnWall_v040',(sign*(w+.16),-14,h/2),(.32,6,h),m['stone'],part=part)
        for z in [.2,1.1,h-.3]:box(p,'ReturnCornice_v040',(sign*(w-.035),-14,z),(.12,6,.12),m['brass'],part=part)
        for y in [-13,-16.7]:
            box(p,'ReturnPilaster_v040',(sign*(w-.14),y,h/2),(.26,.4,h),m['iron'],part=part)
            box(p,'ReturnCapital_v040',(sign*(w-.16),y,h-.5),(.38,.62,.17),m['brass'],part=part)
        D['add'](p,'memory-tape-reel-server',('L' if sign<0 else 'R')+'_CornerReel',(sign*(w-1.4),-12.4,0),4.1 if boss else 3.8,angle=-sign*85)
        D['add'](p,'memory-reliquary-cabinet',('L' if sign<0 else 'R')+'_CornerArchive',(sign*(w-1.4),-15.3,0),4.1 if boss else 3.8,angle=-sign*85)
        F['light'](p,'CornerArchiveWash_v040',(sign*(w-3.2),-13,4.7),(sign*(w-.5),-13,2),600,(1,.82,.62),4)
    if boss:
        box(p,'FrontCeiling_v040',(0,-14,h+.28),(28,6,.4),m['stone'],part=part)
        for x in [-10,-5,0,5,10]:box(p,'FrontCofferBeam_v040',(x,-14,h-.1),(.24,6,.4),m['brass'],part=part)
        for y in [-12,-16.8]:box(p,'FrontCrossBeam_v040',(0,y,h-.15),(w*2,.28,.42),m['iron'],part=part)
    else:
        N=48;vs=[(w*math.cos(math.pi*i/N),y,h+1.8*math.sin(math.pi*i/N)) for y in [-17,-11] for i in range(N+1)]
        roof=F['mesh'](p,'FrontVault_v040',vs,[(i,i+1,N+2+i,N+1+i) for i in range(N)],m['ivory'],part)
        sol=roof.modifiers.new('Vault shell','SOLIDIFY');sol.thickness=.22
        F['mesh'](p,'FrontTympanum_v040',[(0,-17.16,h)]+[(w*math.cos(math.pi*i/N),-17.16,h+1.8*math.sin(math.pi*i/N)) for i in range(N+1)],[(0,i+1,i+2) for i in range(N)],m['stone'],part)
        for y in [-14,-16.8]:F['tube'](p,'FrontVaultRib_v040',[(w*math.cos(math.pi*i/N),y,h+1.8*math.sin(math.pi*i/N)-.1) for i in range(N+1)],.10,m['brass'],part)
bpy.context.view_layer.update()
print('Closed front side returns; added eight matching archive cabinets')
