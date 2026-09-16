"""Create the committed M4.1 Blender/GLB contract fixture.

Run only through `python3 tools/dev.py art-export`; this module executes inside
Blender and deliberately uses no third-party add-ons.
"""
from pathlib import Path
import sys

import bpy


def argument(name: str) -> Path:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    try:
        return Path(arguments[arguments.index(name) + 1]).resolve()
    except (ValueError, IndexError):
        raise SystemExit(f"Missing {name} path")


ROOT = argument("--root")
BLEND_PATH = ROOT / "art/blender/contract_fixture.blend"
GLB_PATH = ROOT / "assets/models/contract_fixture.glb"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.actions):
        for item in list(collection):
            collection.remove(item)


def build_material():
    material = bpy.data.materials.new("ContractPalette")
    material.diffuse_color = (0.28, 0.65, 0.58, 1.0)
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = material.diffuse_color
    material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.78
    return material


def build_rigged_mesh(material):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.75, 0.0))
    mesh = bpy.context.object
    mesh.name = "ContractMesh"
    mesh.scale = (0.5, 0.75, 0.35)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mesh.data.materials.append(material)
    for polygon in mesh.data.polygons:
        polygon.use_smooth = False

    armature_data = bpy.data.armatures.new("ContractSkeleton")
    armature = bpy.data.objects.new("ContractRig", armature_data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    mesh.select_set(False)
    bpy.ops.object.mode_set(mode="EDIT")
    bone = armature_data.edit_bones.new("RootBone")
    bone.head = (0.0, 0.0, 0.0)
    bone.tail = (0.0, 1.5, 0.0)
    bpy.ops.object.mode_set(mode="OBJECT")

    modifier = mesh.modifiers.new("ContractArmature", "ARMATURE")
    modifier.object = armature
    group = mesh.vertex_groups.new(name="RootBone")
    group.add(list(range(len(mesh.data.vertices))), 1.0, "REPLACE")
    mesh.parent = armature

    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    pose_bone = armature.pose.bones["RootBone"]
    pose_bone.rotation_mode = "XYZ"
    for frame, angle in ((1, 0.0), (13, 0.12), (25, 0.0)):
        bpy.context.scene.frame_set(frame)
        pose_bone.rotation_euler[2] = angle
        pose_bone.keyframe_insert(data_path="rotation_euler", frame=frame)
    action = armature.animation_data.action
    action.name = "idle_loop"
    return armature


def add_locator(name: str, location, parent) -> None:
    locator = bpy.data.objects.new(name, None)
    locator.empty_display_type = "PLAIN_AXES"
    locator.empty_display_size = 0.12
    locator.location = location
    locator.parent = parent
    bpy.context.collection.objects.link(locator)


def main() -> None:
    reset_scene()
    scene = bpy.context.scene
    scene.name = "M4ContractFixture"
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 25

    rig = build_rigged_mesh(build_material())
    locators = {
        "WeaponSocket": (0.42, 0.92, -0.18),
        "BladeBase": (0.42, 0.92, -0.18),
        "BladeTip": (0.42, 2.72, -0.18),
        "HornLBase": (-0.38, 1.22, -0.62),
        "HornLTip": (-0.55, 1.28, -1.25),
        "HornRBase": (0.38, 1.22, -0.62),
        "HornRTip": (0.55, 1.28, -1.25),
    }
    for name, location in locators.items():
        add_locator(name, location, rig)

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        export_animations=True,
        export_yup=True,
        export_apply=False,
    )
    print(f"M4 contract assets written: {BLEND_PATH} and {GLB_PATH}")


if __name__ == "__main__":
    main()
