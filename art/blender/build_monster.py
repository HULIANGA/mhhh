"""Build the M4.5 low-poly horned field beast, quadruped rig, and actions."""

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
BLEND_PATH = ROOT / "art/blender/monster.blend"
GLB_PATH = ROOT / "assets/models/monster.glb"
FPS = 24


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.actions):
        for item in list(collection):
            collection.remove(item)


def material(name: str, color, metallic: float = 0.0, roughness: float = 0.82):
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1.0)
    result.use_nodes = True
    shader = result.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return result


def build_armature():
    data = bpy.data.armatures.new("FieldBeastSkeleton")
    armature = bpy.data.objects.new("FieldBeastRig", data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    specs = {
        "Root": ((0.0, 0.0, 0.0), (0.0, 0.0, 0.2), None),
        "Pelvis": ((0.0, 0.42, 0.78), (0.0, 0.05, 0.92), "Root"),
        "Spine": ((0.0, 0.10, 0.92), (0.0, -0.52, 1.04), "Pelvis"),
        "Shoulders": ((0.0, -0.50, 1.02), (0.0, -0.88, 1.08), "Spine"),
        "Neck": ((0.0, -0.82, 1.04), (0.0, -1.12, 0.92), "Shoulders"),
        "Head": ((0.0, -1.08, 0.92), (0.0, -1.48, 0.82), "Neck"),
        "HornLBase": ((-0.30, -1.30, 0.99), (-0.52, -1.46, 1.05), "Head"),
        "HornLTip": ((-0.52, -1.46, 1.05), (-0.92, -1.78, 0.92), "HornLBase"),
        "HornRBase": ((0.30, -1.30, 0.99), (0.52, -1.46, 1.05), "Head"),
        "HornRTip": ((0.52, -1.46, 1.05), (0.92, -1.78, 0.92), "HornRBase"),
        "UpperForeleg.L": ((-0.48, -0.58, 0.90), (-0.52, -0.63, 0.48), "Shoulders"),
        "LowerForeleg.L": ((-0.52, -0.63, 0.48), (-0.50, -0.72, 0.10), "UpperForeleg.L"),
        "UpperForeleg.R": ((0.48, -0.58, 0.90), (0.52, -0.63, 0.48), "Shoulders"),
        "LowerForeleg.R": ((0.52, -0.63, 0.48), (0.50, -0.72, 0.10), "UpperForeleg.R"),
        "UpperHindleg.L": ((-0.42, 0.55, 0.77), (-0.48, 0.62, 0.43), "Pelvis"),
        "LowerHindleg.L": ((-0.48, 0.62, 0.43), (-0.47, 0.72, 0.10), "UpperHindleg.L"),
        "UpperHindleg.R": ((0.42, 0.55, 0.77), (0.48, 0.62, 0.43), "Pelvis"),
        "LowerHindleg.R": ((0.48, 0.62, 0.43), (0.47, 0.72, 0.10), "UpperHindleg.R"),
    }
    bones = {}
    for name, (head, tail, _parent) in specs.items():
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bones[name] = bone
    for name, (_head, _tail, parent_name) in specs.items():
        if parent_name:
            bones[name].parent = bones[parent_name]
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.show_in_front = True
    return armature


def skin(obj, armature, bone_name: str, material_slot) -> None:
    obj.data.materials.append(material_slot)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("FieldBeastArmature", "ARMATURE")
    modifier.object = armature
    obj.parent = armature


def box(name, location, dimensions, armature, bone_name, material_slot, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    skin(obj, armature, bone_name, material_slot)
    return obj


def ico(name, location, scale, armature, bone_name, material_slot, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    skin(obj, armature, bone_name, material_slot)
    return obj


def segment(name, start, end, radius, armature, bone_name, material_slot, vertices=6, end_radius=None):
    start_vector, end_vector = Vector(start), Vector(end)
    direction = end_vector - start_vector
    midpoint = (start_vector + end_vector) * 0.5
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius if end_radius is None else end_radius,
        radius2=radius, depth=direction.length, location=midpoint,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    skin(obj, armature, bone_name, material_slot)
    return obj


def build_beast(armature) -> None:
    earth = material("EarthHide", (0.34, 0.27, 0.20))
    dark = material("DarkBack", (0.14, 0.13, 0.12))
    horn = material("PaleHorn", (0.68, 0.61, 0.45), 0.03, 0.66)
    underside = material("UnderHide", (0.43, 0.34, 0.25))

    ico("BarrelBody", (0.0, 0.10, 0.88), (0.78, 1.05, 0.65), armature, "Spine", earth, 2)
    box("DarkBackPlate", (0.0, 0.10, 1.36), (1.22, 1.65, 0.18), armature, "Spine", dark)
    ico("ShoulderMass", (0.0, -0.58, 0.98), (0.88, 0.67, 0.72), armature, "Shoulders", earth, 2)
    ico("ShortRump", (0.0, 0.72, 0.78), (0.62, 0.60, 0.52), armature, "Pelvis", underside, 1)
    segment("LowNeck", (0.0, -0.72, 1.02), (0.0, -1.13, 0.89), 0.47, armature, "Neck", dark, 8)
    ico("WedgeHead", (0.0, -1.28, 0.86), (0.56, 0.58, 0.40), armature, "Head", earth, 1)
    box("Muzzle", (0.0, -1.70, 0.72), (0.64, 0.52, 0.34), armature, "Head", dark)

    for side, x in (("L", -0.50), ("R", 0.50)):
        segment(f"UpperForeleg{side}", (x, -0.58, 0.91), (x * 1.05, -0.64, 0.48), 0.20, armature, f"UpperForeleg.{side}", earth)
        segment(f"LowerForeleg{side}", (x * 1.05, -0.64, 0.48), (x, -0.72, 0.11), 0.16, armature, f"LowerForeleg.{side}", dark)
        box(f"ForeHoof{side}", (x, -0.80, 0.09), (0.34, 0.38, 0.18), armature, f"LowerForeleg.{side}", dark)
        hind_x = -0.44 if side == "L" else 0.44
        segment(f"UpperHindleg{side}", (hind_x, 0.55, 0.77), (hind_x * 1.08, 0.64, 0.43), 0.17, armature, f"UpperHindleg.{side}", underside)
        segment(f"LowerHindleg{side}", (hind_x * 1.08, 0.64, 0.43), (hind_x * 1.05, 0.73, 0.11), 0.13, armature, f"LowerHindleg.{side}", dark)
        box(f"HindHoof{side}", (hind_x * 1.05, 0.67, 0.09), (0.30, 0.34, 0.17), armature, f"LowerHindleg.{side}", dark)

    segment("HornLInner", (-0.30, -1.30, 0.99), (-0.52, -1.46, 1.05), 0.15, armature, "HornLBase", horn, end_radius=0.11)
    segment("HornLOuter", (-0.52, -1.46, 1.05), (-0.92, -1.78, 0.92), 0.11, armature, "HornLTip", horn, end_radius=0.015)
    segment("HornRInner", (0.30, -1.30, 0.99), (0.52, -1.46, 1.05), 0.15, armature, "HornRBase", horn, end_radius=0.11)
    segment("HornROuter", (0.52, -1.46, 1.05), (0.92, -1.78, 0.92), 0.11, armature, "HornRTip", horn, end_radius=0.015)


def set_pose(armature, rotations, locations=None) -> None:
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
    for bone_name, degrees in rotations.items():
        armature.pose.bones[bone_name].rotation_euler = tuple(math.radians(value) for value in degrees)
    for bone_name, location in (locations or {}).items():
        armature.pose.bones[bone_name].location = location


def action(armature, name, keyframes) -> None:
    result = bpy.data.actions.new(name)
    armature.animation_data.action = result
    for entry in keyframes:
        frame, rotations = entry[0], entry[1]
        locations = entry[2] if len(entry) > 2 else {}
        bpy.context.scene.frame_set(frame)
        set_pose(armature, rotations, locations)
        for bone in armature.pose.bones:
            bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)
    result.use_fake_user = True


def build_actions(armature) -> None:
    armature.animation_data_create()
    rest = {}
    step_a = {"UpperForeleg.L": (25, 0, 0), "LowerForeleg.L": (-18, 0, 0), "UpperHindleg.R": (25, 0, 0), "UpperForeleg.R": (-25, 0, 0), "UpperHindleg.L": (-25, 0, 0)}
    step_b = {"UpperForeleg.R": (25, 0, 0), "LowerForeleg.R": (-18, 0, 0), "UpperHindleg.L": (25, 0, 0), "UpperForeleg.L": (-25, 0, 0), "UpperHindleg.R": (-25, 0, 0)}
    action(armature, "idle_loop", [(1, rest), (13, {"Spine": (2, 0, 0), "Head": (-3, 0, 0)}), (25, rest)])
    action(armature, "run_loop", [(1, step_a), (7, rest), (13, step_b), (19, rest), (25, step_a)])
    action(armature, "sweep", [
        (1, rest), (8, {"Spine": (0, 0, -10), "Neck": (0, 0, -22), "Head": (0, 0, -24)}),
        (13, {"Spine": (0, 0, 18), "Neck": (0, 0, 34), "Head": (0, 0, 38)}), (25, rest),
    ])
    action(armature, "pounce", [
        (1, rest), (8, {"Spine": (14, 0, 0), "Head": (18, 0, 0), "UpperForeleg.L": (-22, 0, 0), "UpperForeleg.R": (-22, 0, 0), "UpperHindleg.L": (20, 0, 0), "UpperHindleg.R": (20, 0, 0)}),
        (14, {"Spine": (-12, 0, 0), "Head": (-16, 0, 0), "UpperForeleg.L": (58, 0, 0), "UpperForeleg.R": (58, 0, 0), "UpperHindleg.L": (-25, 0, 0), "UpperHindleg.R": (-25, 0, 0)}),
        (20, {"Spine": (8, 0, 0), "UpperForeleg.L": (-12, 0, 0), "UpperForeleg.R": (-12, 0, 0)}), (25, rest),
    ])
    windup = {"Spine": (12, 0, 0), "Neck": (22, 0, 0), "Head": (24, 0, 0), "UpperForeleg.L": (-18, 0, 0), "UpperForeleg.R": (12, 0, 0)}
    action(armature, "charge_windup", [(1, rest), (13, windup, {"Pelvis": (0.0, 0.12, 0.0)}), (25, windup, {"Pelvis": (0.0, 0.24, 0.0)})])
    charge_a = {**step_a, "Spine": (-8, 0, 0), "Neck": (12, 0, 0), "Head": (14, 0, 0)}
    charge_b = {**step_b, "Spine": (-8, 0, 0), "Neck": (12, 0, 0), "Head": (14, 0, 0)}
    action(armature, "charge_run", [(1, charge_a), (7, charge_b), (13, charge_a)])
    action(armature, "charge_recovery", [(1, charge_a), (13, {"Spine": (10, 0, 0), "Head": (-8, 0, 0)}), (25, rest)])
    action(armature, "crash_stunned", [
        (1, charge_a), (5, {"Root": (0, 0, 72), "Spine": (-18, 0, 0), "Head": (20, 0, 0)}),
        (19, {"Root": (0, 0, 72), "Spine": (-18, 0, 0), "Head": (20, 0, 0)}), (25, rest),
    ])
    action(armature, "hit", [(1, rest), (7, {"Spine": (-16, 0, 12), "Head": (18, 0, -12)}), (13, rest)])
    action(armature, "defeated", [(1, rest), (25, {"Root": (0, 0, -82), "Spine": (-20, 0, 0), "Head": (28, 0, 0)})])
    armature.animation_data.action = None


def main() -> None:
    reset_scene()
    scene = bpy.context.scene
    scene.name = "M4FieldBeast"
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = FPS
    scene.frame_start = 1
    scene.frame_end = 25
    armature = build_armature()
    build_beast(armature)
    build_actions(armature)
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH), export_format="GLB", export_animations=True,
        export_animation_mode="ACTIONS", export_yup=True, export_apply=False,
    )
    print(f"M4.5 field beast written: {BLEND_PATH} and {GLB_PATH}")


if __name__ == "__main__":
    main()
