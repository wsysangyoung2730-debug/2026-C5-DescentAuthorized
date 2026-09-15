"""Bake portable shared PBR tiles and project UVs at a fixed world scale.

Run before export_v27_game_assets.py in the same Blender process. Source blend
is never saved. No light/shadow information is baked into base color.
"""
import bpy, math
from pathlib import Path
from mathutils import Vector

SCENES = ['DA_F10_ClosedOffice', 'DA_F08A_ResidueIsolation', 'DA_F08_AdministratorObservatory']
OUT = Path('/private/tmp/c5-110-surfaces'); OUT.mkdir(exist_ok=True)
TILE_METERS = 8.0
SIZE = 2048

def repair():
    original_scene = bpy.context.window.scene
    targets = [bpy.data.scenes[n] for n in SCENES]
    materials = {m for s in targets for o in s.objects if o.type == 'MESH' and not o.hide_render
                 for m in o.data.materials if m and m.use_nodes
                 and any(n.type == 'TEX_NOISE' for n in m.node_tree.nodes)
                 and not any(n.type == 'TEX_IMAGE' for n in m.node_tree.nodes)}
    bake = bpy.data.scenes.new('PortableSurfaceBake')
    bpy.context.window.scene = bake
    bake.render.engine = 'CYCLES'; bake.cycles.samples = 8
    bake.cycles.use_denoising = False; bake.render.bake.margin = 16
    bpy.ops.mesh.primitive_plane_add(size=TILE_METERS, location=(TILE_METERS/2, TILE_METERS/2, 0))
    plane = bpy.context.object
    replacements = {}
    for source in sorted(materials, key=lambda m: m.name):
        # Wall shaders include height-dependent damp/dirt masks. Sampling them
        # on a horizontal floor would bake only the darkest bottom edge.
        vertical = source.name in {'DA_Reference_AgedCharcoal_Wall', 'F10_Carved_BlackStone', 'F09_Aged_Plaster'}
        plane.location = (TILE_METERS/2, 0, TILE_METERS/2) if vertical else (TILE_METERS/2, TILE_METERS/2, 0)
        plane.rotation_euler = (math.pi/2,0,0) if vertical else (0,0,0)
        bpy.context.view_layer.update()
        material = source.copy()
        plane.data.materials.clear(); plane.data.materials.append(material)
        nodes = material.node_tree.nodes; links = material.node_tree.links
        bs = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
        emit = nodes.new('ShaderNodeEmission')
        target = nodes.new('ShaderNodeTexImage'); nodes.active = target
        images = {}
        for channel, socket in [('basecolor','Base Color'), ('roughness','Roughness'), ('normal','Normal')]:
            image = bpy.data.images.new(source.name+'_'+channel, width=SIZE,height=SIZE,alpha=False)
            image.colorspace_settings.name = 'sRGB' if channel == 'basecolor' else 'Non-Color'
            target.image = image
            for link in list(output.inputs['Surface'].links): links.remove(link)
            if channel == 'normal':
                links.new(bs.outputs['BSDF'], output.inputs['Surface'])
            else:
                for link in list(emit.inputs['Color'].links): links.remove(link)
                value = bs.inputs[socket]
                if value.is_linked: links.new(value.links[0].from_socket, emit.inputs['Color'])
                else: emit.inputs['Color'].default_value = value.default_value if channel == 'basecolor' else (value.default_value,)*3+(1,)
                links.new(emit.outputs[0], output.inputs['Surface'])
            bpy.ops.object.bake(type='NORMAL' if channel == 'normal' else 'EMIT')
            image.file_format = 'PNG'; image.filepath_raw = str(OUT/(image.name+'.png')); image.save()
            images[channel] = image
            print('BAKED', source.name, channel, flush=True)
        portable = bpy.data.materials.new(source.name+'_Portable'); portable.use_nodes = True
        p = portable.node_tree.nodes.get('Principled BSDF')
        for key in ['Metallic','IOR','Alpha','Emission Color','Emission Strength']:
            p.inputs[key].default_value = bs.inputs[key].default_value
        for channel, socket in [('basecolor','Base Color'),('roughness','Roughness'),('normal','Normal')]:
            tex = portable.node_tree.nodes.new('ShaderNodeTexImage'); tex.image = images[channel]
            result = tex.outputs['Color']
            if channel == 'normal':
                normal = portable.node_tree.nodes.new('ShaderNodeNormalMap')
                portable.node_tree.links.new(result,normal.inputs['Color']); result=normal.outputs['Normal']
            portable.node_tree.links.new(result,p.inputs[socket])
        replacements[source] = portable
        bpy.data.materials.remove(material)
    bpy.context.window.scene = original_scene
    bpy.data.scenes.remove(bake)
    # Exporter can serialize UV coordinates, but cannot serialize Geometry.Position
    # noise graphs. Project only procedural surfaces; imported prop UVs stay intact.
    for scene in targets:
        bpy.context.window.scene = scene
        for obj in list(scene.objects):
            if obj.type != 'MESH' or obj.hide_render or not any(m in replacements for m in obj.data.materials): continue
            obj.data = obj.data.copy()
            mesh = obj.data
            uv = mesh.uv_layers.active or mesh.uv_layers.new(name='UVMap')
            uv.name = 'UVMap'; uv.active_render = True
            normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
            for face in mesh.polygons:
                normal = normal_matrix @ face.normal
                axis = max(range(3),key=lambda i:abs(normal[i]))
                axes = [(1,2),(0,2),(0,1)][axis]
                for loop_index in face.loop_indices:
                    position = obj.matrix_world @ mesh.vertices[mesh.loops[loop_index].vertex_index].co
                    uv.data[loop_index].uv = (position[axes[0]]/TILE_METERS,position[axes[1]]/TILE_METERS)
            for slot in obj.material_slots:
                if slot.material in replacements: slot.material = replacements[slot.material]
        # Glass BSDF is unsupported by USD Preview Surface. Give the suspended
        # lenses explicit portable transmission/opacity rather than white fallback.
        for obj in scene.objects:
            if obj.type != 'MESH': continue
            for slot in obj.material_slots:
                m = slot.material
                if not m or m.name != 'F08B_SuspendedOpticalGlass': continue
                portable = bpy.data.materials.get('F08B_OpticalGlass_Portable')
                if not portable:
                    portable=bpy.data.materials.new('F08B_OpticalGlass_Portable'); portable.use_nodes=True
                    p=portable.node_tree.nodes.get('Principled BSDF')
                    p.inputs['Base Color'].default_value=(.12,.28,.36,1)
                    p.inputs['Roughness'].default_value=.16; p.inputs['Metallic'].default_value=.25
                    p.inputs['Alpha'].default_value=.3
                    p.inputs['Emission Color'].default_value=(.08,.03,.22,1);p.inputs['Emission Strength'].default_value=.25
                slot.material=portable
    bpy.context.window.scene = original_scene

if __name__ == '__main__': repair()
