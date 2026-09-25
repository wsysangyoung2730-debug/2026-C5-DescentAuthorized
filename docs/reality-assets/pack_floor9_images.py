from PIL import Image
from pathlib import Path
import json,sys,math,unicodedata
if sys.argv[1] == '--cap-high':
 for p in Path(sys.argv[2]).rglob('*'):
  if p.suffix.lower() not in ['.png','.jpg','.jpeg']:continue
  im=Image.open(p)
  if max(im.size)>2048:
   im.thumbnail((2048,2048),Image.Resampling.LANCZOS);im.save(p)
 sys.exit(0)
if sys.argv[1] == '--dimensions':
 print(json.dumps({unicodedata.normalize('NFC',str(p.resolve())): Image.open(p).size for p in Path(sys.argv[2]).rglob('*') if p.suffix.lower() in ['.png','.jpg','.jpeg']}))
 sys.exit(0)
p=Path(sys.argv[1]);plan=json.loads(p.read_text());result={}
if len(sys.argv)>2:
 out=Path(plan['out'])
 for quality,cap in [('medium',1024),('low',512)]:
  result[quality]={}
  for ref in plan['refs']:
   src=out/ref
   if src.suffix.lower() not in ['.png','.jpg','.jpeg']:continue
   im=Image.open(src)
   if max(im.size)<=cap:continue
   target=out/'textures'/quality/(src.stem+src.suffix);target.parent.mkdir(parents=True,exist_ok=True)
   im.thumbnail((cap,cap),Image.Resampling.LANCZOS);im.save(target)
   result[quality][ref]='./'+str(target.relative_to(out))
else:
 out=Path(plan['out']);out.mkdir(parents=True,exist_ok=True)
 for gi,g in enumerate(plan['groups']):
  size=2048;pad=8;x=y=row=page=0;canvas=Image.new('RGB',(size,size));result[str(gi)]={}
  def save():
   tiles=[t for t in result[str(gi)].values() if t['page']==page]
   if not tiles:return
   width=max(t['rect'][0]+t['rect'][2]+pad for t in tiles)
   height=max(t['rect'][1]+t['rect'][3]+pad for t in tiles)
   for tile in tiles:tile['dimensions']=[width,height]
   canvas.crop((0,0,width,height)).save(out/(g['prefix']+'_'+str(page)+'.jpg'),quality=94,subsampling=0)
  images=[]
  for name in g['files']:
   im=Image.open(name).convert('RGB');im.thumbnail((512,512),Image.Resampling.LANCZOS);images.append((name,im))
  for name,im in sorted(images,key=lambda e:e[1].height,reverse=True):
   w,h=im.size
   if x+w+2*pad>size:x=0;y+=row;row=0
   if y+h+2*pad>size:save();page+=1;canvas=Image.new('RGB',(size,size));x=y=row=0
   # Edge extrusion prevents bilinear/mipmap seams between tiles.
   canvas.paste(im,(x+pad,y+pad))
   canvas.paste(im.crop((0,0,1,h)).resize((pad,h)),(x,y+pad));canvas.paste(im.crop((w-1,0,w,h)).resize((pad,h)),(x+pad+w,y+pad))
   canvas.paste(canvas.crop((x,y+pad,x+w+2*pad,y+pad+1)).resize((w+2*pad,pad)),(x,y));canvas.paste(canvas.crop((x,y+pad+h-1,x+w+2*pad,y+pad+h)).resize((w+2*pad,pad)),(x,y+pad+h))
   result[str(gi)][name]={'page':page,'file':g['prefix']+'_'+str(page)+'.jpg','size':size,'rect':[x+pad,y+pad,w,h]}
   x+=w+2*pad;row=max(row,h+2*pad)
  save()
p.with_suffix('.result.json').write_text(json.dumps(result))
