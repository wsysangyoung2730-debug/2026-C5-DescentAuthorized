"""Run with Blender's USD Python. Pillow work uses the system Python separately.
Only opaque, base-color-only USD Preview materials with identical constants and
in-range st UVs are packed. Other shaders and all object transforms are preserved.
"""
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt
from pathlib import Path
import json,subprocess,shutil,collections,argparse,unicodedata
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-root',type=Path,required=True,help='Original unoptimized repository snapshot')
parser.add_argument('--output',type=Path,required=True,help='New, nonexistent output directory')
parser.add_argument('--image-python',default='/usr/bin/python3',help='Python with Pillow installed')
args=parser.parse_args()
repo=args.source_root.resolve()
dest=args.output.resolve()
dest.mkdir(parents=True,exist_ok=False)
reports=[]
for folder,filename in [('Scenes/Floor09/ArchiveRedesign','floor09_archive_redesign'),('Actors/RecordAdministrator','record_administrator')]:
 src=repo/'DescentAuthorized/Resources/Reality'/folder
 out=dest/folder
 shutil.copytree(src,out,dirs_exist_ok=True)
 subprocess.run([args.image_python,str(Path(__file__).with_name('pack_floor9_images.py')),'--cap-high',str(out/'textures')],check=True)
 stage=Usd.Stage.Open(str(src/(filename+'.usdc')))
 stage=Usd.Stage.Open(stage.Flatten())
 dimensions=json.loads(subprocess.check_output([args.image_python,str(Path(__file__).with_name('pack_floor9_images.py')),'--dimensions',str(src)]))
 groups=collections.defaultdict(list)
 originalmats=[p for p in stage.Traverse() if p.GetTypeName()=='Material']
 for p in stage.Traverse():
  if not p.IsA(UsdGeom.Mesh) or any(c.IsA(UsdGeom.Subset) for c in p.GetChildren()):continue
  mesh=UsdGeom.Mesh(p);uv=UsdGeom.PrimvarsAPI(p).GetPrimvar('st')
  if not uv or not uv.Get():continue
  if any(min(v)<-0.0001 or max(v)>1.0001 for v in uv.Get()):continue
  material,_=UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()
  if not material:continue
  shader=material.ComputeSurfaceSource()[0]
  if not shader or shader.GetIdAttr().Get()!='UsdPreviewSurface':continue
  color=shader.GetInput('diffuseColor');connection=color.GetConnectedSource() if color else None
  if not connection:continue
  tex=UsdShade.Shader(connection[0].GetPrim())
  if tex.GetIdAttr().Get()!='UsdUVTexture' or str(connection[1])!='rgb':continue
  if any(i.HasConnectedSource() for i in shader.GetInputs() if i.GetBaseName()!='diffuseColor'):continue
  if shader.GetInput('opacity') and shader.GetInput('opacity').Get()!=1:continue
  if any(tex.GetInput(n) and tex.GetInput(n).Get() is not None for n in ['scale','bias']):continue
  stinput=tex.GetInput('st');stconn=stinput.GetConnectedSource() if stinput else None
  if not stconn or stconn[0].GetPrim().GetAttribute('info:id').Get()!='UsdPrimvarReader_float2':continue
  if stconn[0].GetPrim().GetAttribute('inputs:varname').Get()!='st':continue
  asset=tex.GetInput('file').Get();path=Path(asset.resolvedPath) if asset.resolvedPath else src/asset.path
  if path.suffix.lower() not in ['.png','.jpg','.jpeg']:continue
  # Preserve large detailed hero textures independently; atlas only small parts.
  if max(dimensions[unicodedata.normalize('NFC',str(path.resolve()))]) >= 1024:continue
  signature=tuple(sorted((str(i.GetBaseName()),str(i.Get())) for i in shader.GetInputs() if i.GetBaseName()!='diffuseColor'))
  signature+=(('sourceColorSpace',str(tex.GetInput('sourceColorSpace').Get())),)
  groups[signature].append((p,material,shader,path))
 plan=[];groupdata=[]
 for signature,entries in groups.items():
  paths=sorted(set(str(e[3]) for e in entries))
  if len(paths)<2:continue
  idx=len(plan);plan.append({'files':paths,'prefix':filename+'_atlas_'+str(idx)})
  groupdata.append(entries)
 planfile=dest/(filename+'_plan.json');planfile.write_text(json.dumps({'groups':plan,'out':str(out/'textures/atlas')}))
 subprocess.run([args.image_python,str(Path(__file__).with_name('pack_floor9_images.py')),str(planfile)],check=True)
 layouts=json.loads(planfile.with_suffix('.result.json').read_text())
 made={}
 for gi,entries in enumerate(groupdata):
  for prim,old,shader,path in entries:
   tile=layouts[str(gi)][str(path)];page=tile['page'];key=(gi,page)
   if key not in made:
    parent=str(old.GetPath().GetParentPath());mp=parent+'/F09_Atlas_%d_%d'%key
    material=UsdShade.Material.Define(stage,mp);bs=UsdShade.Shader.Define(stage,mp+'/Surface');bs.CreateIdAttr('UsdPreviewSurface')
    for inp in shader.GetInputs():
     if inp.GetBaseName()!='diffuseColor' and inp.Get() is not None:bs.CreateInput(inp.GetBaseName(),inp.GetTypeName()).Set(inp.Get())
    tex=UsdShade.Shader.Define(stage,mp+'/Texture');tex.CreateIdAttr('UsdUVTexture');tex.CreateInput('file',Sdf.ValueTypeNames.Asset).Set('./textures/atlas/'+tile['file']);tex.CreateInput('sourceColorSpace',Sdf.ValueTypeNames.Token).Set('sRGB')
    tex.CreateInput('wrapS',Sdf.ValueTypeNames.Token).Set('clamp');tex.CreateInput('wrapT',Sdf.ValueTypeNames.Token).Set('clamp')
    uvread=UsdShade.Shader.Define(stage,mp+'/UV');uvread.CreateIdAttr('UsdPrimvarReader_float2');uvread.CreateInput('varname',Sdf.ValueTypeNames.Token).Set('st')
    tex.CreateInput('st',Sdf.ValueTypeNames.Float2).ConnectToSource(uvread.ConnectableAPI(),'result');bs.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).ConnectToSource(tex.ConnectableAPI(),'rgb');material.CreateSurfaceOutput().ConnectToSource(bs.ConnectableAPI(),'surface');made[key]=material
   uv=UsdGeom.PrimvarsAPI(prim).GetPrimvar('st');x,y,w,h=tile['rect'];width,height=tile['dimensions']
   # Pillow origin is top-left; USD UV origin is bottom-left.
   uv.Set(Vt.Vec2fArray([Gf.Vec2f((x+float(v[0])*w)/width,(height-y-h+float(v[1])*h)/height) for v in uv.Get()]))
   UsdShade.MaterialBindingAPI.Apply(prim).Bind(made[key])
 # Remove old unbound materials; keep all material bindings including subsets.
 used=set()
 for p in stage.Traverse():
  for rel in p.GetRelationships():
   if str(rel.GetName()).startswith('material:binding'):used.update(str(t) for t in rel.GetTargets())
 for p in originalmats:
  if str(p.GetPath()) not in used:stage.RemovePrim(p.GetPath())
 # Flatten resolves source assets to absolute paths; remap into the copied tree.
 for p in stage.Traverse():
  for a in p.GetAttributes():
   if a.GetTypeName()==Sdf.ValueTypeNames.Asset and a.Get():
    v=a.Get();name=v.path
    if str(src) in name:name='./'+str(Path(name).relative_to(src));a.Set(Sdf.AssetPath(name))
 stage.GetRootLayer().Export(str(out/(filename+'.usdc')))
 # Build complete quality variants so all textures, including the actor, follow quality.
 base=Usd.Stage.Open(str(out/(filename+'.usdc')))
 refs=set()
 for p in base.Traverse():
  for a in p.GetAttributes():
   if a.GetTypeName()==Sdf.ValueTypeNames.Asset and a.Get():refs.add(a.Get().path)
 resizeplan=dest/(filename+'_variants.json');resizeplan.write_text(json.dumps({'out':str(out),'refs':sorted(refs)}))
 subprocess.run([args.image_python,str(Path(__file__).with_name('pack_floor9_images.py')),str(resizeplan),'variants'],check=True)
 maps=json.loads(resizeplan.with_suffix('.result.json').read_text())
 for quality in ['medium','low']:
  variant=Usd.Stage.Open(base.Flatten())
  for p in variant.Traverse():
   for a in p.GetAttributes():
    if a.GetTypeName()==Sdf.ValueTypeNames.Asset and a.Get():
     v=a.Get();rel='./'+str(Path(v.path).relative_to(out)) if v.path.startswith(str(out)) else v.path
     a.Set(Sdf.AssetPath(maps[quality].get(rel,rel)))
  variant.GetRootLayer().Export(str(out/(filename+'_'+quality+'.usdc')))
 # Only ship assets referenced by the three final stages, plus motion metadata.
 keep=set()
 for quality in ['', '_medium','_low']:
  st=Usd.Stage.Open(str(out/(filename+quality+'.usdc')))
  for p in st.Traverse():
   for a in p.GetAttributes():
    if a.GetTypeName()==Sdf.ValueTypeNames.Asset and a.Get():keep.add(unicodedata.normalize('NFC',str(Path(a.Get().resolvedPath).resolve())))
 for p in (out/'textures').rglob('*'):
  if p.is_file() and unicodedata.normalize('NFC',str(p.resolve())) not in keep:p.unlink()
 reports.append({'asset':filename,'packed_meshes':sum(len(e) for e in groupdata),'atlas_materials':len(made),'before_materials':len(originalmats),'after_materials':sum(p.GetTypeName()=='Material' for p in stage.Traverse())})
 print(reports[-1],flush=True)
(dest/'report.json').write_text(json.dumps(reports,indent=2))
