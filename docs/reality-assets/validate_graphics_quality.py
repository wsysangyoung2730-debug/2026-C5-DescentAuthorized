from pathlib import Path
from pxr import Usd,UsdGeom
import struct,json
import sys
r=Path(sys.argv[1])/'DescentAuthorized/Resources/Reality/Scenes/Floor09/ArchiveRedesign'
for quality,size in [('low',512),('medium',1024),('high',2048)]:
 name='floor09_archive_redesign'+('' if quality=='high' else '_'+quality)+'.usdc';s=Usd.Stage.Open(str(r/name));n=0
 assert len([p for p in s.Traverse() if p.IsA(UsdGeom.Camera)])==3
 for p in s.Traverse():
  a=p.GetAttribute('inputs:file')
  if a and a.Get() and Path(a.Get().path).name.startswith('F09_'):
   f=r/a.Get().path;assert struct.unpack('>II',f.read_bytes()[16:24])==(size,size),(quality,f);n+=1
 assert n==12,(quality,n)
 for track in json.loads((r/'floor09_reward_motion.json').read_text())['tracks']:
  assert any(str(p.GetName())==track['entity'] for p in s.Traverse())
 print(quality,size,'12 textures, 3 cameras, 13 motion entities OK')
