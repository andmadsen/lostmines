"""Splits a Sketchfab model pack (one .glb with many trees/rocks) into one .glb
per object, each standing on the ground at the origin, in metres.

    python3 tools/split_pack.py

The packs and what to take from them are listed in PACKS below. Output goes to
assets/nature/split/<name>.gltf (+ .bin), textures shared in split/textures/. Needs Blender's Python module (bpy).
"""
import os
import sys

import bpy
import mathutils

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "nature", "models_sf")
OUT = os.path.join(ROOT, "assets", "nature", "split")

# pack file -> {output name: node name in the pack (a group; its meshes are taken)}
PACKS = {
    "conifer_pack.glb": {
        "fir": "FirTree_0", "pine": "PineTree_1", "noble_fir": "NobleFirTree_2",
        "conifer_shrub": "ConiferousShrub_3", "conifer_sapling": "Coniferous Sapling_4",
        "dead_log": "Coniferous Dead Log_5", "dead_tree": "Coniferous Dead Tree_6",
        "dead_tree_2": "Coniferous Dead Tree 2_7",
        "boulder_mossy": "BoulderMossyLarge_8", "outcrop_mossy": "BoulderOutcropMossyLarge_9",
        "outcrop_mossy_m": "BoulderOutcropMossyMedium_10", "outcrop_plain": "BoulderOutcropPlainLarge_11",
        "outcrop_plain_m": "BoulderOutcropPlainMedium_12", "boulder_plain": "BoulderPlainLarge_13",
    },
    # maple trees come in four levels of detail; LOD1 is light enough for a forest
    "maple_pack.glb": {f"maple_{size}_{i}": f"Acer_{size}_{i}_LOD1"
                       for size in ("large", "medium", "small") for i in (1, 2, 3)}
                      | {f"maple_sapling_{i}": f"Acer_Sapling_{i}_LOD1" for i in (1, 2, 3)},
}


def _meshes(node):
    return [o for o in [node] + list(node.children_recursive) if o.type == "MESH"]


def split(pack, wanted):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, pack))
    for out_name, node_name in wanted.items():
        node = bpy.data.objects.get(node_name)
        if node is None:
            print("  ! not found:", node_name)
            continue
        meshes = _meshes(node)
        # copies with the world transform applied, joined into one object
        copies = []
        for m in meshes:
            c = m.copy()
            c.data = m.data.copy()
            bpy.context.scene.collection.objects.link(c)
            c.parent = None
            c.matrix_world = m.matrix_world.copy()
            copies.append(c)
        bpy.ops.object.select_all(action="DESELECT")
        for c in copies:
            c.select_set(True)
        bpy.context.view_layer.objects.active = copies[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        if len(copies) > 1:
            bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        # stand it at the origin: centre of the base, lowest point at zero
        vs = [v.co for v in ob.data.vertices]
        lo = min(v.z for v in vs)
        base = [v for v in vs if v.z < lo + 0.3] or vs
        cx = sum(v.x for v in base) / len(base)
        cy = sum(v.y for v in base) / len(base)
        for v in ob.data.vertices:
            v.co -= mathutils.Vector((cx, cy, lo))
        ob.name = out_name
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        path = os.path.join(OUT, out_name + ".gltf")
        # separate files with one shared texture folder: the trees of a pack share their textures
        bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLTF_SEPARATE",
                                  export_texture_dir="textures", export_image_format="AUTO")
        h = max(v.co.z for v in ob.data.vertices)
        print(f"  {out_name}: {len(ob.data.polygons)} faces, {h:.1f} m tall -> {path}")
        bpy.data.objects.remove(ob)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for pack, wanted in PACKS.items():
        if len(sys.argv) > 1 and sys.argv[1] not in pack:
            continue
        print(pack)
        split(pack, wanted)
