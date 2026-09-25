"""Consolidate byte-identical room textures without changing pixels or quality tiers."""
import hashlib,json,collections,shutil,os
from pathlib import Path
from pxr import Usd,Sdf
root=Path(__file__).resolve().parents[2]/'DescentAuthorized/Resources'
rows=json.loads((root/'Reality/FinalSceneManifest.json').read_text());groups=collections.defaultdict(list)
for r in rows:
 for p in (root/r['directory']/'textures').rglob('*'):
  if p.is_file():groups[hashlib.sha256(p.read_bytes()).hexdigest()].append(p.resolve())
shared=root/'Reality/Shared/FinalTextures';shared.mkdir(parents=True,exist_ok=True);mapping={};savings=0
for digest,files in groups.items():
 if len(files)<2:continue
 target=(shared/(digest+files[0].suffix)).resolve();shutil.copy2(files[0],target)
 savings+=files[0].stat().st_size*(len(files)-1)
 for f in files:mapping[f]=target
changes=[]
for r in rows:
 for suffix in ['', '_medium', '_low']:
  file=root/r['directory']/(r['resource']+suffix+'.usdc');stage=Usd.Stage.Open(str(file));count=0
  for prim in stage.Traverse():
   for attr in prim.GetAttributes():
    if attr.GetTypeName()!=Sdf.ValueTypeNames.Asset:continue
    value=attr.Get()
    if not value or not value.path:continue
    source=Path(value.resolvedPath or file.parent/value.path).resolve()
    if source in mapping:
     attr.Set(Sdf.AssetPath(os.path.relpath(mapping[source],file.parent)));count+=1
  stage.GetRootLayer().Save();changes.append({'file':str(file.relative_to(root)),'reboundTextures':count})
for file in mapping:file.unlink()
report={'duplicatesRemoved':len(mapping)-sum(len(v)>1 for v in groups.values()),'savedBytes':savings,'method':'SHA-256 exact byte match; no re-encoding','layers':changes}
(Path(__file__).parent/'validation/texture-deduplication.json').write_text(json.dumps(report,indent=2)+'\n')
print('Saved MiB:',round(savings/2**20,2))
