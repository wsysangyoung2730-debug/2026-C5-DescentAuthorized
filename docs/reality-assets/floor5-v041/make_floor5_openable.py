import bpy
s=bpy.data.scenes['DA_F05B_OriginalMemoryAdministrator']
for window in bpy.context.window_manager.windows:
    window.scene=s
    for area in window.screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.overlay.show_overlays=False
            area.spaces.active.shading.type='MATERIAL'
            area.spaces.active.region_3d.view_camera_zoom=0
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print('Floor5 file saved with normal startup workspace')
