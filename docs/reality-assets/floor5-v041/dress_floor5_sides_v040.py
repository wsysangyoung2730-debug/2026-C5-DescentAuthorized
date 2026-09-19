"""Add dense, functional prop groups along both 5F side walls. Run once on v039."""
import bpy,runpy,math,json
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).parent
F=runpy.run_path(str(OUT/'build_floor5_v039.py'))

def move(name,loc):
    o=bpy.data.objects[name];o.location=loc;return o

def add(p,key,label,loc,size,axis='z',angle=0):
    root=F['imported'](p,'floor5-'+key,p+'_SideDense_'+label,loc,size,axis,math.radians(angle))
    root['revision']='v040';root['side_dressing']=True
    for o in [root]+list(root.children_recursive):
        for c in list(o.users_collection):c.objects.unlink(o)
        F['collection'](p,'SideDressing_v040').objects.link(o)
    return root

def top(p,key,label,base,width):
    bpy.context.view_layer.update();lo,hi=F['bounds'](base)
    return add(p,key,label,((lo.x+hi.x)/2,(lo.y+hi.y)/2,hi.z+.025),width,'x')

def run():
    assert not bpy.data.collections.get('F05A_SideDressing_v040'),'v040 already applied'
    snapshot={s.name:F['fingerprint'](s) for s in bpy.data.scenes if s.name not in F['SCENES'].values()}
    (OUT/'floor5_side_baseline_v040.json').write_text(json.dumps(snapshot,indent=2))
    m=F['mats']()
    # Align the existing tall pieces into banks and separate the lower foreground cases.
    move('F05A_Portraits',(-10.45,-7.6,0))
    move('F05A_ReelBank01',(-10.4,-1.15,0))
    move('F05A_ReelBank02',(-10.4,5.25,0))
    move('F05A_NearRightReliquary',(10.65,-6.55,0))
    move('F05A_SealedCasket',(8.5,-5.8,0))
    move('F05A_SignatureTable',(8.1,4.8,0))
    move('F05B_PortraitsLeft',(-12.45,-8.3,0))
    move('F05B_ComparisonDesk',(-10.5,-.25,0))
    p='F05A'
    for key,label,loc,h,angle in [
      ('memory-reliquary-cabinet','L_Reliquary',(-10.65,-4.35,0),4.2,70),
      ('blank-mask-display-rack','L_MaskBank',(-10.65,2.05,0),4.4,75),
      ('archive-data-spine-panel','L_DataBank',(-10.9,8.1,0),4.5,85),
      ('cracked-echo-mirror','L_EchoFront',(-10.9,-9.9,0),3.2,70),
      ('blank-mask-display-rack','R_MaskBank',(10.65,-3.15,0),4.3,-75),
      ('archive-data-spine-panel','R_DataBank',(10.9,.25,0),4.5,-85),
      ('memory-tape-reel-server','R_ReelBank',(10.6,3.4,0),3.95,-70),
      ('mnemonic-vial-carousel','R_VialBank',(10.5,7.3,0),3.6,-30),
      ('archive-data-spine-panel','R_FrontSpine',(10.7,-9.5,0),4.15,-70),
      ('echo-playback-terminal','L_ReadingStation',(-7.9,-3.8,0),2.2,35),
      ('wax-imprint-seal-press','R_SealStation',(7.85,-8.3,0),2.2,-35),
    ]:add(p,key,label,loc,h,angle=angle)
    for label,loc,yaw in [('L_CaseFront',(-8.2,-7.65,0),35),('L_CaseRear',(-8.0,7.6,0),65),('R_CaseNear',(8.1,-1.7,0),-25)]:
        root=add(p,'memory-scroll-cylinder-crate',label,loc,1.7,'x',yaw)
        top(p,'missing-name-tag-set',label+'_Tags',root,.52)
    root=add(p,'sealed-memory-casket','L_SealedStack',(-8.0,-.6,0),1.8,'x',60)
    top(p,'porcelain-mask-shard-set','L_SealedStack_Fragment',root,.75)
    p='F05B'
    for key,label,loc,h,angle in [
      ('blank-mask-display-rack','L_FrontMasks',(-12.6,-5.0,0),4.6,75),
      ('memory-reliquary-cabinet','L_Reliquary',(-12.8,-1.85,0),4.3,85),
      ('archive-data-spine-panel','L_DataBank',(-13.0,1.4,0),4.9,90),
      ('blank-mask-display-rack','L_OriginalMasks',(-12.8,5.15,0),4.65,85),
      ('archive-data-spine-panel','L_RearSpine',(-13.0,10.95,0),4.4,90),
      ('blank-mask-display-rack','R_FrontMasks',(12.6,-8.5,0),4.5,-75),
      ('memory-reliquary-cabinet','R_Reliquary',(12.8,-1.65,0),4.5,-85),
      ('archive-data-spine-panel','R_DataBank',(13.0,1.5,0),4.9,-90),
      ('blank-mask-display-rack','R_OriginalMasks',(13.0,4.05,0),3.7,-85),
      ('cracked-echo-mirror','R_RearEcho',(13.25,9.25,0),4.0,-90),
      ('identity-collation-console','L_FrontVerifier',(-9.9,-6.3,0),2.5,40),
      ('mnemonic-extraction-helmet','R_FrontHelmet',(9.45,-7.7,0),2.55,-30),
      ('echo-playback-terminal','R_Playback',(9.65,-3.5,0),2.4,-40),
    ]:add(p,key,label,loc,h,angle=angle)
    for label,loc,yaw in [('L_RecordCase',(-10.2,-3.4,0),65),('R_SealedRecords',(8.65,2.65,0),-40)]:
        root=add(p,'memory-scroll-cylinder-crate',label,loc,1.7,'x',yaw)
        top(p,'missing-name-tag-set',label+'_Tags',root,.5)
    root=add(p,'sealed-memory-casket','R_CasketFront',(8.4,-.25,0),1.85,'x',-50)
    top(p,'porcelain-mask-shard-set','R_CasketFront_Fragment',root,.72)
    # Continuous cornices and low display strips make the banks read as archive bays.
    for p in F['SCENES']:
        boss=p.endswith('B');w=14 if boss else 12;s=bpy.data.scenes[F['SCENES'][p]]
        for sign in [-1,1]:
            for y in [-6.2,1.0,7.5]:
                x=sign*(w-.45)
                F['box'](p,'SideArchiveFascia_v040',(x,y,5.35 if boss else 4.95),(.34,5.9,.18),m['iron'],part='SideDressing_v040')
                F['box'](p,'SideArchiveTrim_v040',(x-sign*.18,y,5.3 if boss else 4.9),(.035,5.8,.055),m['brass'],part='SideDressing_v040')
            F['light'](p,'SideArchiveWash_v040',(sign*(w-3.5),-4.4,4.6),(sign*(w-.5),-1.5,2),450,(1,.78,.53),4)
        # Genuine head-turn cameras at the original combat eye, no camera reposition cheat.
        main=s.objects['F05_iPad_MainCamera' if boss else 'F05A_iPad_MainCamera']
        for side,sign in [('Left',-1),('Right',1)]:
            for deg in [70,90]:
                loc=main.location.copy();direction=Vector((sign*math.sin(math.radians(deg)),math.cos(math.radians(deg)),-.06))
                F['camera'](p,p+'_HeadTurn'+str(deg)+'_'+side,loc,loc+direction*10,main.data.lens)
        s['layout_version']='v040';s['side_dressing']='Dense archive banks with lower foreground workstations; inspected from original combat eye at 70 and 90 degrees'
    bpy.context.view_layer.update()
    print('Added asset placements',sum(o.get('side_dressing',False) for o in bpy.data.objects))

if __name__=='__main__':run()
