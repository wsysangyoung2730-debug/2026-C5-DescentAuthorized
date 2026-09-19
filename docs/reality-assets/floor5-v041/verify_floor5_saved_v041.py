import bpy,json,os
from pathlib import Path
expected=['DA_F05A_MemoryOmissionResidue','DA_F05B_OriginalMemoryAdministrator']
assert sorted(s.name for s in bpy.data.scenes)==expected
report={'file':bpy.data.filepath,'scenes':{},'missing_images':[]}
for name in expected:
    s=bpy.data.scenes[name]
    assert s.camera and s.camera.name.endswith('Overview')
    assert not any('RewardScroll' in o.name for o in s.objects)
    if name=='DA_F05A_MemoryOmissionResidue':assert not any('CombatStage' in o.name or 'ArenaCircuit' in o.name for o in s.objects)
    else:assert 'F05B_CombatStage' in s.objects
    report['scenes'][name]={'objects':len(s.objects),'camera':s.camera.name}
for i in bpy.data.images:
    if i.users and i.source=='FILE' and not i.packed_file and not os.path.exists(bpy.path.abspath(i.filepath)):
        report['missing_images'].append(i.name)
assert not report['missing_images']
Path(bpy.data.filepath).with_name('VERIFY_floor5_v041.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print('FLOOR5_SAVED_VERIFIED',json.dumps(report,ensure_ascii=False))
