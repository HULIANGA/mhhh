"""Validate committed Blender/GLB asset contracts without requiring Blender."""
from pathlib import Path
import json
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
GLB_PATH = ROOT / "assets/models/contract_fixture.glb"
BLEND_PATH = ROOT / "art/blender/contract_fixture.blend"
GREATSWORD_GLB_PATH = ROOT / "assets/models/greatsword.glb"
GREATSWORD_BLEND_PATH = ROOT / "art/blender/greatsword.blend"
HUNTER_GLB_PATH = ROOT / "assets/models/hunter.glb"
HUNTER_BLEND_PATH = ROOT / "art/blender/hunter.blend"
MONSTER_GLB_PATH = ROOT / "assets/models/monster.glb"
MONSTER_BLEND_PATH = ROOT / "art/blender/monster.blend"
REQUIRED_NODES = {
    "ContractRig",
    "ContractMesh",
    "WeaponSocket",
    "BladeBase",
    "BladeTip",
    "HornLBase",
    "HornLTip",
    "HornRBase",
    "HornRTip",
}
GREATSWORD_REQUIRED_NODES = {
    "GreatswordAsset",
    "WeaponSocket",
    "BladeCore",
    "BladeBase",
    "BladeTip",
}
HUNTER_REQUIRED_NODES = {
    "HunterRig",
    "Root",
    "Pelvis",
    "Spine",
    "Chest",
    "Neck",
    "Head",
    "UpperArm.L",
    "Forearm.L",
    "Hand.L",
    "UpperArm.R",
    "Forearm.R",
    "Hand.R",
    "WeaponSocket",
    "Thigh.L",
    "Shin.L",
    "Foot.L",
    "Thigh.R",
    "Shin.R",
    "Foot.R",
}
HUNTER_REQUIRED_ANIMATIONS = {
    "idle_loop",
    "run_loop",
    "light_attack",
    "charge_enter",
    "charge_hold",
    "charge_release_1",
    "charge_release_2",
    "charge_cancel",
    "dodge",
    "hit",
    "defeated",
}
MONSTER_REQUIRED_NODES = {
    "FieldBeastRig", "Root", "Pelvis", "Spine", "Shoulders", "Neck", "Head",
    "HornLBase", "HornLTip", "HornRBase", "HornRTip",
    "UpperForeleg.L", "LowerForeleg.L", "UpperForeleg.R", "LowerForeleg.R",
    "UpperHindleg.L", "LowerHindleg.L", "UpperHindleg.R", "LowerHindleg.R",
}
MONSTER_REQUIRED_ANIMATIONS = {
    "idle_loop", "run_loop", "sweep", "pounce", "charge_windup", "charge_run",
    "charge_recovery", "crash_stunned", "hit", "defeated",
}


def glb_json(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("file is too small to be GLB")
    magic, version, total_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or total_length != len(data):
        raise ValueError("invalid GLB 2.0 header")
    chunk_length, chunk_type = struct.unpack_from("<I4s", data, 12)
    if chunk_type != b"JSON":
        raise ValueError("first GLB chunk is not JSON")
    return json.loads(data[20 : 20 + chunk_length].decode("utf-8"))


def fail(message: str) -> None:
    print(f"ART ASSET ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if not BLEND_PATH.is_file():
        fail(f"missing Blender source: {BLEND_PATH.relative_to(ROOT)}")
    if not GLB_PATH.is_file():
        fail(f"missing runtime GLB: {GLB_PATH.relative_to(ROOT)}")
    try:
        document = glb_json(GLB_PATH)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        fail(str(error))

    names = {node.get("name") for node in document.get("nodes", [])}
    missing = sorted(REQUIRED_NODES - names)
    if missing:
        fail(f"missing nodes: {', '.join(missing)}")
    if not document.get("meshes"):
        fail("fixture contains no mesh")
    if not document.get("skins"):
        fail("fixture contains no skin/skeleton")
    if not document.get("materials"):
        fail("fixture contains no material")
    animations = {animation.get("name") for animation in document.get("animations", [])}
    if "idle_loop" not in animations:
        fail(f"missing idle_loop animation; found {sorted(name for name in animations if name)}")

    print(
        "ART ASSET CHECK: PASS "
        f"({len(document['meshes'])} mesh, {len(document['skins'])} skin, "
        f"{len(document['animations'])} animation, {len(document['materials'])} material)"
    )

    if not GREATSWORD_BLEND_PATH.is_file():
        fail(f"missing Blender source: {GREATSWORD_BLEND_PATH.relative_to(ROOT)}")
    if not GREATSWORD_GLB_PATH.is_file():
        fail(f"missing runtime GLB: {GREATSWORD_GLB_PATH.relative_to(ROOT)}")
    try:
        sword = glb_json(GREATSWORD_GLB_PATH)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        fail(f"greatsword: {error}")
    sword_names = {node.get("name") for node in sword.get("nodes", [])}
    missing_sword_nodes = sorted(GREATSWORD_REQUIRED_NODES - sword_names)
    if missing_sword_nodes:
        fail(f"greatsword missing nodes: {', '.join(missing_sword_nodes)}")
    material_count = len(sword.get("materials", []))
    if material_count > 3:
        fail(f"greatsword exceeds 3 material slots: {material_count}")
    triangle_count = 0
    accessors = sword.get("accessors", [])
    for mesh in sword.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if primitive.get("mode", 4) != 4:
                continue
            accessor_index = primitive.get("indices")
            if accessor_index is not None:
                triangle_count += accessors[accessor_index]["count"] // 3
    if triangle_count <= 0 or triangle_count > 3000:
        fail(f"greatsword triangle budget invalid: {triangle_count}")
    print(
        "GREATSWORD ASSET CHECK: PASS "
        f"({len(sword.get('meshes', []))} meshes, {triangle_count} triangles, {material_count} materials)"
    )

    if not HUNTER_BLEND_PATH.is_file():
        fail(f"missing Blender source: {HUNTER_BLEND_PATH.relative_to(ROOT)}")
    if not HUNTER_GLB_PATH.is_file():
        fail(f"missing runtime GLB: {HUNTER_GLB_PATH.relative_to(ROOT)}")
    try:
        hunter = glb_json(HUNTER_GLB_PATH)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        fail(f"hunter: {error}")
    hunter_names = {node.get("name") for node in hunter.get("nodes", [])}
    missing_hunter_nodes = sorted(HUNTER_REQUIRED_NODES - hunter_names)
    if missing_hunter_nodes:
        fail(f"hunter missing nodes/bones: {', '.join(missing_hunter_nodes)}")
    hunter_animations = {animation.get("name") for animation in hunter.get("animations", [])}
    missing_hunter_animations = sorted(HUNTER_REQUIRED_ANIMATIONS - hunter_animations)
    if missing_hunter_animations:
        fail(f"hunter missing animations: {', '.join(missing_hunter_animations)}")
    if not hunter.get("skins"):
        fail("hunter contains no skin/skeleton")
    hunter_material_count = len(hunter.get("materials", []))
    if hunter_material_count <= 0 or hunter_material_count > 6:
        fail(f"hunter material budget invalid: {hunter_material_count}")
    hunter_triangle_count = 0
    hunter_accessors = hunter.get("accessors", [])
    for mesh in hunter.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if primitive.get("mode", 4) != 4:
                continue
            accessor_index = primitive.get("indices")
            if accessor_index is not None:
                hunter_triangle_count += hunter_accessors[accessor_index]["count"] // 3
    if hunter_triangle_count <= 0 or hunter_triangle_count > 15000:
        fail(f"hunter triangle budget invalid: {hunter_triangle_count}")
    print(
        "HUNTER ASSET CHECK: PASS "
        f"({len(hunter.get('meshes', []))} meshes, {hunter_triangle_count} triangles, "
        f"{hunter_material_count} materials, {len(hunter_animations)} animations)"
    )

    if not MONSTER_BLEND_PATH.is_file():
        fail(f"missing Blender source: {MONSTER_BLEND_PATH.relative_to(ROOT)}")
    if not MONSTER_GLB_PATH.is_file():
        fail(f"missing runtime GLB: {MONSTER_GLB_PATH.relative_to(ROOT)}")
    try:
        monster = glb_json(MONSTER_GLB_PATH)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        fail(f"monster: {error}")
    monster_names = {node.get("name") for node in monster.get("nodes", [])}
    missing_monster_nodes = sorted(MONSTER_REQUIRED_NODES - monster_names)
    if missing_monster_nodes:
        fail(f"monster missing nodes/bones: {', '.join(missing_monster_nodes)}")
    monster_animations = {animation.get("name") for animation in monster.get("animations", [])}
    missing_monster_animations = sorted(MONSTER_REQUIRED_ANIMATIONS - monster_animations)
    if missing_monster_animations:
        fail(f"monster missing animations: {', '.join(missing_monster_animations)}")
    if not monster.get("skins"):
        fail("monster contains no skin/skeleton")
    monster_material_count = len(monster.get("materials", []))
    if monster_material_count <= 0 or monster_material_count > 4:
        fail(f"monster material budget invalid: {monster_material_count}")
    monster_triangle_count = 0
    monster_accessors = monster.get("accessors", [])
    for mesh in monster.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if primitive.get("mode", 4) != 4:
                continue
            accessor_index = primitive.get("indices")
            if accessor_index is not None:
                monster_triangle_count += monster_accessors[accessor_index]["count"] // 3
    if monster_triangle_count <= 0 or monster_triangle_count > 15000:
        fail(f"monster triangle budget invalid: {monster_triangle_count}")
    print(
        "MONSTER ASSET CHECK: PASS "
        f"({len(monster.get('meshes', []))} meshes, {monster_triangle_count} triangles, "
        f"{monster_material_count} materials, {len(monster_animations)} animations)"
    )


if __name__ == "__main__":
    main()
