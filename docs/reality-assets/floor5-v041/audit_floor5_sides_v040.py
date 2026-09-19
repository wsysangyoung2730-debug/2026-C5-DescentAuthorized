import bpy,runpy,json,itertools
from pathlib import Path
OUT=Path(__file__).parent;F=runpy.run_path(str(OUT/'build_floor5_v039.py'))
report={}
for p,sn in F['SCENES'].items():
    s=bpy.data.scenes[sn];bpy.context.window.scene=s;bpy.context.view_layer.update()
    roots=[o for o in s.objects if o.get('source_asset')]
    bounds={o.name:F['bounds'](o) for o in roots};overlaps=[];outside=[];w=14 if p.endswith('B') else 12
    for a,b in itertools.combinations(roots,2):
        if not (a.get('side_dressing') or b.get('side_dressing')):continue
        lo,hi=bounds[a.name];bl,bh=bounds[b.name]
        depth=[min(hi[i],bh[i])-max(lo[i],bl[i]) for i in range(3)]
        if min(depth)>.08:overlaps.append([a.name,b.name,depth])
    for o in roots:
        if o.get('side_dressing'):
            lo,hi=bounds[o.name]
            if lo.x < -w or hi.x>w or lo.y < -17:outside.append(o.name)
    report[p]={'added_props':sum(bool(o.get('side_dressing')) for o in roots),'prop_overlaps':overlaps,'outside_room':outside}
assert all(not r['prop_overlaps'] and not r['outside_room'] for r in report.values()),report
baseline=json.loads((OUT/'floor5_side_baseline_v040.json').read_text())
report['other_scenes_unchanged']=all(F['fingerprint'](bpy.data.scenes[n])==v for n,v in baseline.items())
assert report['other_scenes_unchanged']
(OUT/'AUDIT_floor5_sides_v040.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
