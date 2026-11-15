"""Builds a hero's 3D body from a recipe with MakeHuman (MPFB2 in Blender).

Run (with Blender's Python module 'bpy' and the MPFB2 extension installed):
    python3 tools/build_hero.py aurelia
Reads data/heroes.json -> heroes[id].body and writes assets/characters/<id>_mh.glb.
The body uses the "mixamo" rig, so all Mixamo animations work (the game
retargets them from Mixamo's T-pose to MakeHuman's rest pose).
"""
import importlib
import math
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
    bsdf.inputs["Metallic"].default_value = (0.55 if kind == "steel" else 1.0) if metal else 0.0
    bsdf.inputs["Roughness"].default_value = {"chain": 0.45, "steel": 0.42, "gold": 0.3, "leather": 0.62, "leather_dark": 0.6, "cloth": 0.9}[kind]
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


# ---------------------------------------------------------------- armour models
# Real armour from Sketchfab (assets/gear/*.glb): scaled so its neckline sits
# at the hero's neck, pushed out wherever it would cut into the body, and
# given the body's bone weights so it moves with every animation.
def _rig_of(body):
    for m in body.modifiers:
        if m.type == "ARMATURE" and m.object:
            return m.object
    return body.parent


def _bone_head(rig, name):
    b = rig.data.bones.get(B + name)
    return rig.matrix_world @ b.head_local if b else None


def fit_armour(body, spec):
    import mathutils
    path = os.path.join(ROOT, "assets", "gear", spec["file"])
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH" and not any(x in o.name for x in spec.get("drop", []))]
    others = [o.name for o in new if o not in meshes]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    # bake the importer's parent transforms into the meshes, then join them
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for n in others:
        if n in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[n])
    ob.name = "outfit_" + spec["id"]
    ob.data.name = ob.name
    rig = _rig_of(body)
    neck = _bone_head(rig, "Neck")
    # the outfit's own neckline: given in the data, as a height in its file
    pts = [v.co for v in ob.data.vertices]
    top = max(p.z for p in pts)
    neck_z = spec.get("neck", top)
    s = neck.z / neck_z * spec.get("scale", 1.0)
    for v in ob.data.vertices:
        v.co = mathutils.Vector((v.co.x * s * spec.get("width", 1.0), v.co.y * s * spec.get("depth", 1.0), v.co.z * s))
    # centre it on the neck (x) and the chest (y)
    chest = _bone_head(rig, "Spine2")
    xs = [v.co.x for v in ob.data.vertices]
    ys = [v.co.y for v in ob.data.vertices if v.co.z > chest.z - 0.1]
    dx = neck.x - (min(xs) + max(xs)) / 2
    dy = chest.y - (min(ys) + max(ys)) / 2 + spec.get("forward", 0.0)
    dz = spec.get("up", 0.0)
    for v in ob.data.vertices:
        v.co += mathutils.Vector((dx, dy, dz))
    ob.data.update()
    # push it out wherever it cuts into the body
    hips_z = _bone_head(rig, "Hips").z + spec.get("wrap_above", 0.0)
    vg = ob.vertex_groups.new(name="_wrap")
    vg.add([v.index for v in ob.data.vertices if v.co.z > hips_z], 1.0, "REPLACE")
    sw = ob.modifiers.new("fit", "SHRINKWRAP")
    sw.vertex_group = "_wrap"
    sw.target = body
    sw.wrap_method = "NEAREST_SURFACEPOINT"
    sw.wrap_mode = "OUTSIDE"
    sw.offset = spec.get("gap", 0.014)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="fit")
    # bone weights from the body
    for g in body.vertex_groups:
        if g.name.startswith(B) and g.name not in ob.vertex_groups:
            ob.vertex_groups.new(name=g.name)
    dt = ob.modifiers.new("weights", "DATA_TRANSFER")
    dt.object = body
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    bpy.ops.object.modifier_apply(modifier="weights")
    for g in list(ob.vertex_groups):
        if not g.name.startswith(B):
            ob.vertex_groups.remove(g)
    ob.parent = rig
    am = ob.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    print("  armour:", ob.name, len(ob.data.vertices), "verts, scale", round(s, 3))
    return ob


def _snap_to_helpers(body, root):
    """Eyes, brows and lashes are fitted to the base shape; move each so it
    sits on its helper geometry in the final (macro-shaped) body."""
    import mathutils
    dg = bpy.context.evaluated_depsgraph_get()
    sk = body.data.shape_keys
    basis = [v.co.copy() for v in body.data.vertices]
    pos = [c.copy() for c in basis]
    if sk:
        for kb in sk.key_blocks[1:]:
            if kb.value:
                for i, d in enumerate(kb.data):
                    pos[i] += (d.co - basis[i]) * kb.value
    groups = {g.name: g.index for g in body.vertex_groups}
    def centre(names):
        idx = {groups[n] for n in names if n in groups}
        pts = [body.matrix_world @ pos[v.index] for v in body.data.vertices if any(g.group in idx and g.weight > 0.5 for g in v.groups)]
        return sum(pts, mathutils.Vector()) / len(pts) if pts else None
    plan = [("low-poly", ["helper-l-eye", "helper-r-eye"]), ("high-poly", ["helper-l-eye", "helper-r-eye"]),
            ("eyelashes", ["helper-l-eyelashes-1", "helper-l-eyelashes-2", "helper-r-eyelashes-1", "helper-r-eyelashes-2"])]
    for o in ObjectService.get_list_of_children(root):
        if o.type != "MESH":
            continue
        for key, names in plan:
            if key in o.name:
                target = centre(names)
                oe = o.evaluated_get(dg).to_mesh()
                cur = sum((o.matrix_world @ v.co for v in oe.vertices), mathutils.Vector()) / max(1, len(oe.vertices))
                o.evaluated_get(dg).to_mesh_clear()
                if target is not None:
                    d = o.matrix_world.inverted().to_3x3() @ (target - cur)
                    for v in o.data.vertices:
                        v.co += d
                    print("  snapped", o.name, [round(x, 3) for x in (target - cur)])
                    if key == "eyelashes" or key.endswith("poly"):
                        brow_d = d


# ---------------------------------------------------------------- hidden skin
# Each MakeHuman garment knows which skin it covers (vertex group
# "Delete.<asset>"). The skin is not deleted - the hero may take the garment
# off - but split into pieces named body_hide_<id>+<id>; the game hides a
# piece while any of those outfits is worn, so feet never poke through boots.
def split_body_by_clothes(body, clothes):
    import bmesh
    ids = {}
    for c in clothes:
        if isinstance(c, dict):
            g = body.vertex_groups.get("Delete." + c["asset"])
            if g:
                ids[g.index] = c["id"]
    if not ids:
        return
    done = set()
    while True:
        covered = [frozenset(ids[g.group] for g in v.groups if g.group in ids and g.weight > 0.5) for v in body.data.vertices]
        sets = {}
        for f in body.data.polygons:
            common = frozenset.intersection(*[covered[i] for i in f.vertices])
            if common and common not in done:
                sets.setdefault(common, []).append(f.index)
        if not sets:
            break
        key, faces = next(iter(sets.items()))
        done.add(key)
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = body
        body.select_set(True)
        for p in body.data.polygons:
            p.select = False
        for fi in faces:
            body.data.polygons[fi].select = True
        before = set(bpy.data.objects)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        for o in set(bpy.data.objects) - before:
            o.name = "body_hide_" + "+".join(sorted(key))
            print("  skin piece:", o.name, len(o.data.polygons), "faces")


# ---------------------------------------------------------------- rigid armour
# Plates (cuirass, pauldrons, bracers...) are stiff: each piece is fitted to
# the body once and then follows ONE bone 100%, so it never bends or drifts.
# spec: {"id": outfit name, "file": gear glb, "fit": "chest"|"shoulders",
#        "scale": extra size, "up": metres, "forward": metres, "drop": [names]}
def _import_joined(path, drop=(), keep=()):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH" and not any(x in o.name for x in drop)
              and (not keep or any(x in o.name for x in keep))]
    others = [o.name for o in new if o not in meshes]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for n in others:
        if n in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[n])
    return ob


def _body_points(body, bones):
    """(position, outward normal) of body vertices that mostly follow these bones."""
    dom = _dominant_bones(body)
    m3 = body.matrix_world.to_3x3()
    return [(body.matrix_world @ v.co, (m3 @ v.normal).normalized()) for v, d in zip(body.data.vertices, dom) if d in bones]


def _penetration(piece, pts, reach=0.09):
    """Share of the covered body points that poke out through the piece.
    A body point is under the piece if the piece is within `reach`; it is
    safely covered if a ray from it, straight out of the skin, hits the piece."""
    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromObject(piece, bpy.context.evaluated_depsgraph_get())
    near = out = 0
    for p, n in pts:
        loc, _, _, dist = bvh.find_nearest(p)
        if loc is None or dist > reach:
            continue
        near += 1
        hit = bvh.ray_cast(p + n * 0.004, n, 0.25)
        if hit[0] is None:
            out += 1
    return out / max(1, near), near


def _grow(piece, centre, pts, sx=1.0, sy=1.0, sz=1.0, step=1.04, limit=1.6):
    """Scale the piece about `centre` until the body no longer pokes through."""
    import mathutils
    total = 1.0
    for _ in range(14):
        frac, near = _penetration(piece, pts)
        print(f"      try x{total:.2f}: {frac * 100:.1f}% of {near}")
        if frac < 0.015 or total > limit:
            break
        f = mathutils.Vector((1 + (step - 1) * sx, 1 + (step - 1) * sy, 1 + (step - 1) * sz))
        for v in piece.data.vertices:
            v.co = centre + mathutils.Vector(((v.co - centre).x * f.x, (v.co - centre).y * f.y, (v.co - centre).z * f.z))
        piece.data.update()
        total *= step
    print(f"    grown x{total:.2f}, poke-through {frac * 100:.1f}% of {near} points")


def _weight_to(piece, rig, chooser):
    for g in list(piece.vertex_groups):
        piece.vertex_groups.remove(g)
    groups = {}
    for v in piece.data.vertices:
        bone = chooser(v.co)
        if bone not in groups:
            groups[bone] = piece.vertex_groups.new(name=B + bone)
        groups[bone].add([v.index], 1.0, "REPLACE")
    piece.parent = rig
    am = piece.modifiers.new("Armature", "ARMATURE")
    am.object = rig


def fit_rigid(body, spec):
    import mathutils
    rig = _rig_of(body)
    ob = _import_joined(os.path.join(ROOT, "assets", "gear", spec["file"]), spec.get("drop", []), spec.get("keep", []))
    ob.name = "outfit_" + spec["id"]
    ob.data.name = ob.name
    vs = ob.data.vertices
    if spec.get("turn"):  # make the piece face -Y like the body (degrees about Z)
        rz = mathutils.Matrix.Rotation(math.radians(spec["turn"]), 3, "Z")
        for v in vs:
            v.co = rz @ v.co
    lo = mathutils.Vector((min(v.co.x for v in vs), min(v.co.y for v in vs), min(v.co.z for v in vs)))
    hi = mathutils.Vector((max(v.co.x for v in vs), max(v.co.y for v in vs), max(v.co.z for v in vs)))
    neck = _bone_head(rig, "Neck")
    la, ra = _bone_head(rig, "LeftArm"), _bone_head(rig, "RightArm")
    shoulder_w = abs(la.x - ra.x)
    if spec["fit"] == "chest":
        bones = TORSO | {"Hips"}
        torso = _body_points(body, TORSO)
        torso_w = max(p.x for p, _ in torso) - min(p.x for p, _ in torso)
        s = torso_w / (hi.x - lo.x) * spec.get("scale", 1.05)
        anchor = mathutils.Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, hi.z))   # top of the piece
        target = mathutils.Vector((neck.x, sum(p.y for p, _ in torso) / len(torso), neck.z - 0.02))
    elif spec["fit"] == "torso":  # cuirass with pauldrons and belt in one piece
        bones = TORSO
        hips = _bone_head(rig, "Hips")
        torso = _body_points(body, {"Spine1", "Spine2"})
        depth = max(p.y for p, _ in torso) - min(p.y for p, _ in torso)
        s = depth / (hi.y - lo.y) * spec.get("scale", 1.12)
        anchor = mathutils.Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, hi.z))
        target = mathutils.Vector((neck.x, sum(p.y for p, _ in torso) / len(torso), neck.z + 0.05))
    else:  # shoulders: the pair spans both shoulders
        bones = SHOULDER | UPPERARM | {"Spine2"}
        s = shoulder_w / (hi.x - lo.x) * spec.get("scale", 1.35)
        anchor = mathutils.Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, hi.z))
        target = mathutils.Vector((neck.x, (la.y + ra.y) / 2, neck.z + 0.06))
    target += mathutils.Vector((0, -spec.get("forward", 0.0), spec.get("up", 0.0)))
    dscale = spec.get("depth", 1.0)   # extra front-to-back size (room for the chest)
    for v in vs:
        d = (v.co - anchor) * s
        d.y *= dscale
        v.co = target + d
    ob.data.update()
    pts = _body_points(body, TORSO if spec["fit"] in ("chest", "torso") else SHOULDER)
    centre = sum((p for p, _ in pts), mathutils.Vector()) / len(pts) if spec["fit"] != "shoulders" else target
    if spec.get("grow", True):
        _grow(ob, centre, pts, sz=0.3)
    if spec["fit"] == "torso":
        spine1, spine2 = _bone_head(rig, "Spine1").z, _bone_head(rig, "Spine2").z
        hips_z = _bone_head(rig, "Hips").z
        half = shoulder_w / 2
        def pick(co):
            dx = co.x - neck.x
            if abs(dx) > half * 0.62 and co.z > spine2:
                return "LeftShoulder" if dx * (la.x - neck.x) > 0 else "RightShoulder"
            if co.z < (hips_z + spine1) / 2:
                return "Hips"
            return "Spine2" if co.z > spine2 - 0.04 else "Spine1"
        _weight_to(ob, rig, pick)
        if spec.get("shoulders_only"):
            import bmesh
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bm.verts.ensure_lookup_table()
            keep_groups = {ob.vertex_groups[B + n].index for n in ("LeftShoulder", "RightShoulder") if B + n in ob.vertex_groups}
            dl = bm.verts.layers.deform.active
            drop = [v for v in bm.verts if not any(g in keep_groups for g in v[dl].keys())]
            bmesh.ops.delete(bm, geom=drop, context="VERTS")
            bm.to_mesh(ob.data)
            bm.free()
    elif spec["fit"] == "chest":
        chest_z = _bone_head(rig, "Spine1").z
        _weight_to(ob, rig, lambda co: "Spine2" if co.z > chest_z else "Spine1")
    else:
        mid = 0.35 * shoulder_w / 2
        _weight_to(ob, rig, lambda co: "Spine2" if abs(co.x - neck.x) < mid else ("LeftShoulder" if (co.x - neck.x) * (la.x - neck.x) > 0 else "RightShoulder"))
    if spec.get("material"):  # replace the model's own look, e.g. low-res or odd colours
        ob.data.materials.clear()
        ob.data.materials.append(_material(spec["material"], tuple(spec.get("color", (0.78, 0.8, 0.84)))))
    print("  rigid:", ob.name, len(vs), "verts, scale", round(s, 3))
    return ob


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
        asset = c["asset"] if isinstance(c, dict) else c
        p = find(asset, "clothes")
        if p:
            HumanService.add_mhclo_asset(p, bm, asset_type="Clothes", material_type="GAMEENGINE")
    # clothes must not cut holes in the skin: they can be taken off in game
    for m in list(bm.modifiers):
        if m.type == "MASK" and m.name != "Hide helpers":
            bm.modifiers.remove(m)

    root = ExportService.create_character_copy(bm, name_suffix="_export")
    # the mixamo rig has no eye bones: eyes, brows and lashes follow the head
    for o in ObjectService.get_list_of_children(root):
        if o.type == "MESH" and any(k in o.name for k in ("low-poly", "high-poly", "eyebrows", "eyelashes")):
            print("  head-weighted:", o.name, [g.name for g in o.vertex_groups][:6])
            for g in list(o.vertex_groups):
                o.vertex_groups.remove(g)
            hg = o.vertex_groups.new(name=B + "Head")
            hg.add([v.index for v in o.data.vertices], 1.0, "REPLACE")
    eb = ObjectService.find_object_of_type_amongst_nearest_relatives(root, "Basemesh")
    _snap_to_helpers(eb, root)
    # name each clothing mesh outfit_<id> so the game can show/hide it
    for c in body.get("clothes", []):
        if not isinstance(c, dict):
            continue
        for o in ObjectService.get_list_of_children(root):
            if o.type == "MESH" and c["asset"] in o.name:
                o.name = "outfit_" + c["id"]
                if c.get("push"):  # lift a layer off the one beneath (boots over trousers)
                    for v in o.data.vertices:
                        v.co += v.normal * c["push"]
                print("  clothes:", o.name)
    ExportService.bake_modifiers_remove_helpers(eb, bake_masks=True, bake_subdiv=True, remove_helpers=True, also_proxy=True)
    # freeze the body shape (macro shape keys) so every engine shows it as built
    if eb.data.shape_keys:
        eb.shape_key_add(name="final", from_mix=True)
        keep = [v.co.copy() for v in eb.data.shape_keys.key_blocks["final"].data]
        eb.shape_key_clear()
        for v, c in zip(eb.data.vertices, keep):
            v.co = c
        print("  froze body shape keys")
    make_outfits(eb, body.get("outfits", ["under_top", "under_legs", "boots", "gloves"]))
    split_body_by_clothes(eb, body.get("clothes", []))
    for spec in body.get("armour", []):
        fit_armour(eb, spec)
    for spec in body.get("rigid", []):
        fit_rigid(eb, spec)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    kids = ObjectService.get_list_of_children(root)
    for c in kids:
        c.select_set(True)
        print("  part:", c.name, c.type)
    bpy.context.view_layer.objects.active = root
    out_path = out_path or os.path.join(ROOT, "assets", "characters", hero_id + "_mh.glb")
    bpy.ops.export_scene.gltf(filepath=out_path, use_selection=True, export_format="GLB", export_animations=False,
                              export_image_format="AUTO")
    print("wrote", out_path)
    return out_path


if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
