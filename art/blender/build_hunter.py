"""Build the M4.4 low-poly armored hunter, rig, and normalized actions."""

from pathlib import Path
import math
import sys

import bpy
from mathutils import Vector


def argument(name: str) -> Path:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    try:
        return Path(arguments[arguments.index(name) + 1]).resolve()
    except (ValueError, IndexError):
        raise SystemExit(f"Missing {name} path")


ROOT = argument("--root")
BLEND_PATH = ROOT / "art/blender/hunter.blend"
GLB_PATH = ROOT / "assets/models/hunter.glb"
FPS = 24


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.actions):
        for item in list(collection):
            collection.remove(item)


def make_material(name: str, color, metallic: float = 0.0, roughness: float = 0.75):
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1.0)
    result.use_nodes = True
    shader = result.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return result


def build_armature():
    data = bpy.data.armatures.new("HunterSkeleton")
    armature = bpy.data.objects.new("HunterRig", data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    specifications = {
        "Root": ((0.0, 0.0, 0.0), (0.0, 0.0, 0.18), None),
        "Pelvis": ((0.0, 0.0, 0.70), (0.0, 0.0, 0.94), "Root"),
        "Spine": ((0.0, 0.0, 0.88), (0.0, 0.0, 1.18), "Pelvis"),
        "Chest": ((0.0, 0.0, 1.14), (0.0, 0.0, 1.42), "Spine"),
        "Neck": ((0.0, 0.0, 1.40), (0.0, 0.0, 1.54), "Chest"),
        "Head": ((0.0, 0.0, 1.52), (0.0, 0.0, 1.76), "Neck"),
        "UpperArm.L": ((-0.27, 0.0, 1.36), (-0.43, 0.09, 1.16), "Chest"),
        "Forearm.L": ((-0.43, 0.09, 1.16), (-0.37, 0.22, 0.98), "UpperArm.L"),
        "Hand.L": ((-0.37, 0.22, 0.98), (-0.28, 0.25, 0.91), "Forearm.L"),
        "UpperArm.R": ((0.27, 0.0, 1.36), (0.43, 0.09, 1.16), "Chest"),
        "Forearm.R": ((0.43, 0.09, 1.16), (0.48, 0.22, 0.98), "UpperArm.R"),
        "Hand.R": ((0.48, 0.22, 0.98), (0.48, 0.26, 0.88), "Forearm.R"),
        "WeaponSocket": ((0.48, 0.26, 0.92), (0.48, 0.26, 1.08), "Hand.R"),
        "Thigh.L": ((-0.15, 0.0, 0.72), (-0.17, 0.0, 0.40), "Pelvis"),
        "Shin.L": ((-0.17, 0.0, 0.40), (-0.17, 0.02, 0.10), "Thigh.L"),
        "Foot.L": ((-0.17, 0.02, 0.10), (-0.17, 0.19, 0.06), "Shin.L"),
        "Thigh.R": ((0.15, 0.0, 0.72), (0.17, 0.0, 0.40), "Pelvis"),
        "Shin.R": ((0.17, 0.0, 0.40), (0.17, 0.02, 0.10), "Thigh.R"),
        "Foot.R": ((0.17, 0.02, 0.10), (0.17, 0.19, 0.06), "Shin.R"),
    }
    bones = {}
    for name, (head, tail, _parent) in specifications.items():
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bones[name] = bone
    for name, (_head, _tail, parent_name) in specifications.items():
        if parent_name:
            bones[name].parent = bones[parent_name]
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.show_in_front = True
    return armature


def skin_object(obj, armature, bone_name: str, material) -> None:
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("HunterArmature", "ARMATURE")
    modifier.object = armature
    obj.parent = armature


def box(name: str, location, dimensions, armature, bone_name: str, material, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    skin_object(obj, armature, bone_name, material)
    return obj


def ico(name: str, location, scale, armature, bone_name: str, material):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    skin_object(obj, armature, bone_name, material)
    return obj


def segment(name: str, start, end, radius: float, armature, bone_name: str, material):
    start_vector = Vector(start)
    end_vector = Vector(end)
    direction = end_vector - start_vector
    midpoint = (start_vector + end_vector) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=radius, depth=direction.length, location=midpoint)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    skin_object(obj, armature, bone_name, material)
    return obj


def cape_mesh(armature, material):
    vertices = [
        (-0.31, -0.05, 1.42), (-0.02, -0.10, 1.33), (-0.04, -0.13, 0.82),
        (-0.39, -0.10, 0.96), (-0.31, -0.075, 1.42), (-0.02, -0.125, 1.33),
        (-0.04, -0.155, 0.82), (-0.39, -0.125, 0.96),
    ]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    mesh = bpy.data.meshes.new("AsymmetricCapeMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("AsymmetricCape", mesh)
    bpy.context.collection.objects.link(obj)
    skin_object(obj, armature, "Chest", material)


def build_character(armature) -> None:
    armor = make_material("ArmorLight", (0.66, 0.72, 0.70), 0.42, 0.52)
    under = make_material("UnderDark", (0.055, 0.075, 0.080), 0.05, 0.86)
    hair = make_material("HairSilver", (0.72, 0.76, 0.75), 0.12, 0.70)
    teal = make_material("HunterTeal", (0.20, 0.48, 0.43), 0.08, 0.78)
    leather = make_material("Leather", (0.20, 0.15, 0.12), 0.0, 0.90)
    skin = make_material("Skin", (0.74, 0.58, 0.49), 0.0, 0.86)

    box("PelvisArmor", (0.0, 0.0, 0.79), (0.38, 0.25, 0.25), armature, "Pelvis", armor)
    box("Waist", (0.0, 0.0, 0.94), (0.29, 0.22, 0.16), armature, "Spine", under)
    box("ChestArmor", (0.0, 0.0, 1.22), (0.52, 0.29, 0.50), armature, "Chest", armor)
    box("ChestInlay", (0.0, 0.155, 1.22), (0.22, 0.035, 0.31), armature, "Chest", teal)
    box("ShoulderL", (-0.31, 0.0, 1.36), (0.24, 0.31, 0.17), armature, "UpperArm.L", armor)
    box("ShoulderR", (0.31, 0.0, 1.36), (0.24, 0.31, 0.17), armature, "UpperArm.R", armor)
    segment("UpperArmL", (-0.34, 0.05, 1.29), (-0.43, 0.09, 1.16), 0.105, armature, "UpperArm.L", under)
    segment("UpperArmR", (0.34, 0.05, 1.29), (0.43, 0.09, 1.16), 0.105, armature, "UpperArm.R", under)
    segment("ForearmL", (-0.43, 0.09, 1.16), (-0.37, 0.22, 0.98), 0.11, armature, "Forearm.L", armor)
    segment("ForearmR", (0.43, 0.09, 1.16), (0.48, 0.22, 0.98), 0.11, armature, "Forearm.R", armor)
    ico("HandL", (-0.32, 0.24, 0.94), (0.09, 0.08, 0.10), armature, "Hand.L", leather)
    ico("HandR", (0.48, 0.25, 0.93), (0.09, 0.08, 0.10), armature, "Hand.R", leather)

    segment("ThighL", (-0.15, 0.0, 0.70), (-0.17, 0.0, 0.41), 0.14, armature, "Thigh.L", under)
    segment("ThighR", (0.15, 0.0, 0.70), (0.17, 0.0, 0.41), 0.14, armature, "Thigh.R", under)
    segment("GreaveL", (-0.17, 0.0, 0.40), (-0.17, 0.02, 0.12), 0.13, armature, "Shin.L", armor)
    segment("GreaveR", (0.17, 0.0, 0.40), (0.17, 0.02, 0.12), 0.13, armature, "Shin.R", armor)
    box("BootL", (-0.17, 0.11, 0.08), (0.24, 0.38, 0.16), armature, "Foot.L", leather)
    box("BootR", (0.17, 0.11, 0.08), (0.24, 0.38, 0.16), armature, "Foot.R", leather)

    ico("Face", (0.0, 0.015, 1.66), (0.22, 0.19, 0.25), armature, "Head", skin)
    ico("HairCap", (0.0, -0.035, 1.72), (0.235, 0.205, 0.245), armature, "Head", hair)
    box("HairFringeL", (-0.10, 0.185, 1.72), (0.10, 0.055, 0.25), armature, "Head", hair, rotation=(0.0, -0.16, 0.0))
    box("HairFringeR", (0.09, 0.19, 1.70), (0.10, 0.055, 0.20), armature, "Head", hair, rotation=(0.0, 0.20, 0.0))
    box("HairBackL", (-0.13, -0.15, 1.58), (0.12, 0.10, 0.30), armature, "Head", hair, rotation=(0.0, -0.10, 0.0))
    box("HairBackR", (0.12, -0.15, 1.60), (0.12, 0.10, 0.26), armature, "Head", hair, rotation=(0.0, 0.12, 0.0))
    cape_mesh(armature, teal)


def set_pose(armature, rotations: dict[str, tuple[float, float, float]]) -> None:
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
    for bone_name, degrees in rotations.items():
        armature.pose.bones[bone_name].rotation_euler = tuple(math.radians(value) for value in degrees)


def make_action(armature, name: str, keyframes: list[tuple[int, dict[str, tuple[float, float, float]]]]) -> None:
    action = bpy.data.actions.new(name)
    armature.animation_data.action = action
    for frame, rotations in keyframes:
        bpy.context.scene.frame_set(frame)
        set_pose(armature, rotations)
        for bone in armature.pose.bones:
            bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone.name)
        root = armature.pose.bones["Root"]
        root.location = (0.0, 0.0, 0.0)
        root.keyframe_insert(data_path="location", frame=frame, group="Root")
    action.use_fake_user = True


def build_actions(armature) -> None:
    armature.animation_data_create()
    rest = {}
    ready_arms = {"UpperArm.L": (8, 2, -8), "Forearm.L": (-12, 3, 8), "UpperArm.R": (7, -2, 7), "Forearm.R": (-10, -3, -6)}
    make_action(armature, "idle_loop", [(1, rest), (13, {"Chest": (2, 0, 0), "Head": (-2, 0, 0), **ready_arms}), (25, rest)])
    make_action(armature, "run_loop", [
        (1, {"Thigh.L": (28, 0, 0), "Shin.L": (-16, 0, 0), "Thigh.R": (-28, 0, 0), "UpperArm.L": (-16, 0, 0), "UpperArm.R": (16, 0, 0), "Chest": (4, 0, 0)}),
        (7, rest),
        (13, {"Thigh.L": (-28, 0, 0), "Thigh.R": (28, 0, 0), "Shin.R": (-16, 0, 0), "UpperArm.L": (16, 0, 0), "UpperArm.R": (-16, 0, 0), "Chest": (4, 0, 0)}),
        (19, rest),
        (25, {"Thigh.L": (28, 0, 0), "Shin.L": (-16, 0, 0), "Thigh.R": (-28, 0, 0), "UpperArm.L": (-16, 0, 0), "UpperArm.R": (16, 0, 0), "Chest": (4, 0, 0)}),
    ])
    make_action(armature, "light_attack", [(1, ready_arms), (8, {"Chest": (-8, 0, -20), "UpperArm.L": (-30, 5, -25), "UpperArm.R": (-35, -5, -18)}), (14, {"Chest": (12, 0, 24), "UpperArm.L": (28, 0, 20), "UpperArm.R": (32, 0, 24)}), (25, ready_arms)])
    charge_pose = {
        "Pelvis": (3, 0, 0), "Spine": (9, 0, 0), "Chest": (18, 0, 0),
        "UpperArm.L": (42, 8, -12), "Forearm.L": (24, 0, 8),
        "UpperArm.R": (48, -8, 12), "Forearm.R": (22, 0, -8),
        "Thigh.L": (8, 0, 0), "Thigh.R": (8, 0, 0),
    }
    make_action(armature, "charge_enter", [(1, ready_arms), (25, charge_pose)])
    make_action(armature, "charge_hold", [(1, charge_pose), (13, {**charge_pose, "Spine": (11, 0, 0), "Chest": (22, 0, 0), "Head": (-4, 0, 0)}), (25, charge_pose)])
    release_finish = {
        "Pelvis": (-5, 0, 0), "Spine": (-10, 0, 0), "Chest": (-26, 0, 0),
        "UpperArm.L": (38, 0, 0), "UpperArm.R": (42, 0, 0),
        "Thigh.L": (-8, 0, 0), "Thigh.R": (-8, 0, 0),
    }
    make_action(armature, "charge_release_1", [(1, charge_pose), (12, release_finish), (25, ready_arms)])
    make_action(armature, "charge_release_2", [(1, charge_pose), (14, {**release_finish, "Spine": (-13, 0, 0), "Chest": (-34, 0, 0)}), (25, ready_arms)])
    make_action(armature, "charge_cancel", [(1, charge_pose), (25, ready_arms)])
    make_action(armature, "dodge", [(1, {"Pelvis": (-12, 0, 0), "Chest": (18, 0, 0)}), (12, {"Root": (-155, 0, 0), "Pelvis": (-20, 0, 0)}), (25, rest)])
    make_action(armature, "hit", [(1, rest), (8, {"Chest": (-18, 0, -12), "Head": (12, 0, 8)}), (16, rest)])
    make_action(armature, "defeated", [(1, rest), (25, {"Root": (0, 72, 0), "Chest": (-22, 0, 0), "Head": (18, 0, 0), "UpperArm.L": (25, 0, 20), "UpperArm.R": (-20, 0, -18)})])
    armature.animation_data.action = None


def main() -> None:
    reset_scene()
    scene = bpy.context.scene
    scene.name = "M4Hunter"
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = FPS
    scene.frame_start = 1
    scene.frame_end = 25
    armature = build_armature()
    build_character(armature)
    build_actions(armature)
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_yup=True,
        export_apply=False,
    )
    print(f"M4.4 hunter written: {BLEND_PATH} and {GLB_PATH}")


if __name__ == "__main__":
    main()
