"""Builds a hero's 3D body from a recipe with MakeHuman (MPFB2 in Blender).

Run (with Blender's Python module 'bpy' and the MPFB2 extension installed):
    python3 tools/build_hero.py aurelia
Reads data/heroes.json -> heroes[id].body and writes assets/characters/<id>_mh.glb.
The body uses the "mixamo" rig, so all Mixamo animations work (the game
retargets them from Mixamo's T-pose to MakeHuman's rest pose).
"""
import importlib
import json
import os
import sys

import bpy  # noqa: E402  (must come before addon_utils)
import addon_utils

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)


def M(path, key):
    return getattr(importlib.import_module("bl_ext.user_default.mpfb." + path), key)


HumanService = M("services.humanservice", "HumanService")
AssetService = M("services.assetservice", "AssetService")
ExportService = M("services.exportservice", "ExportService")
ObjectService = M("services.objectservice", "ObjectService")


def find(name, subdir):
    if not name:
        return None
    p = AssetService.find_asset_absolute_path(name + (".mhclo" if subdir != "skins" else ".mhmat"), asset_subdir=subdir)
    if p is None:
        print("  ! not found:", subdir, name)
    return p


# ---------------------------------------------------------------- outfits
# Outfits are generated from the body itself: the parts of the skin covered
# by a garment are copied, pushed outwards and given thickness. They keep the
# body's bone weights, so they move perfectly with every animation, and each
# one is a separate mesh ("outfit_<name>") the game shows or hides when the
# hero changes equipment.
TEX = os.path.join(ROOT, "tools", "textures")
B = "mixamorig:"
TORSO = {"Spine", "Spine1", "Spine2"}
SHOULDER = {"LeftShoulder", "RightShoulder"}
UPPERARM = {"LeftArm", "RightArm"}
FOREARM = {"LeftForeArm", "RightForeArm"}
HIPS = {"Hips"}
THIGH = {"LeftUpLeg", "RightUpLeg"}
SHIN = {"LeftLeg", "RightLeg"}
FOOT = {"LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"}
HAND = {"LeftHand", "RightHand"} | {f"{s}Hand{f}{i}" for s in ("Left", "Right") for f in ("Thumb", "Index", "Middle", "Ring", "Pinky") for i in (1, 2, 3)}

# name: (parts, push out m, thickness m, material, trim material or None, colour)
OUTFITS = {
    "under_top": (TORSO | SHOULDER | UPPERARM | FOREARM, 0.003, 0.002, "cloth", None, (0.78, 0.72, 0.62)),
    "under_legs": (HIPS | THIGH | SHIN, 0.003, 0.002, "cloth", None, (0.24, 0.19, 0.15)),
    "boots": (FOOT | {"__shin_low"}, 0.007, 0.004, "leather", None, (0.32, 0.21, 0.13)),
    "gloves": (HAND | {"__forearm_low"}, 0.003, 0.002, "leather", None, (0.28, 0.19, 0.12)),
    "leather": (TORSO | SHOULDER | {"__hips_high"}, 0.011, 0.005, "leather", "leather_dark", (0.55, 0.36, 0.22)),
    "chain": (TORSO | SHOULDER | UPPERARM | HIPS | {"__thigh_high"}, 0.010, 0.004, "chain", None, (0.85, 0.86, 0.9)),
    "plate": (TORSO | SHOULDER | UPPERARM | FOREARM | THIGH | SHIN | FOOT, 0.022, 0.006, "steel", "gold", (0.86, 0.87, 0.9)),
}


def _material(kind, colour):
    m = bpy.data.materials.new(f"{kind}_{len(bpy.data.materials)}")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    metal = kind in ("chain", "steel", "gold")
    bsdf.inputs["Metallic"].default_value = 1.0 if metal else 0.0
    bsdf.inputs["Roughness"].default_value = {"chain": 0.45, "steel": 0.32, "gold": 0.3, "leather": 0.62, "leather_dark": 0.6, "cloth": 0.9}[kind]
    tex = {"chain": "chain", "steel": "steel", "gold": "steel", "leather": "leather", "leather_dark": "leather", "cloth": "cloth"}[kind]
    scale = {"chain": 9.0, "steel": 2.0, "gold": 2.0, "leather": 3.0, "leather_dark": 3.0, "cloth": 10.0}[kind]
    uv = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    nt.links.new(uv.outputs["UV"], mp.inputs["Vector"])
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(os.path.join(TEX, f"{tex}_albedo.png"), check_existing=True)
    nt.links.new(mp.outputs["Vector"], img.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(img.outputs["Color"], mix.inputs[6])
    mix.inputs[7].default_value = (*colour, 1.0)
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    npath = os.path.join(TEX, f"{tex}_normal.png")
    if os.path.exists(npath):
        nimg = nt.nodes.new("ShaderNodeTexImage")
        nimg.image = bpy.data.images.load(npath, check_existing=True)
        nimg.image.colorspace_settings.name = "Non-Color"
        nt.links.new(mp.outputs["Vector"], nimg.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nimg.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def _dominant_bones(obj):
    names = {g.index: g.name[len(B):] for g in obj.vertex_groups if g.name.startswith(B)}
    dom = []
    for v in obj.data.vertices:
        best, bw = "", 0.0
        for g in v.groups:
            if g.group in names and g.weight > bw:
                best, bw = names[g.group], g.weight
        dom.append(best)
    return dom


def _keep(dom, co, parts, ranges):
    """Is a vertex inside this garment? Parts are bone names, plus a few
    height-limited extras ("__shin_low" = lower half of the shin...)."""
    if dom in parts:
        return True
    z = co.z
    if "__shin_low" in parts and dom in SHIN and z < ranges["shin_mid"]:
        return True
    if "__forearm_low" in parts and dom in FOREARM and abs(co.x) > ranges["wrist_x"] * 0.82:
        return True
    if "__hips_high" in parts and dom in HIPS and z > ranges["hips_z"]:
        return True
    if "__thigh_high" in parts and dom in THIGH and z > ranges["thigh_mid"]:
        return True
    return False


def make_outfits(body, wanted):
    import bmesh
    dom = _dominant_bones(body)
    zs = {}
    for v, d in zip(body.data.vertices, dom):
        zs.setdefault(d, []).append(v.co)
    def mid(bones):
        pts = [c for b in bones for c in zs.get(b, [])]
        return sum(p.z for p in pts) / max(1, len(pts))
    ranges = {"shin_mid": mid(SHIN), "thigh_mid": mid(THIGH), "hips_z": mid(HIPS),
              "wrist_x": max((abs(c.x) for b in FOREARM for c in zs.get(b, [])), default=0.6)}
    made = []
    for name in wanted:
        if name not in OUTFITS:
            print("  ! unknown outfit", name)
            continue
        parts, push, thick, mat, trim, colour = OUTFITS[name]
        ob = body.copy()
        ob.data = body.data.copy()
        ob.name = "outfit_" + name
        ob.data.name = "outfit_" + name
        body.users_collection[0].objects.link(ob)
        if ob.data.shape_keys:
            ob.shape_key_clear()
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.verts.ensure_lookup_table()
        drop = [v for v in bm.verts if not _keep(dom[v.index], v.co, parts, ranges)]
        bmesh.ops.delete(bm, geom=drop, context="VERTS")
        # loose bits (single stray triangles) go away
        for v in [v for v in bm.verts if len(v.link_faces) == 0]:
            bm.verts.remove(v)
        bm.normal_update()
        for v in bm.verts:
            v.co += v.normal * push
        # trim: the faces along the garment's edges
        ring = {v for e in bm.edges if e.is_boundary for v in e.verts}
        for _ in range(1):
            ring |= {o for v in list(ring) for e in v.link_edges for o in e.verts}
        bm.verts.index_update()
        ring_idx = {v.index for v in ring}
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.materials.clear()
        ob.data.materials.append(_material(mat, colour))
        if trim:
            tcol = (0.85, 0.62, 0.22) if trim == "gold" else (0.22, 0.14, 0.09)
            ob.data.materials.append(_material(trim, tcol))
            for f in ob.data.polygons:
                if any(i in ring_idx for i in f.vertices):
                    f.material_index = 1
        sol = ob.modifiers.new("thick", "SOLIDIFY")
        sol.thickness = thick
        sol.offset = 1.0
        sol.use_rim = True
        # solidify before the armature so the shell deforms with the body
        while ob.modifiers[0].name != "thick":
            bpy.context.view_layer.objects.active = ob
            bpy.ops.object.modifier_move_up(modifier="thick")
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier="thick")
        made.append(ob)
        print("  outfit:", ob.name, len(ob.data.vertices), "verts")
    return made


def build(hero_id, out_path=None):
    heroes = {h["id"]: h for h in json.load(open(os.path.join(ROOT, "data", "heroes.json")))["heroes"]}
    body = heroes[hero_id]["body"]
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    macro = {
        "gender": body.get("gender", 0.5), "age": body.get("age", 0.5), "muscle": body.get("muscle", 0.5),
        "weight": body.get("weight", 0.5), "height": body.get("height", 0.5), "proportions": body.get("proportions", 0.5),
        "cupsize": body.get("cupsize", 0.5), "firmness": body.get("firmness", 0.5),
        "race": body.get("race", {"african": 0.0, "asian": 0.0, "caucasian": 1.0}),
    }
    bm = HumanService.create_human(macro_detail_dict=macro)
    skin = find(body.get("skin"), "skins")
    if skin:
        HumanService.set_character_skin(skin, bm, skin_type="GAMEENGINE")
    HumanService.add_builtin_rig(bm, "mixamo")
    for subdir, key, atype in [("eyes", "eyes", "Eyes"), ("eyebrows", "eyebrows", "Eyebrows"), ("eyelashes", "eyelashes", "Eyelashes"),
                               ("teeth", "teeth", "Teeth"), ("tongue", "tongue", "Tongue"), ("hair", "hair", "Hair")]:
        p = find(body.get(key), subdir)
        if p:
            HumanService.add_mhclo_asset(p, bm, asset_type=atype, material_type="GAMEENGINE")
    for c in body.get("clothes", []):
        p = find(c, "clothes")
        if p:
            HumanService.add_mhclo_asset(p, bm, asset_type="Clothes", material_type="GAMEENGINE")

    root = ExportService.create_character_copy(bm, name_suffix="_export")
    eb = ObjectService.find_object_of_type_amongst_nearest_relatives(root, "Basemesh")
    ExportService.bake_modifiers_remove_helpers(eb, bake_masks=True, bake_subdiv=True, remove_helpers=True, also_proxy=True)
    make_outfits(eb, body.get("outfits", ["under_top", "under_legs", "boots", "gloves", "leather", "chain", "plate"]))
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    kids = ObjectService.get_list_of_children(root)
    for c in kids:
        c.select_set(True)
        print("  part:", c.name, c.type)
    bpy.context.view_layer.objects.active = root
    out_path = out_path or os.path.join(ROOT, "assets", "characters", hero_id + "_mh.glb")
    bpy.ops.export_scene.gltf(filepath=out_path, use_selection=True, export_format="GLB", export_animations=False,
                              export_image_format="JPEG", export_jpeg_quality=90)
    print("wrote", out_path)
    return out_path


if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
