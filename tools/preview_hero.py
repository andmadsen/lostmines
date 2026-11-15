"""Renders a quick preview of a built hero (front, side, back, 3/4 and a head
close-up) with Blender, showing only the outfit layers you list.

    python3 tools/preview_hero.py <glb> <out.png> [shown outfits, comma separated]

Example:
    python3 tools/preview_hero.py assets/characters/keldrin_mh.glb /tmp/k.png pants,boots,beard,tabard
Meshes named outfit_<id> are hidden unless listed; body_hide_* are hidden.
"""
import math
import os
import sys

import bpy
import mathutils

glb, out = sys.argv[1], sys.argv[2]
shown = set(sys.argv[3].split(",")) if len(sys.argv) > 3 and sys.argv[3] else set()

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=glb)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    hide = o.name.startswith("body_hide") or (o.name.startswith("outfit_") and o.name[7:] not in shown)
    o.hide_render = hide
vis = [o for o in meshes if not o.hide_render and o.name.startswith("Human")] or [o for o in meshes if not o.hide_render]
pts = [o.matrix_world @ mathutils.Vector(c) for o in vis for c in o.bound_box]
lo = mathutils.Vector([min(p[i] for p in pts) for i in range(3)])
hi = mathutils.Vector([max(p[i] for p in pts) for i in range(3)])

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x, scene.render.resolution_y = 360, 640
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
cam.data.type = "ORTHO"
scene.camera = cam

frames = []
height = hi.z - lo.z
views = [(0, 0.5, 1.15), (90, 0.5, 1.15), (180, 0.5, 1.15), (35, 0.5, 1.15), (15, 0.8, 0.42)]
for i, (yaw, cz, size) in enumerate(views):
    c = mathutils.Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z + height * cz))
    a = math.radians(yaw)
    d = mathutils.Vector((math.sin(a), -math.cos(a), 0.05))
    cam.data.ortho_scale = height * size
    cam.location = c + d * 5
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    p = f"/tmp/_prev_{i}.png"
    scene.render.filepath = p
    bpy.ops.render.render(write_still=True)
    frames.append(p)

from PIL import Image  # noqa: E402
ims = [Image.open(p) for p in frames]
sheet = Image.new("RGB", (sum(im.width for im in ims), ims[0].height), "white")
x = 0
for im in ims:
    sheet.paste(im, (x, 0))
    x += im.width
sheet.save(out)
print("preview", out, "height", round(height, 3))
