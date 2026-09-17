"""Build the M4.3 low-poly greatsword source and runtime GLB."""

from pathlib import Path
import math
import sys

import bpy


def argument(name: str) -> Path:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    try:
        return Path(arguments[arguments.index(name) + 1]).resolve()
    except (ValueError, IndexError):
        raise SystemExit(f"Missing {name} path")


ROOT = argument("--root")
BLEND_PATH = ROOT / "art/blender/greatsword.blend"
GLB_PATH = ROOT / "assets/models/greatsword.glb"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.materials, bpy.data.curves):
        for item in list(collection):
            collection.remove(item)


def material(name: str, color: tuple[float, float, float, float], metallic: float, roughness: float):
    result = bpy.data.materials.new(name)
    result.diffuse_color = color
    result.use_nodes = True
    shader = result.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return result


def parented(obj, parent):
    obj.parent = parent
    return obj


def cylinder(name: str, radius: float, depth: float, z: float, material_slot, parent):
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius, depth=depth, location=(0.0, 0.0, z))
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    obj.data.materials.append(material_slot)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return parented(obj, parent)


def prism(name: str, profile: list[tuple[float, float]], thickness: float, material_slot, parent):
    """Extrude an X/Z profile symmetrically along Blender Y."""
    half = thickness * 0.5
    vertices = [(x, -half, z) for x, z in profile] + [(x, half, z) for x, z in profile]
    count = len(profile)
    faces = [tuple(range(count - 1, -1, -1)), tuple(range(count, count * 2))]
    for index in range(count):
        following = (index + 1) % count
        faces.append((index, following, count + following, count + index))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material_slot)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    return parented(obj, parent)


def edge_inlays(material_slot, parent):
    """Add bright bevel faces so the cutting direction reads from the game camera."""
    left = [(-0.305, 0.38), (-0.275, 1.55), (0.0, 1.82), (-0.105, 1.54), (-0.205, 0.40)]
    right = [(-x, z) for x, z in reversed(left)]
    for side_name, profile in (("BladeEdgeL", left), ("BladeEdgeR", right)):
        for face_name, y in (("Front", -0.0515), ("Back", 0.0515)):
            vertices = [(x, y, z) for x, z in profile]
            mesh = bpy.data.meshes.new(side_name + face_name + "Mesh")
            mesh.from_pydata(vertices, [], [tuple(range(len(vertices)))])
            mesh.materials.append(material_slot)
            mesh.update()
            obj = bpy.data.objects.new(side_name + face_name, mesh)
            bpy.context.collection.objects.link(obj)
            parented(obj, parent)


def empty(name: str, location, parent):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.08
    obj.location = location
    obj.parent = parent
    bpy.context.collection.objects.link(obj)
    return obj


def main() -> None:
    reset_scene()
    scene = bpy.context.scene
    scene.name = "M4Greatsword"
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    grip_dark = material("GripDark", (0.055, 0.075, 0.080, 1.0), 0.10, 0.82)
    guard_steel = material("GuardSteel", (0.29, 0.34, 0.35, 1.0), 0.58, 0.48)
    blade_light = material("BladeLight", (0.72, 0.80, 0.79, 1.0), 0.66, 0.30)

    asset = empty("GreatswordAsset", (0.0, 0.0, 0.0), None)
    socket = empty("WeaponSocket", (0.0, 0.0, 0.0), asset)

    cylinder("Grip", 0.062, 0.46, -0.015, grip_dark, socket)
    cylinder("GripCollar", 0.082, 0.055, 0.225, guard_steel, socket)
    cylinder("Pommel", 0.095, 0.12, -0.305, guard_steel, socket)
    guard_profile = [
        (-0.35, 0.245), (-0.31, 0.205), (0.31, 0.205), (0.35, 0.245),
        (0.35, 0.325), (0.31, 0.365), (-0.31, 0.365), (-0.35, 0.325),
    ]
    prism("Guard", guard_profile, 0.15, guard_steel, socket)
    cylinder("GuardCenter", 0.13, 0.08, 0.285, guard_steel, socket).rotation_euler[0] = math.pi * 0.5

    blade_profile = [
        (-0.235, 0.30), (0.235, 0.30), (0.305, 0.39), (0.275, 1.55),
        (0.0, 1.82), (-0.275, 1.55), (-0.305, 0.39),
    ]
    prism("BladeCore", blade_profile, 0.10, guard_steel, socket)
    edge_inlays(blade_light, socket)

    # These authored locators are the gameplay contract. Their Godot-space
    # distance is 1.52 m and exactly matches the visible blade center line.
    empty("BladeBase", (0.0, 0.0, 0.30), socket)
    empty("BladeTip", (0.0, 0.0, 1.82), socket)

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        export_animations=False,
        export_yup=True,
        export_apply=False,
    )
    print(f"M4.3 greatsword written: {BLEND_PATH} and {GLB_PATH}")


if __name__ == "__main__":
    main()
