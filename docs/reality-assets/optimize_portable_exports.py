import argparse
import collections
import hashlib
import json
import subprocess
import unicodedata
from pathlib import Path

from pxr import Sdf, Usd, UsdGeom


parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--image-python", default="/usr/bin/python3")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
image_helper = Path(__file__).with_name("process_v27_textures.py")


def normalized(path):
    return unicodedata.normalize("NFC", str(Path(path).resolve()))


def asset_attributes(stage):
    for prim in stage.Traverse():
        for attr in prim.GetAttributes():
            if attr.GetTypeName() != Sdf.ValueTypeNames.Asset:
                continue
            value = attr.Get()
            if value and value.path:
                yield attr, value


def material_signature(material):
    root = str(material.GetPath())
    records = []
    for prim in Usd.PrimRange(material):
        path = str(prim.GetPath()).replace(root, "<material>", 1)
        attrs = []
        for attr in prim.GetAttributes():
            value = attr.Get()
            if isinstance(value, Sdf.AssetPath):
                value = value.path
            connections = [
                str(connection).replace(root, "<material>", 1)
                for connection in attr.GetConnections()
            ]
            attrs.append((str(attr.GetName()), str(attr.GetTypeName()), repr(value), connections))
        rels = []
        for rel in prim.GetRelationships():
            targets = [str(target).replace(root, "<material>", 1) for target in rel.GetTargets()]
            rels.append((str(rel.GetName()), targets))
        records.append((path, prim.GetTypeName(), sorted(attrs), sorted(rels)))
    return repr(records)


def deduplicate_materials(stage):
    groups = collections.defaultdict(list)
    for prim in stage.Traverse():
        if prim.GetTypeName() == "Material":
            groups[material_signature(prim)].append(prim)
    replacements = {}
    for materials in groups.values():
        if len(materials) < 2:
            continue
        canonical = materials[0].GetPath()
        for duplicate in materials[1:]:
            replacements[str(duplicate.GetPath())] = canonical
    if not replacements:
        return 0
    for prim in stage.Traverse():
        for rel in prim.GetRelationships():
            targets = rel.GetTargets()
            updated = [replacements.get(str(target), target) for target in targets]
            if updated != targets:
                rel.SetTargets(updated)
    for duplicate in sorted(replacements, key=len, reverse=True):
        stage.RemovePrim(duplicate)
    return len(replacements)


reports = []
for source_usdc in sorted(args.source.glob("*/*.usdc")):
    asset_name = source_usdc.stem
    destination = args.output / source_usdc.parent.name
    texture_root = destination / "textures"
    destination.mkdir(parents=True)

    source_stage = Usd.Stage.Open(str(source_usdc))
    # RealityKit's importer can drop face-varying indices. Expand every indexed
    # UV set before packaging, preserving exactly the Blender corner-to-UV map.
    for prim in source_stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        # Blender writes constant mesh data at the first animation frame.
        # Give importers a default value without changing animated attributes.
        for attr in prim.GetAttributes():
            samples = attr.GetTimeSamples()
            if len(samples) == 1:
                value = attr.Get(Usd.TimeCode(samples[0]))
                attr.ClearAtTime(Usd.TimeCode(samples[0]))
                attr.Set(value)
        for uv in UsdGeom.PrimvarsAPI(prim).GetPrimvars():
            if uv.GetTypeName() in (Sdf.ValueTypeNames.TexCoord2fArray, Sdf.ValueTypeNames.Float2Array) and uv.IsIndexed():
                times = sorted(set(uv.GetTimeSamples() + uv.GetIndicesAttr().GetTimeSamples()))
                samples = [(time, uv.ComputeFlattened(Usd.TimeCode(time))) for time in times]
                default = uv.ComputeFlattened() if uv.Get() is not None and len(uv.GetIndices()) > 0 else None
                if default is not None: uv.Set(default)
                for time, values in samples: uv.Set(values, Usd.TimeCode(time))
                uv.BlockIndices()
    source_files = {}
    for _, value in asset_attributes(source_stage):
        resolved = Path(value.resolvedPath) if value.resolvedPath else source_usdc.parent / value.path
        if resolved.is_file():
            source_files[normalized(resolved)] = resolved

    quality_maps = {}
    shipped_content = {}
    for quality, cap in (("high", 2048), ("medium", 1024), ("low", 512)):
        quality_output = texture_root if quality == "high" else texture_root / quality
        plan_path = args.output / f"{asset_name}_{quality}_textures.json"
        plan_path.write_text(
            json.dumps(
                {
                    "cap": cap,
                    "output": str(quality_output),
                    "sources": [str(path) for path in source_files.values()],
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        subprocess.run([args.image_python, str(image_helper), str(plan_path)], check=True)
        generated = json.loads(plan_path.with_suffix(".result.json").read_text())
        quality_maps[quality] = {}
        generated_relatives = {}
        for source_key, filename in generated.items():
            if filename in generated_relatives:
                quality_maps[quality][source_key] = generated_relatives[filename]
                continue
            generated_path = quality_output / filename
            digest = hashlib.sha256(generated_path.read_bytes()).hexdigest()
            if digest in shipped_content:
                generated_path.unlink()
                relative = shipped_content[digest]
            else:
                relative = str(generated_path.relative_to(destination))
                shipped_content[digest] = relative
            generated_relatives[filename] = relative
            quality_maps[quality][source_key] = relative

    quality_reports = {}
    high_stage = Usd.Stage.Open(source_stage.Flatten())
    for attr, value in asset_attributes(high_stage):
        resolved = Path(value.resolvedPath) if value.resolvedPath else source_usdc.parent / value.path
        key = normalized(resolved)
        if key in quality_maps["high"]:
            attr.Set(Sdf.AssetPath(f"./{quality_maps['high'][key]}"))
    deduplicated = deduplicate_materials(high_stage)
    high_usdc = destination / f"{asset_name}.usdc"
    high_stage.GetRootLayer().Export(str(high_usdc))
    quality_reports["high"] = {
        "stageMB": round(high_usdc.stat().st_size / 1024 / 1024, 2),
        "deduplicatedMaterials": deduplicated,
    }

    # Medium and low only override texture paths on top of the high stage.
    # This keeps geometry in one USDC instead of shipping it three times.
    flattened_source = Usd.Stage.Open(source_stage.Flatten())
    for quality in ("medium", "low"):
        output_usdc = destination / f"{asset_name}_{quality}.usdc"
        stage = Usd.Stage.CreateNew(str(output_usdc))
        stage.GetRootLayer().subLayerPaths = [f"./{asset_name}.usdc"]
        for attr, value in asset_attributes(flattened_source):
            resolved = Path(value.resolvedPath) if value.resolvedPath else source_usdc.parent / value.path
            key = normalized(resolved)
            if key not in quality_maps[quality]:
                continue
            target = f"./{quality_maps[quality][key]}"
            if target == f"./{quality_maps['high'][key]}":
                continue
            override = stage.OverridePrim(attr.GetPrim().GetPath())
            override.CreateAttribute(
                attr.GetName(),
                Sdf.ValueTypeNames.Asset,
                custom=attr.IsCustom(),
            ).Set(Sdf.AssetPath(target))
        default_prim = high_stage.GetDefaultPrim()
        if default_prim:
            stage.SetDefaultPrim(stage.OverridePrim(default_prim.GetPath()))
        stage.GetRootLayer().Save()
        quality_reports[quality] = {
            "stageMB": round(output_usdc.stat().st_size / 1024 / 1024, 2),
            "deduplicatedMaterials": 0,
        }

    reports.append(
        {
            "asset": asset_name,
            "sourceFiles": len(source_files),
            "highFiles": len(set(quality_maps["high"].values())),
            "mediumFiles": len(set(quality_maps["medium"].values())),
            "lowFiles": len(set(quality_maps["low"].values())),
            "qualities": quality_reports,
        }
    )

(args.output / "optimization_report.json").write_text(
    json.dumps(reports, ensure_ascii=False, indent=2)
)
print(json.dumps(reports, ensure_ascii=False, indent=2))
