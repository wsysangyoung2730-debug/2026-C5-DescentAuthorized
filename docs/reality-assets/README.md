# Descent Authorized Reality assets v012

This package was exported from `DA_F08_F09_F10_Combined_v012.blend`.

## Xcode import

1. Drag `Assets/Reality` into the Xcode project.
2. Enable **Copy items if needed**.
3. Add the folder to the application target.
4. Keep `AssetManifest.json` in the app bundle or copy its data into the project manifest.
5. Load a file by its manifest path and resolve interactive entities through `entityAliases`.

Floor scenes include their authored cameras, lights, placement, and door transition
states. Blender visibility keys do not survive Blender 5.2 USDC export, so both closed
and open door entities are included and `RealityAssetIDs.swift` provides the required
RealityKit state toggle. Call `DoorStateTransitions.setDoorOpen(false, ...)` immediately
after loading a floor scene. Actors and VFX are separate files. The actor source scenes
currently have no authored animation clips; gameplay movement must be supplied by
RealityKit until actor animation is authored.
