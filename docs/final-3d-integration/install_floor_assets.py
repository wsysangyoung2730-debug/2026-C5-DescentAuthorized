"""Publish one floor after its export has completed; never modify source art."""
import argparse, json, shutil
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--floor',type=int,required=True)
p.add_argument('--rooms',type=Path,required=True)
p.add_argument('--raw-rooms',type=Path,required=True)
p.add_argument('--actors',type=Path)
p.add_argument('--raw-actors',type=Path)
a=p.parse_args()
root=Path(__file__).resolve().parents[2]
resources=root/'DescentAuthorized/Resources'
rows=json.loads((Path(__file__).parent/'room-contracts.json').read_text())
manifest=resources/'Reality/FinalSceneManifest.json'
installed=json.loads(manifest.read_text())
for row in rows:
    if row['floor']!=a.floor:continue
    source=a.rooms/row['name'];target=resources/row['directory']
    assert (source/(row['resource']+'.usdc')).is_file(),source
    if target.exists():shutil.rmtree(target)
    shutil.copytree(source,target)
    for env in (a.raw_rooms/row['name']).glob('*.hdr'):shutil.copy2(env,target/env.name)
    if a.actors:
        source=a.actors/row['name'];target=resources/'Reality/Actors'/row['name']
        assert (source/(row['asset']+'.usdc')).is_file(),source
        if target.exists():shutil.rmtree(target)
        shutil.copytree(source,target)
        shutil.copy2(a.raw_actors/row['name']/'motion.json',target/'motion.json')
    installed=[r for r in installed if r['resource']!=row['resource']]+[row]
manifest.write_text(json.dumps(sorted(installed,key=lambda r:(-r['floor'],r['role'])),ensure_ascii=False,indent=2)+'\n')
print(f'Installed floor {a.floor}: '+', '.join(r['name'] for r in rows if r['floor']==a.floor))
