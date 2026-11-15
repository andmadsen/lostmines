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
import mathutils  # noqa: E402
import addon_utils

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)


def M(path, key):
    return getattr(importlib.import_module("bl_ext.user_default.mpfb." + path), key)


HumanService = M("services.humanservice", "HumanService")
AssetService = M("services.assetservice", "AssetService")
ExportService = M("services.exportservice", "ExportService")
ObjectService = M("services.objectservice", "ObjectService")
TargetService = M("services.targetservice", "TargetService")


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


SMOOTH = {"leather": 14, "chain": 8, "under_top": 4, "plate": 8}


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


def _smooth_edges(bm, trims=3, passes=12):
    """Cut by bone, a garment's edge zigzags. Shave off the teeth (faces that
    hang on by one edge) and relax the edge line so necklines, armholes and
    hems run smoothly."""
    import bmesh
    for _ in range(trims):
        teeth = [f for f in bm.faces if sum(1 for e in f.edges if e.is_boundary or len(e.link_faces) == 1) >= 2]
        if not teeth:
            break
        bmesh.ops.delete(bm, geom=teeth, context="FACES")
        for v in [v for v in bm.verts if not v.link_faces]:
            bm.verts.remove(v)
    for _ in range(passes):
        moves = {}
        for v in bm.verts:
            if not v.is_boundary:
                continue
            nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(nb) == 2:
                moves[v] = (nb[0].co + nb[1].co) / 2
        for v, target in moves.items():
            v.co = v.co.lerp(target, 0.5)


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
        _smooth_edges(bm)
        bm.normal_update()
        for v in bm.verts:
            v.co += v.normal * push
        # garments do not follow every curve of the body: relax the shape
        smooth = SMOOTH.get(name, 0)
        if smooth:
            inner = [v for v in bm.verts if not v.is_boundary]
            for _ in range(smooth):
                bmesh.ops.smooth_vert(bm, verts=inner, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
            bm.normal_update()
            for v in inner:
                v.co += v.normal * 0.002
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


def clean_weights(obj, rig, max_dist=0.3):
    """Drop bone influences that are far from the vertex (MakeHuman sometimes
    gives a glove vertex a little shoulder weight: in game that stretches
    into long spikes), keep at most 4 per vertex and renormalise."""
    from mathutils.geometry import intersect_point_line
    segs = {}
    for b in rig.data.bones:
        segs[b.name] = (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local)
    names = {g.index: g.name for g in obj.vertex_groups}
    removed = 0
    for v in obj.data.vertices:
        co = obj.matrix_world @ v.co
        for g in list(v.groups):
            seg = segs.get(names[g.group])
            if seg is None or g.weight < 1e-4:
                continue
            pt, t = intersect_point_line(co, seg[0], seg[1])
            t = max(0.0, min(1.0, t))
            d = (co - (seg[0] + (seg[1] - seg[0]) * t)).length
            if d > max_dist:
                obj.vertex_groups[g.group].remove([v.index])
                removed += 1
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="BONE_DEFORM", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="BONE_DEFORM", lock_active=False)
    if removed:
        print(f"  cleaned {obj.name}: {removed} far influences")


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
    if spec.get("taper"):  # pull the lower edge in to the waist (plates flare otherwise)
        top_z = max(v.co.z for v in ob.data.vertices)
        low_z = min(v.co.z for v in ob.data.vertices)
        start = top_z - (top_z - low_z) * spec["taper"]
        tg = ob.vertex_groups.new(name="_taper")
        for v in ob.data.vertices:
            if v.co.z < start:
                tg.add([v.index], min(1.0, (start - v.co.z) / max(0.01, start - low_z) * 1.6), "REPLACE")
        sw = ob.modifiers.new("taper", "SHRINKWRAP")
        sw.target = body
        sw.vertex_group = "_taper"
        sw.wrap_method = "NEAREST_SURFACEPOINT"
        sw.wrap_mode = "ON_SURFACE"
        sw.offset = spec.get("taper_gap", 0.03)
        mods = list(ob.modifiers)
        bpy.context.view_layer.objects.active = ob
        while ob.modifiers[0].name != "taper":
            bpy.ops.object.modifier_move_up(modifier="taper")
        bpy.ops.object.modifier_apply(modifier="taper")
        ob.vertex_groups.remove(ob.vertex_groups["_taper"])
    if spec.get("material"):  # replace the model's own look, e.g. low-res or odd colours
        ob.data.materials.clear()
        ob.data.materials.append(_material(spec["material"], tuple(spec.get("color", (0.78, 0.8, 0.84)))))
    print("  rigid:", ob.name, len(vs), "verts, scale", round(s, 3))
    return ob


# ---------------------------------------------------------------- panels
# Generated cloth panels (tabards, aprons): a grid laid over the front (and
# back) of the dressed body, painted with a colour, a border and an emblem.
# Above the belt it follows the torso bones; below it hangs straight and
# follows the hips and, partly, both thighs, so legs swing under it.
EMBLEMS = {
    # outlines in 0..1 (x right, y down), drawn in the trim colour
    "anvil": [(0.02, 0.20), (0.70, 0.20), (0.98, 0.16), (0.90, 0.30), (0.78, 0.40), (0.66, 0.44),
              (0.62, 0.62), (0.84, 0.78), (0.86, 0.90), (0.14, 0.90), (0.16, 0.78), (0.38, 0.62),
              (0.34, 0.44), (0.20, 0.42), (0.10, 0.36), (0.04, 0.30)],
    "sun": None,
}


def _paint_panel(path, spec):
    from PIL import Image, ImageDraw
    w, h = 512, 2048
    c = tuple(int(x * 255) for x in spec.get("color", (0.85, 0.81, 0.7)))
    t = tuple(int(x * 255) for x in spec.get("trim", (0.72, 0.53, 0.2)))
    im = Image.new("RGB", (w, h), c)
    d = ImageDraw.Draw(im)
    import random
    rnd = random.Random(7)
    for _ in range(9000):   # woven cloth: faint speckles and threads
        x, y = rnd.randrange(w), rnd.randrange(h)
        k = rnd.uniform(0.9, 1.06)
        im.putpixel((x, y), tuple(max(0, min(255, int(v * k))) for v in c))
    b = int(w * spec.get("border", 0.07))
    d.rectangle([0, 0, b, h], fill=t)
    d.rectangle([w - b, 0, w, h], fill=t)
    d.rectangle([0, h - b * 2, w, h], fill=t)
    d.rectangle([0, 0, w, b // 2], fill=t)
    for y0 in (b * 3,):   # a thin inner line
        d.rectangle([b + 6, 0, b + 9, h - b * 2 - 6], fill=t)
        d.rectangle([w - b - 9, 0, w - b - 6, h - b * 2 - 6], fill=t)
    em = EMBLEMS.get(spec.get("emblem", ""))
    if em:
        for cy, size in ((spec.get("emblem_y", 0.2), 0.82), (spec.get("emblem_y2", 0.72), 0.66)):
            if cy is None:
                continue
            sz = w * size
            ox, oy = (w - sz) / 2, cy * h - sz / 2
            d.polygon([(ox + x * sz, oy + y * sz) for x, y in em], fill=t)
    im.save(path)


def make_panel(body, spec, root):
    import bmesh
    import mathutils
    from mathutils.bvhtree import BVHTree
    rig = _rig_of(body)
    dg = bpy.context.evaluated_depsgraph_get()
    skip = tuple(spec.get("ignore", ["hair", "beard", "moustache", "eye", "brow", "lash", "teeth", "tongue"]))
    trees = []
    for o in [body] + ObjectService.get_list_of_children(root):
        if o.type == "MESH" and o.name.startswith(("outfit_", body.name)) and not any(k in o.name.lower() for k in skip):
            if o.name.startswith("outfit_panel"):
                continue
            trees.append(BVHTree.FromObject(o, dg))
    hips = _bone_head(rig, "Hips")
    sp = {n: _bone_head(rig, n).z for n in ("Hips", "Spine", "Spine1", "Spine2", "Neck")}
    knee = _bone_head(rig, "LeftLeg").z
    top = sp["Spine2"] + (sp["Neck"] - sp["Spine2"]) * spec.get("top", 0.6)
    bottom = knee + (hips.z - knee) * spec.get("bottom", 0.0)
    belt = hips.z + spec.get("belt", 0.04)
    gap = spec.get("gap", 0.012)
    rows, cols = 28, spec.get("columns", 9)
    wt, wb = spec.get("width_top", 0.32), spec.get("width_bottom", 0.26)

    def surface(x, z, side):
        """y of the outermost dressed surface at (x, z); side -1 front, +1 back."""
        best = None
        for t in trees:
            hit = t.ray_cast(mathutils.Vector((x, side * 1.5, z)), mathutils.Vector((0, -side, 0)))
            if hit[0] is not None:
                y = hit[0].y
                if best is None or (side < 0 and y < best) or (side > 0 and y > best):
                    best = y
        return best

    made = []
    sides = {"front": -1, "back": 1}
    for side in [sides[n] for n in spec.get("sides", ["front", "back"] if spec.get("back", True) else ["front"])]:
        zs = [top + (bottom - top) * r / (rows - 1) for r in range(rows)]
        widths = [wt if z >= belt else wb for z in zs]
        if spec.get("neck_width"):   # a cape: narrow at the neck, out over the shoulders, flaring to the hem
            nw, drop = spec["neck_width"], spec.get("shoulder_drop", 0.1)
            widths = []
            for z in zs:
                if z > top - drop:
                    t = (top - z) / drop
                    widths.append(nw + (wt - nw) * math.sin(t * math.pi / 2))
                else:
                    t = (top - drop - z) / max(0.01, top - drop - bottom)
                    widths.append(wt + (wb - wt) * t)
        grid = []
        for z, w in zip(zs, widths):
            xs = [-w / 2 + w * c / (cols - 1) for c in range(cols)]
            ys = [surface(x, z, side) for x in xs]
            if z < belt:   # hang straight: outermost point of the body across the width
                probe = [surface(-wt / 2 + wt * c / 12, z, side) for c in range(13)]
                probe = [p for p in probe if p is not None]
                ext = (min(probe) if side < 0 else max(probe)) if probe else None
                ys = [ext] * cols
            grid.append([(x, y, z) for x, y in zip(xs, ys)])
        # fill misses from the row above; keep the hanging part from bending inwards
        for r in range(rows):
            for c in range(cols):
                x, y, z = grid[r][c]
                if y is None:
                    y = grid[r - 1][c][1] if r else hips.y + side * 0.15
                grid[r][c] = (x, y, z)
        for r in range(1, rows):
            if zs[r] < belt:
                for c in range(cols):
                    x, y, z = grid[r][c]
                    yp = grid[r - 1][c][1]
                    y = min(y, yp) if side < 0 else max(y, yp)
                    grid[r][c] = (x, y, z)
        folds = spec.get("folds", 0)
        if folds:   # hanging cloth falls in folds that deepen towards the hem
            for r in range(rows):
                z = zs[r]
                depth = spec.get("fold_depth", 0.025) * max(0.0, min(1.0, (top - z) / max(0.01, top - bottom))) ** 0.7
                for c in range(cols):
                    x, y, zz = grid[r][c]
                    grid[r][c] = (x, y + side * depth * (0.5 + 0.5 * math.sin(c / (cols - 1) * folds * 2 * math.pi)), zz)
        flare = spec.get("flare", 0.0)
        if flare:   # loose cloth: falls away from the back towards the hem
            for r in range(rows):
                t = max(0.0, min(1.0, (top - zs[r]) / max(0.01, top - bottom)))
                for c in range(cols):
                    x, y, zz = grid[r][c]
                    grid[r][c] = (x, y + side * flare * t ** 1.5, zz)
        me = bpy.data.meshes.new("panel")
        bm = bmesh.new()
        vs = [[bm.verts.new((x, y + side * gap, z)) for (x, y, z) in row] for row in grid]
        uvl = bm.loops.layers.uv.new()
        for r in range(rows - 1):
            for c in range(cols - 1):
                quad = [vs[r][c], vs[r][c + 1], vs[r + 1][c + 1], vs[r + 1][c]]
                f = bm.faces.new(list(reversed(quad)) if side < 0 else quad)   # normals face outwards
                for lp in f.loops:
                    ri = next(i for i in range(rows) if lp.vert in vs[i])
                    ci = vs[ri].index(lp.vert)
                    u = ci / (cols - 1)
                    lp[uvl].uv = (u if side < 0 else 1 - u, 1 - ri / (rows - 1))
        bm.to_mesh(me)
        bm.free()
        only = len(spec.get("sides", ["front", "back"])) == 1
        name = "outfit_" + spec["id"] + ("" if side < 0 or only else "_back")
        ob = bpy.data.objects.new(name, me)
        body.users_collection[0].objects.link(ob)
        # paint and material
        tex = os.path.join(TEX, "_gen_" + spec["id"] + ".png")
        _paint_panel(tex, spec)
        m = bpy.data.materials.new(name + "_mat")
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        bsdf.inputs["Roughness"].default_value = 0.92
        img = nt.nodes.new("ShaderNodeTexImage")
        img.image = bpy.data.images.load(tex, check_existing=False)
        img.image.pack()
        nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
        me.materials.append(m)
        for f in me.polygons:   # soft shading over the folds
            f.use_smooth = True
        sol = ob.modifiers.new("thick", "SOLIDIFY")
        sol.thickness = spec.get("thickness", 0.004)
        sol.offset = 0.0
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier="thick")
        # weights: torso bones by height above the belt, hips + thighs below
        groups = {}

        def add(bone, i, wgt):
            if wgt <= 0:
                return
            if bone not in groups:
                groups[bone] = ob.vertex_groups.new(name=B + bone)
            groups[bone].add([i], wgt, "ADD")
        legs = spec.get("legs", 0.35)
        chain = [("Hips", sp["Hips"]), ("Spine", sp["Spine"]), ("Spine1", sp["Spine1"]), ("Spine2", sp["Spine2"])]
        springs = _cape_bones(rig, spec, grid, zs, belt, side * gap) if spec.get("bones") else None
        for v in ob.data.vertices:
            z = v.co.z
            if springs and z < springs["z0"]:   # the hanging part moves with its own (simulated) bones
                for bone, w in _spring_weights(springs, v.co.x, z):
                    if bone not in groups:
                        groups[bone] = ob.vertex_groups.new(name=bone)
                    groups[bone].add([v.index], w, "ADD")
                continue
            if z < belt:
                k = min(1.0, (belt - z) / max(0.01, belt - bottom)) * legs
                add("Hips", v.index, 1.0 - k)
                add("LeftUpLeg", v.index, k / 2)
                add("RightUpLeg", v.index, k / 2)
                continue
            for (b0, z0), (b1, z1) in zip(chain, chain[1:]):
                if z <= z1:
                    t = max(0.0, min(1.0, (z - z0) / max(0.01, z1 - z0)))
                    add(b0, v.index, 1 - t)
                    add(b1, v.index, t)
                    break
            else:
                add("Spine2", v.index, 1.0)
        ob.parent = rig
        am = ob.modifiers.new("Armature", "ARMATURE")
        am.object = rig
        made.append(ob)
        print("  panel:", name, len(ob.data.vertices), "verts")
    return made


def _cape_bones(rig, spec, grid, zs, belt, dy):
    """Adds chains of bones down the hanging part of a cape (named
    <id>_<chain>_<segment>, parented to Spine2) for the game's spring-bone
    simulation, so the cloth hangs with gravity and swings."""
    cfg = spec["bones"]
    nch, nseg = cfg.get("chains", 5), cfg.get("segments", 4)
    rows, cols = len(grid), len(grid[0])
    r0 = next((r for r in range(rows) if zs[r] < belt), rows - 2)
    cols_at = [round(j * (cols - 1) / (nch - 1)) for j in range(nch)]
    joint_rows = [round(r0 + (rows - 1 - r0) * k / nseg) for k in range(nseg + 1)]
    inv = rig.matrix_world.inverted()
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = rig.data.edit_bones
    parent = ebs.get(B + cfg.get("parent", "Spine2"))
    xs = []
    for j, c in enumerate(cols_at):
        prev = parent
        xs.append(grid[r0][c][0])
        for k in range(nseg):
            a = grid[joint_rows[k]][c]
            b = grid[joint_rows[k + 1]][c]
            bone = ebs.new(f"{spec['id']}_{j}_{k}")
            bone.head = inv @ mathutils.Vector((a[0], a[1] + dy, a[2]))
            bone.tail = inv @ mathutils.Vector((b[0], b[1] + dy, b[2]))
            bone.parent = prev
            bone.use_connect = k > 0
            bone.use_deform = True
            prev = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    return {"id": spec["id"], "xs": xs, "z_joints": [zs[r] for r in joint_rows], "z0": zs[r0] + 0.0005, "nseg": nseg}


def _spring_weights(sp, x, z):
    """Weights of a cape vertex: the segment it hangs in, shared between
    the two nearest chains across the width."""
    zj = sp["z_joints"]
    k = 0
    while k < sp["nseg"] - 1 and z < zj[k + 1]:
        k += 1
    xs = sp["xs"]
    if x <= xs[0]:
        return [(f"{sp['id']}_0_{k}", 1.0)]
    if x >= xs[-1]:
        return [(f"{sp['id']}_{len(xs) - 1}_{k}", 1.0)]
    j = max(i for i in range(len(xs) - 1) if xs[i] <= x)
    t = (x - xs[j]) / max(1e-6, xs[j + 1] - xs[j])
    return [(f"{sp['id']}_{j}_{k}", 1 - t), (f"{sp['id']}_{j + 1}_{k}", t)]


# ---------------------------------------------------------------- beards
# A full beard grown from the face: rings from the cheeks down to the chest,
# each wrapped over the (dressed) body and pushed out by a thickness that
# fades towards the sides and the tip. Below the chin it hangs straight
# (never tucks into the neck). Optional braids with metal rings.
def _paint_hair(path, colour, seed=3):
    from PIL import Image, ImageDraw, ImageFilter
    import random
    w, h = 512, 1024
    base = tuple(int(c * 255) for c in colour)
    im = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for _ in range(2600):
        x = rnd.uniform(0, w)
        y = rnd.uniform(-h * 0.2, h)
        length = rnd.uniform(h * 0.15, h * 0.6)
        k = rnd.uniform(0.6, 1.35)
        col = tuple(max(0, min(255, int(c * k))) for c in base)
        pts = []
        for i in range(12):
            t = i / 11
            pts.append((x + math.sin(t * 3 + x) * 6, y + t * length))
        d.line(pts, fill=col, width=rnd.choice((1, 1, 2, 3)))
    im = im.filter(ImageFilter.GaussianBlur(0.7))
    im.save(path)


def _hair_material(name, tex, rough=0.75):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = rough
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(tex, check_existing=False)
    img.image.pack()
    nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def make_beard(body, spec, root):
    import bmesh
    import mathutils
    from mathutils.bvhtree import BVHTree
    rig = _rig_of(body)
    dg = bpy.context.evaluated_depsgraph_get()
    skip = ("hair", "beard", "moustache", "eye", "brow", "lash", "teeth", "tongue")
    trees = [BVHTree.FromObject(o, dg) for o in [body] + ObjectService.get_list_of_children(root)
             if o.type == "MESH" and (o == body or o.name.startswith("outfit_")) and not any(k in o.name.lower() for k in skip)]
    head = _bone_head(rig, "Head")
    neck = _bone_head(rig, "Neck")
    yc = head.y
    # landmarks from the body: mouth (teeth) and chin
    teeth = next((o for o in ObjectService.get_list_of_children(root) if "teeth" in o.name and o.type == "MESH"), None)
    z_mouth = (sum((teeth.matrix_world @ v.co).z for v in teeth.data.vertices) / len(teeth.data.vertices)) if teeth else head.z + 0.06
    front = [body.matrix_world @ v.co for v in body.data.vertices]
    chin_pts = [p for p in front if abs(p.x) < 0.012 and head.z - 0.06 < p.z < z_mouth and p.y < yc - 0.03]
    z_chin = min(p.z for p in chin_pts) if chin_pts else head.z - 0.02
    z_top = z_mouth + spec.get("top", 0.045)
    z_bot = z_chin - spec.get("length", 0.3)
    T = spec.get("thickness", 0.045)
    K, N = 30, 29
    amax = math.radians(spec.get("max_angle", 72))

    def surface_r(theta, z):
        d = mathutils.Vector((math.sin(theta), -math.cos(theta), 0.0))
        o = mathutils.Vector((d.x * 0.6, yc + d.y * 0.6, z))
        best = None
        for t in trees:
            hit = t.ray_cast(o, -d, 0.6)
            if hit[0] is not None and (best is None or hit[3] < best):
                best = hit[3]
        return 0.6 - best if best is not None else None

    rings = []
    prev = None
    for k in range(K):
        t = k / (K - 1)
        z = z_top + (z_bot - z_top) * t
        w = spec.get("width_top", 0.085) + (spec.get("width_bottom", 0.025) - spec.get("width_top", 0.085)) * (t ** 1.3)
        thick = T * (0.25 + 0.75 * math.sin(min(1.0, t * 2.4) * math.pi / 2)) * (1 - t) ** 0.45
        row = []
        for j in range(N):
            th = -amax + 2 * amax * j / (N - 1)
            rs = surface_r(th, z)
            if rs is None:
                rs = prev[j][0] + 0.006 if prev else 0.08
            x = abs(math.sin(th)) * rs
            cover = math.cos(math.pi / 2 * min(1.0, x / w)) ** 0.5 if x < w and abs(th) < math.radians(80) else 0.0
            cover *= min(1.0, (z_top - z) / 0.035 + 0.15)   # soft top edge (no steps at the sideburns)
            cheek = spec.get("mouth_half_width", 0.032)
            if z > z_mouth - spec.get("below_lip", 0.016):   # beside the mouth only (sideburns, cheeks)
                cover *= max(0.0, min(1.0, (x - cheek) / 0.015))
            if cover > 0.03:
                ri = rs - 0.006
                ro = rs + 0.003 + thick * cover
            else:   # no beard here: fold the shell away deep inside the body
                ri = ro = min(rs - 0.03, 0.03)   # (near the neck axis: inside head, neck and chest)
            if prev is not None and z < z_chin and cover > 0.03:   # hang: do not tuck in under the chin
                ro = max(ro, prev[j][1] - 0.003)
            row.append((ri, ro, th))
        rings.append((z, row))
        prev = row
    # mesh: outer and inner shell, closed
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    outer, inner = [], []
    for z, row in rings:
        o_r, i_r = [], []
        for ri, ro, th in row:
            d = (math.sin(th), -math.cos(th))
            o_r.append(bm.verts.new((d[0] * ro, yc + d[1] * ro, z)))
            i_r.append(bm.verts.new((d[0] * ri, yc + d[1] * ri, z)))
        outer.append(o_r)
        inner.append(i_r)
    def quad(vs, uvs):
        try:
            f = bm.faces.new(vs)
        except ValueError:
            return
        for lp, uv in zip(f.loops, uvs):
            lp[uvl].uv = uv
    for k in range(K - 1):
        for j in range(N - 1):
            u0, u1, v0, v1 = j / (N - 1), (j + 1) / (N - 1), 1 - k / (K - 1), 1 - (k + 1) / (K - 1)
            quad([outer[k][j], outer[k + 1][j], outer[k + 1][j + 1], outer[k][j + 1]], [(u0, v0), (u0, v1), (u1, v1), (u1, v0)])
            quad([inner[k][j + 1], inner[k + 1][j + 1], inner[k + 1][j], inner[k][j]], [(u1, v0), (u1, v1), (u0, v1), (u0, v0)])
        for j in (0, N - 1):
            quad([outer[k][j], inner[k][j], inner[k + 1][j], outer[k + 1][j]], [(0, 1 - k / K)] * 4)
    for k in (0, K - 1):
        for j in range(N - 1):
            quad([outer[k][j], outer[k][j + 1], inner[k][j + 1], inner[k][j]], [(j / N, 1.0)] * 4)
    # shell faces point away from the neck axis (Godot culls back faces)
    for f in bm.faces:
        c = f.calc_center_median()
        f.normal_update()
        if f.normal.dot(mathutils.Vector((c.x, c.y - yc, 0.0))) < 0:
            f.normal_flip()
    shell = set(bm.faces)
    # braids: lumps hanging over the beard, with metal rings
    ring_faces = []
    for bspec in spec.get("braids", []):
        xb0 = bspec.get("x", 0.035)
        z0 = z_chin + bspec.get("start", -0.01)
        z1 = z_bot + bspec.get("end", 0.0)
        r0 = bspec.get("radius", 0.016)
        n = max(3, int((z0 - z1) / (r0 * 1.15)))
        rings_at = set(bspec.get("rings", [0.25, 0.55, 0.85]))
        for i in range(n):
            t = i / (n - 1)
            z = z0 + (z1 - z0) * t
            # on top of the beard at this height, at the column closest to x
            kk = min(K - 1, max(0, int(round((z_top - z) / (z_top - z_bot) * (K - 1)))))
            xb = xb0 * (1 - 0.45 * t)
            row = rings[kk][1]
            cand = [(abs(math.sin(th_) * ro_ - abs(xb)), ro_, th_) for ri_, ro_, th_ in row
                    if ro_ > ri_ + 0.002 and (th_ > 0) == (xb0 > 0)]
            if not cand:
                continue
            _, ro_, th_ = min(cand)
            rr = ro_ + r0 * 0.45
            d = (math.sin(th_), -math.cos(th_))
            side = 0.004 * (1 if i % 2 else -1)
            c = mathutils.Vector((d[0] * rr + side, yc + d[1] * rr, z))
            r = r0 * (1 - 0.35 * t)
            ret = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=1.0)
            tilt = mathutils.Matrix.Rotation(math.radians(28 if i % 2 else -28), 3, "Y")   # plaited strands
            for v in ret["verts"]:
                v.co = c + tilt @ mathutils.Vector((v.co.x * r * 0.95, v.co.y * r * 0.8, v.co.z * r * 1.5))
            if any(abs(t - q) < 0.5 / n for q in rings_at):
                ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=1.0, radius2=1.0, depth=1.0)
                for v in ret["verts"]:
                    v.co = c + mathutils.Vector((v.co.x * r * 1.3, v.co.y * r * 1.3, v.co.z * 0.012))
                ring_faces.extend({f for v in ret["verts"] for f in v.link_faces})
    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f not in shell])
    me = bpy.data.meshes.new("beard")
    for f in ring_faces:
        f.material_index = 1
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("outfit_" + spec.get("id", "beard"), me)
    body.users_collection[0].objects.link(ob)
    tex = os.path.join(TEX, "_gen_" + spec.get("id", "beard") + ".png")
    _paint_hair(tex, spec.get("color", (0.42, 0.17, 0.07)))
    me.materials.append(_hair_material(ob.name + "_mat", tex))
    me.materials.append(_material("gold", tuple(spec.get("ring_color", (0.85, 0.62, 0.22)))))
    for f in me.polygons:
        f.use_smooth = True
    # weights: the face part follows the head, the hanging part the chest
    hg = ob.vertex_groups.new(name=B + "Head")
    ng = ob.vertex_groups.new(name=B + "Neck")
    sg = ob.vertex_groups.new(name=B + "Spine2")
    z_s = z_chin - spec.get("chest_blend", 0.12)
    for v in me.vertices:
        z = v.co.z
        if z >= z_chin:
            hg.add([v.index], 1.0, "REPLACE")
        elif z >= z_s:
            t = (z_chin - z) / (z_chin - z_s)
            hg.add([v.index], 1 - t, "REPLACE")
            ng.add([v.index], t * 0.5, "REPLACE")
            sg.add([v.index], t * 0.5, "REPLACE")
        else:
            ng.add([v.index], 0.3, "REPLACE")
            sg.add([v.index], 0.7, "REPLACE")
    ob.parent = rig
    am = ob.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    print("  beard:", ob.name, len(me.vertices), "verts, chin", round(z_chin, 3), "mouth", round(z_mouth, 3))
    return ob


# ---------------------------------------------------------------- props
# Small generated gear worn on the body (a quiver with arrows), rigid on one bone.
def make_quiver(body, spec, root):
    import bmesh
    import mathutils
    from mathutils.bvhtree import BVHTree
    rig = _rig_of(body)
    dg = bpy.context.evaluated_depsgraph_get()
    trees = [BVHTree.FromObject(o, dg) for o in [body] + ObjectService.get_list_of_children(root)
             if o.type == "MESH" and (o == body or o.name.startswith("outfit_")) and "hair" not in o.name.lower()]
    sp2 = _bone_head(rig, "Spine2")
    sp1 = _bone_head(rig, "Spine1")
    z = (sp1.z + sp2.z) / 2 + spec.get("up", 0.0)
    x = spec.get("x", -0.04)
    back = None
    for t in trees:
        hit = t.ray_cast(mathutils.Vector((x, 1.5, z)), mathutils.Vector((0, -1, 0)))
        if hit[0] is not None and (back is None or hit[0].y > back):
            back = hit[0].y
    back = back if back is not None else sp2.y + 0.15
    L, R = spec.get("length", 0.5), spec.get("radius", 0.05)
    centre = mathutils.Vector((x, back + R + spec.get("gap", 0.01), z))
    tilt = mathutils.Matrix.Rotation(math.radians(spec.get("tilt", -25)), 3, "Y")
    bm = bmesh.new()
    bm.loops.layers.uv.new()   # create_cone fills it (calc_uvs); textures need UVs
    ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=14, radius1=R, radius2=R * 1.12, depth=L, calc_uvs=True)
    for v in ret["verts"]:
        v.co = centre + tilt @ v.co
    leather = set(bm.faces)
    wood, feather = set(), set()
    n = spec.get("arrows", 7)
    for i in range(n):
        a = 2 * math.pi * i / n
        off = mathutils.Vector((math.cos(a) * R * 0.5, math.sin(a) * R * 0.5, 0))
        h = spec.get("arrow_out", 0.2) + 0.02 * (i % 3)
        r = bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.004, radius2=0.004, depth=h, calc_uvs=True)
        for v in r["verts"]:
            v.co = centre + tilt @ (v.co + off + mathutils.Vector((0, 0, L / 2 + h / 2 - 0.02)))
        wood |= {f for v in r["verts"] for f in v.link_faces}
        for k in range(3):   # three vanes near the nock
            b = a + k * 2 * math.pi / 3
            d = mathutils.Vector((math.cos(b), math.sin(b), 0)) * 0.016
            top = mathutils.Vector((0, 0, L / 2 + h - 0.025))
            low = mathutils.Vector((0, 0, L / 2 + h - 0.085))
            pts = [off + top, off + top + d, off + low + d * 0.6, off + low]
            vs = [bm.verts.new(centre + tilt @ p) for p in pts]
            f = bm.faces.new(vs)
            feather.add(f)
    me = bpy.data.meshes.new("quiver")
    for f in bm.faces:
        f.material_index = 2 if f in feather else (1 if f in wood else 0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("outfit_" + spec.get("id", "quiver"), me)
    body.users_collection[0].objects.link(ob)
    me.materials.append(_material("leather", tuple(spec.get("color", (0.36, 0.22, 0.12)))))
    me.materials.append(_material("leather_dark", (0.45, 0.32, 0.2)))
    me.materials.append(_material("cloth", (0.85, 0.83, 0.78)))
    g = ob.vertex_groups.new(name=B + "Spine2")
    g.add([v.index for v in me.vertices], 1.0, "REPLACE")
    ob.parent = rig
    am = ob.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    print("  quiver:", ob.name, len(me.vertices), "verts")
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
    # extra body shape targets, e.g. {"legs/measure-upperleg-height-decr": 0.8}
    tdir = os.path.join(os.path.dirname(importlib.import_module("bl_ext.user_default.mpfb").__file__), "data", "targets")
    for name, weight in body.get("targets", {}).items():
        path = os.path.join(tdir, name + ".target.gz")
        if os.path.exists(path):
            TargetService.load_target(bm, path, weight=float(weight))
        else:
            print("  ! target not found:", name)
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
                if c.get("scale"):  # [width, depth, length] about its top-back-centre (a fuller beard)
                    sx, sy, sz = c["scale"]
                    xs = [v.co.x for v in o.data.vertices]
                    ys = [v.co.y for v in o.data.vertices]
                    zs = [v.co.z for v in o.data.vertices]
                    ax, ay, az = (min(xs) + max(xs)) / 2, max(ys), max(zs)
                    for v in o.data.vertices:
                        v.co.x = ax + (v.co.x - ax) * sx
                        v.co.y = ay + (v.co.y - ay) * sy
                        v.co.z = az + (v.co.z - az) * sz
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
    rig_obj = _rig_of(eb)
    for o in ObjectService.get_list_of_children(root):
        if o.type == "MESH" and o.vertex_groups and not any(k in o.name for k in ("hair", "beard", "moustache")):
            clean_weights(o, rig_obj)
    split_body_by_clothes(eb, body.get("clothes", []))
    for spec in body.get("armour", []):
        fit_armour(eb, spec)
    for spec in body.get("rigid", []):
        fit_rigid(eb, spec)
    for spec in body.get("panels", []):
        make_panel(eb, spec, root)
    for spec in body.get("beards", []):
        make_beard(eb, spec, root)
    for spec in body.get("props", []):
        if spec.get("type", "quiver") == "quiver":
            make_quiver(eb, spec, root)
    # stand on the floor: body targets (shorter legs) lift the feet off zero
    skin = [eb] + [o for o in ObjectService.get_list_of_children(root) if o.type == "MESH" and o.name.startswith("body_hide")]
    low = min((o.matrix_world @ v.co).z for o in skin for v in o.data.vertices)   # feet under boots are split off
    if abs(low) > 0.002:
        root.location.z -= low
        print("  grounded: moved down", round(low, 3))
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
