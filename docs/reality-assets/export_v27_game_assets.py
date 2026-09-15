import argparse
import bpy
import json
import sys
from pathlib import Path


ASSETS = [
    {
        "scene": "DA_F10_ClosedOffice",
        "filename": "floor10_closed_office",
        "root": "/floor10_closed_office",
        "cameras": {
            "F10_iPad_MainCamera",
            "CAM_F10_TrainingBoard",
            "CAM_F10_RewardSelection",
            "CAM_F10_DescentDoor",
        },
        "lights": {
            "OfficeFront",
            "OfficeLeft",
            "OfficeRight",
            "TrainingViolet",
            "DescentAmber",
            "DocumentFill",
        },
        "forcedRoots": {"DA_STATE_OpenDoor_F10"},
    },
    {
        "scene": "DA_F08A_ResidueIsolation",
        "filename": "floor08_residue_isolation",
        "root": "/floor08_residue_isolation",
        "cameras": {"F08A_iPadCamera", "CAM_F08A_BossAccessDoor"},
        "lights": {"ResidueKey", "CapsuleViolet", "IsolationFill"},
        "forcedRoots": set(),
    },
    {
        "scene": "DA_F08_AdministratorObservatory",
        "filename": "floor08_administrator_observatory",
        "root": "/floor08_administrator_observatory",
        "cameras": {
            "F08_iPad_MainCamera",
            "CAM_F08_RewardSelection",
            "CAM_F08_DescentDoor",
        },
        "lights": {
            "F08B_GameKey_0",
            "F08B_GameKey_1",
            "F08B_GameKey_2",
            "F08B_GameKey_3",
        },
        "forcedRoots": {"DA_STATE_OpenDoor_F08B"},
    },
]


def parse_args():
    values = sys.argv[sys.argv.index("--") + 1 :]
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(values)


def cap_scene_images(scene, limit=2048):
    materials = {
        material
        for obj in scene.objects
        if obj.type == "MESH" and not obj.hide_render
        for material in obj.data.materials
        if material and material.use_nodes
    }
    images = {
        node.image
        for material in materials
        for node in material.node_tree.nodes
        if node.type == "TEX_IMAGE" and node.image
    }
    resized = []
    for image in images:
        width, height = image.size
        if max(width, height) <= limit:
            continue
        ratio = limit / max(width, height)
        image.scale(max(1, round(width * ratio)), max(1, round(height * ratio)))
        resized.append(image.name)
    return resized


args = parse_args()
args.output.mkdir(parents=True, exist_ok=True)
report = []

for asset in ASSETS:
    scene = bpy.data.scenes[asset["scene"]]
    bpy.context.window.scene = scene
    resized = cap_scene_images(scene)
    bpy.ops.object.select_all(action="DESELECT")
    selected = []
    for obj in scene.objects:
        ancestor = obj
        forced = False
        while ancestor:
            if ancestor.name in asset["forcedRoots"]:
                forced = True
                break
            ancestor = ancestor.parent
        include = not obj.hide_render or forced
        if obj.type == "CAMERA":
            include = obj.name in asset["cameras"]
        elif obj.type == "LIGHT":
            include = obj.name in asset["lights"]
        if include:
            if obj.type in {"CAMERA", "LIGHT"}:
                # Blender's USD exporter may prefer the data-block name for
                # cameras and lights. Keep it identical to the object name so
                # RealityKit can resolve the scene descriptor exactly.
                obj.data.name = obj.name
            obj.hide_set(False)
            if forced:
                obj.hide_render = False
                obj.hide_viewport = False
            obj.select_set(True)
            selected.append(obj)

    bpy.context.view_layer.update()

    output = args.output / asset["filename"] / f'{asset["filename"]}.usdc'
    output.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.wm.usd_export(
        filepath=str(output),
        selected_objects_only=True,
        evaluation_mode="VIEWPORT",
        export_animation=False,
        export_uvmaps=True,
        export_normals=True,
        export_materials=True,
        generate_preview_surface=True,
        export_textures_mode="NEW",
        overwrite_textures=True,
        relative_paths=True,
        export_lights=True,
        export_cameras=True,
        # Some repeated Blender collection instances form cyclic USD payloads.
        # The optimized source scenes are already batched, so explicit meshes
        # are smaller and more reliable for RealityKit on Apple devices.
        use_instancing=False,
        triangulate_meshes=False,
        root_prim_path=asset["root"],
        convert_scene_units="METERS",
        meters_per_unit=1.0,
    )
    report.append(
        {
            "scene": asset["scene"],
            "output": str(output),
            "result": sorted(result),
            "selected": len(selected),
            "resizedImages": sorted(resized),
        }
    )

(args.output / "export_report.json").write_text(
    json.dumps(report, ensure_ascii=False, indent=2)
)
print(json.dumps(report, ensure_ascii=False, indent=2))
