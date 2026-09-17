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


if __name__ == "__main__":
    main()
