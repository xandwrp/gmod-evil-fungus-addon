"""Renders the workshop thumbnail in Blender: someone asleep on the mat in a dark corner of
gm_construct, cocooned and wired in, caught in a flashlight, the mat spreading out from under them.

The map comes from the blender-agent-toolkit's source/bsp_to_obj.py:

    python bsp_to_obj.py .../garrysmod/maps/gm_construct.bsp renders/gm_construct --vpk ...
    blender --background --python tools/render_thumbnail.py -- --map renders/gm_construct --out renders
    python tools/finish_thumbnail.py renders

Everything is built in Source units and scaled down by SCALE, the same as the map.
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

SCALE = 0.02
SEED = 1998
SPOT = (-2105, -1330, 40)  # where the fungus is, dropped onto the floor below
YAW = 90  # which way the sleeper lies, head first

# The mat, grown toward points scattered over a lumpy patch.
MAT_RADIUS = 330
MAT_LUMP = 0.3
ATTRACTORS = 16000
SPACING = 6
INFLUENCE = 40
KILL = 7
FUSE = 18
FUSE_CHANCE = 0.7
R_THIN, R_THICK = 0.2, 1.2
PIPE = 2.6  # how fast strands thicken with how much of the mat they feed
LIFT = 0.45

# The body, wound round the sleeper and thrown over them.
COCOON_PITCH = 0.75  # how close the cocoon's turns lie
R_COCOON = (0.3, 0.5)
WRAPS = 7
R_BODY = (0.45, 1.0)

SIDES = 7
SUB = 3

ROOT = (175, 165, 150)
VEIN = (200, 175, 140)
BODY_THIN = (200, 185, 180)
BODY_THICK = (140, 95, 105)
SKIN = (196, 150, 128)

SUN = 0.1
LAMP = 0.6
SKY = 0.06
SKY_COLOR = tuple((c / 255) ** 2.2 for c in (142, 164, 178)) + (1,)

CAMERA = dict(at=(-68, 44, 64), look=(0, 9, 4), lens=40, fstop=4)
SIZE = (1024, 1024)
EXPOSURE = -0.5
TORCH = dict(energy=700, cone=38, blend=0.8, at=(-14, 6, 22))

rand = random.Random(SEED)


def linear(c, k=1.0):
    return tuple(min(1, max(0, v * k / 255)) ** 2.2 for v in c) + (1,)


def lerp_color(a, b, f):
    return tuple(a[i] + (b[i] - a[i]) * f for i in range(3))


# ------------------------------------------------------------------ stage (as in the crawler's render_assets.py)

def fix_material(m, info):
    if not m or not m.use_nodes:
        return
    nt = m.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if not bsdf:
        return
    bsdf.inputs["Roughness"].default_value = 0.85
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25
    image = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None)
    if image and (info.get("translucent") or info.get("alphatest")):
        nt.links.new(image.outputs["Alpha"], bsdf.inputs["Alpha"])
    if info.get("water"):
        bsdf.inputs["Base Color"].default_value = (0.02, 0.04, 0.05, 1)
        bsdf.inputs["Roughness"].default_value = 0.05
    if not image and "glass" in m.name.lower():
        bsdf.inputs["Transmission Weight"].default_value = 1
        bsdf.inputs["Roughness"].default_value = 0.05


def stage(map_dir):
    with open(os.path.join(map_dir, "scene.json")) as f:
        info = json.load(f)
    bpy.ops.wm.obj_import(filepath=os.path.join(map_dir, "map.obj"), forward_axis="Y", up_axis="Z")
    for ob in bpy.context.selected_objects:
        for slot in ob.material_slots:
            fix_material(slot.material, info["materials"].get(slot.material.name.lower(), {}))

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = SKY_COLOR
    bg.inputs["Strength"].default_value = SKY
    bpy.context.scene.world = world

    for l in info["lights"]:
        if l["kind"] == "light_environment":
            d = Vector(l["direction"])
            if d.z > 0:
                d = -d
            data = bpy.data.lights.new("Sun", "SUN")
            data.energy = SUN * l["brightness"] / 255
            data.angle = math.radians(1.5)
            ob = bpy.data.objects.new("Sun", data)
            ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        else:
            spot = l["kind"] == "light_spot"
            data = bpy.data.lights.new("MapLight", "SPOT" if spot else "POINT")
            data.energy = LAMP * l["brightness"]
            data.shadow_soft_size = 0.15
            if spot:
                data.spot_size = math.radians(min(175, l["outer"] * 2))
                data.spot_blend = max(0, min(1, 1 - l["inner"] / max(1, l["outer"])))
            ob = bpy.data.objects.new("MapLight", data)
            ob.location = l["origin"]
            if spot:
                ob.rotation_euler = Vector(l["direction"]).to_track_quat("-Z", "Y").to_euler()
        data.color = l["color"]
        bpy.context.scene.collection.objects.link(ob)


def floor_at(x, y, z):
    deps = bpy.context.evaluated_depsgraph_get()
    hit, loc, normal, *_ = bpy.context.scene.ray_cast(deps, Vector((x, y, z)) * SCALE, Vector((0, 0, -1)))
    if not hit:
        raise RuntimeError("no floor under %s" % ((x, y, z),))
    return loc / SCALE


# ------------------------------------------------------------------ meshes

def tube(points, radii, colors, verts, faces, cols, sides=SIDES, caps=True):
    """A smooth tube through points, appended to one big mesh."""
    n = len(points)
    samples = []
    for i in range(n - 1):
        p0, p1, p2, p3 = points[max(i - 1, 0)], points[i], points[i + 1], points[min(i + 2, n - 1)]
        for s in range(SUB):
            t = s / SUB
            t2, t3 = t * t, t * t * t
            p = (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
            samples.append((p, radii[i] + (radii[i + 1] - radii[i]) * t, lerp_color(colors[i], colors[i + 1], t)))
    samples.append((points[-1], radii[-1], colors[-1]))

    base = len(verts)
    normal = None
    count = len(samples)
    for j, (p, r, c) in enumerate(samples):
        a, b = samples[max(j - 1, 0)][0], samples[min(j + 1, count - 1)][0]
        tan = b - a
        tan = tan.normalized() if tan.length > 1e-6 else Vector((0, 0, 1))
        if normal is None:
            normal = Vector((0, 0, 1)) if abs(tan.z) < 0.9 else Vector((1, 0, 0))
        normal = normal - tan * normal.dot(tan)
        if normal.length < 1e-6:
            normal = tan.orthogonal()
        normal.normalize()
        binormal = tan.cross(normal)
        col = linear(c)
        for k in range(sides):
            ang = k / sides * math.pi * 2
            verts.append(tuple((p + (normal * math.cos(ang) + binormal * math.sin(ang)) * r) * SCALE))
            cols.append(col)
    for j in range(count - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            faces.append((base + j * sides + k, base + j * sides + k2, base + (j + 1) * sides + k2, base + (j + 1) * sides + k))
    if caps:
        for end, sign in ((0, -1), (count - 1, 1)):
            p, r, _ = samples[end]
            q = samples[end - sign][0] if 0 <= end - sign < count else p
            d = p - q
            tip = p + (d.normalized() if d.length > 1e-6 else Vector((0, 0, 1))) * r * 0.8
            ring = base + end * sides
            verts.append(tuple(tip * SCALE))
            cols.append(cols[ring])
            c = len(verts) - 1
            for k in range(sides):
                k2 = (k + 1) % sides
                faces.append((ring + k2, ring + k, c) if sign < 0 else (ring + k, ring + k2, c))


def add_mesh(name, verts, faces, cols, material):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i, c in enumerate(cols):
        attr.data[i].color = c
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def material(name, roughness, coat, subsurface, sss_radius, bump, blotch=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 140
    noise.inputs["Detail"].default_value = 6
    mottle = nt.nodes.new("ShaderNodeMix")
    mottle.data_type = "RGBA"
    mottle.blend_type = "MULTIPLY"
    mottle.inputs["Factor"].default_value = 0.35
    nt.links.new(attr.outputs["Color"], mottle.inputs["A"])
    nt.links.new(noise.outputs["Color"], mottle.inputs["B"])
    if blotch:
        spots = nt.nodes.new("ShaderNodeTexNoise")
        spots.inputs["Scale"].default_value = 45
        spots.inputs["Detail"].default_value = 3
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.58
        ramp.color_ramp.elements[0].color = (1, 1, 1, 1)
        ramp.color_ramp.elements[1].position = 0.72
        ramp.color_ramp.elements[1].color = (0.35, 0.3, 0.32, 1)
        nt.links.new(spots.outputs["Fac"], ramp.inputs["Fac"])
        dark = nt.nodes.new("ShaderNodeMix")
        dark.data_type = "RGBA"
        dark.blend_type = "MULTIPLY"
        dark.inputs["Factor"].default_value = 1
        nt.links.new(mottle.outputs["Result"], dark.inputs["A"])
        nt.links.new(ramp.outputs["Color"], dark.inputs["B"])
        mottle = dark
    nt.links.new(mottle.outputs["Result"], bsdf.inputs["Base Color"])
    wet = nt.nodes.new("ShaderNodeMapRange")
    wet.inputs["To Min"].default_value = roughness * 0.5
    wet.inputs["To Max"].default_value = roughness * 1.4
    nt.links.new(noise.outputs["Fac"], wet.inputs["Value"])
    nt.links.new(wet.outputs["Result"], bsdf.inputs["Roughness"])
    bmp = nt.nodes.new("ShaderNodeBump")
    bmp.inputs["Strength"].default_value = bump
    bmp.inputs["Distance"].default_value = 0.002
    nt.links.new(noise.outputs["Fac"], bmp.inputs["Height"])
    nt.links.new(bmp.outputs["Normal"], bsdf.inputs["Normal"])
    for key, value in (("Coat Weight", coat), ("Coat Roughness", 0.15), ("Subsurface Weight", subsurface),
                       ("Subsurface Scale", 0.02)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = value
    if "Subsurface Radius" in bsdf.inputs:
        bsdf.inputs["Subsurface Radius"].default_value = sss_radius
    return m


# ------------------------------------------------------------------ the mat

def grow_mat(center):
    """Space colonisation from the middle out toward scattered points, then fused where tips meet."""
    lump = [rand.uniform(-1, 1) for _ in range(6)]

    def edge(a):
        return MAT_RADIUS * (1 + MAT_LUMP * sum(lump[i] * math.sin(a * (i + 2) + i) for i in range(6)) / 3)

    attractors = []
    while len(attractors) < ATTRACTORS:
        x, y = rand.uniform(-1, 1), rand.uniform(-1, 1)
        if x * x + y * y > 1:
            continue
        a = math.atan2(y, x)
        attractors.append(center + Vector((x, y, 0)) * edge(a))

    nodes = [dict(p=center.copy(), parent=None, kids=[])]
    for k in range(7):
        a = k / 7 * math.pi * 2
        nodes.append(dict(p=center + Vector((math.cos(a), math.sin(a), 0)) * SPACING, parent=0, kids=[]))
        nodes[0]["kids"].append(len(nodes) - 1)

    for _ in range(400):
        kd = KDTree(len(nodes))
        for i, n in enumerate(nodes):
            kd.insert(n["p"], i)
        kd.balance()
        pull = {}
        alive = []
        for a in attractors:
            p, i, d = kd.find(a)
            if d < KILL:
                continue
            alive.append(a)
            if d < INFLUENCE:
                pull.setdefault(i, Vector()).__iadd__((a - p).normalized())
        attractors = alive
        if not pull:
            break
        for i, v in pull.items():
            if v.length < 1e-6:
                continue
            v = v.normalized() + Vector((rand.uniform(-0.3, 0.3), rand.uniform(-0.3, 0.3), 0))
            v.z = 0
            p = nodes[i]["p"] + v.normalized() * SPACING
            nodes.append(dict(p=p, parent=i, kids=[]))
            nodes[i]["kids"].append(len(nodes) - 1)

    # Thickness from the tips in: what a strand carries is everything beyond it.
    for i in range(len(nodes) - 1, -1, -1):
        n = nodes[i]
        n["carry"] = 1 + sum(nodes[k]["carry"] for k in n["kids"])
    most = math.log(nodes[0]["carry"])
    for n in nodes:
        n["r"] = R_THIN + (R_THICK - R_THIN) * (math.log(n["carry"]) / most) ** PIPE

    for n in nodes:
        n["p"] = floor_at(n["p"].x, n["p"].y, n["p"].z + 30)
    return nodes


def mat_mesh(nodes, mtl):
    verts, faces, cols = [], [], []

    def colour(r):
        return lerp_color(ROOT, VEIN, (r - R_THIN) / (R_THICK - R_THIN))

    def lifted(i):
        n = nodes[i]
        return n["p"] + Vector((0, 0, n["r"] * (1 + LIFT)))

    # Chains: each strand carries on through its thickest child, the others start their own from the fork.
    starts = [0]
    while starts:
        i = starts.pop()
        chain = [i]
        while nodes[chain[-1]]["kids"]:
            kids = sorted(nodes[chain[-1]]["kids"], key=lambda k: -nodes[k]["r"])
            starts.extend(kids[1:])
            chain.append(kids[0])
        if len(chain) < 2:
            continue
        pts = [lifted(k) for k in chain]
        radii = [nodes[k]["r"] for k in chain]
        # Wander a little, the way they do in game.
        for j in range(1, len(pts) - 1):
            pts[j] = pts[j] + Vector((rand.uniform(-0.8, 0.8), rand.uniform(-0.8, 0.8), 0))
        tube(pts, radii, [colour(r) for r in radii], verts, faces, cols, sides=6 if radii[0] > 1 else 4)

    # Where tips meet another strand they fuse, so it's a net and not a tree.
    kd = KDTree(len(nodes))
    for i, n in enumerate(nodes):
        kd.insert(n["p"], i)
    kd.balance()
    def near_kin(i, j):
        for a, b in ((i, j), (j, i)):
            for _ in range(5):
                a = nodes[a]["parent"]
                if a is None:
                    break
                if a == b:
                    return True
        return False

    for i, n in enumerate(nodes):
        if rand.random() > (FUSE_CHANCE if not n["kids"] else FUSE_CHANCE * 0.3):
            continue
        for p, j, d in sorted(kd.find_range(n["p"], FUSE), key=lambda h: -h[2]):
            if j == i or d < SPACING * 0.8 or near_kin(i, j):
                continue
            a, b = lifted(i), lifted(j)
            side = (b - a).cross(Vector((0, 0, 1))).normalized() * d * rand.uniform(-0.25, 0.25)
            pts = [a, a.lerp(b, 0.33) + side + Vector((0, 0, d * 0.05)), a.lerp(b, 0.66) + side * 0.6 + Vector((0, 0, d * 0.05)), b]
            r = R_THIN
            tube(pts, [r] * 4, [colour(r)] * 4, verts, faces, cols, sides=4)
            break
    return add_mesh("Mat", verts, faces, cols, mtl)


# ------------------------------------------------------------------ the sleeper

# The sleeper: (from, to, radius) in a frame where x runs from feet to head, y to their left and z up, units above the floor.
PARTS = [
    ((24, 0, 6.5), (44, 0, 7), 6.8),  # hips to chest
    ((44, 0, 7.4), (51, 0, 7.4), 7.2),  # chest
    ((53, 0, 7), (58, 0, 6.5), 3.2),  # neck
    ((22, 4.5, 5), (2, 6.5, 4), 3.8),  # left leg
    ((22, -4.5, 5), (2, -7.5, 4), 3.8),  # right leg
    ((50, 10, 5.5), (29, 11.5, 3.5), 2.8),  # left arm
    ((50, -10, 5.5), (29, -11.5, 3.5), 2.8),  # right arm
    ((0, 7, 5.5), (-2, 7.4, 9), 2.4),  # feet
    ((0, -8, 5.5), (-2, -8.4, 9), 2.4),
]
# The head, lying face up with the crown toward +x: half its length, width and depth, and where it sits.
HEAD = dict(at=(64.3, -0.6, 4.8), size=(5.0, 3.7, 4.5), crown=1.12)
# Bumps pressed into it: (x, y, z) on the unit head, (spread along, across, up), height.
FACE = [
    ((-0.2, 0, 1), (0.22, 0.11, 0.3), 1.5),  # nose
    ((0.08, 0, 1), (0.22, 0.09, 0.3), 0.6),  # bridge
    ((0.28, 0, 1), (0.08, 0.55, 0.3), 0.45),  # brow
    ((0.14, 0.4, 1), (0.1, 0.15, 0.3), -0.75),  # eyes
    ((0.14, -0.4, 1), (0.1, 0.15, 0.3), -0.75),
    ((-0.47, 0, 1), (0.05, 0.28, 0.3), 0.35),  # upper lip
    ((-0.535, 0, 1), (0.02, 0.24, 0.3), -0.3),  # mouth
    ((-0.6, 0, 1), (0.05, 0.25, 0.3), 0.3),  # lower lip
    ((-0.85, 0, 0.9), (0.09, 0.22, 0.4), 0.5),  # chin
    ((-0.15, 0.55, 0.8), (0.18, 0.15, 0.3), 0.35),  # cheeks
    ((-0.15, -0.55, 0.8), (0.18, 0.15, 0.3), 0.35),
    ((0.05, 1, -0.1), (0.2, 0.3, 0.2), 0.9),  # ears
    ((0.05, -1, -0.1), (0.2, 0.3, 0.2), 0.9),
]
HAIR_COLOR = (58, 40, 30)


def blob(name, parts, center, frame):
    """Capsules melted together into one smooth mesh, through a metaball."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = 1.2 * SCALE
    mb.render_resolution = 0.9 * SCALE
    mb.threshold = 0.6
    ob = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(ob)
    for a, b, r in parts:
        a, b = Vector(a), Vector(b)
        el = mb.elements.new(type="CAPSULE")
        d = b - a
        el.co = (frame @ ((a + b) / 2 - Vector((32, 0, 0)))) * SCALE + center * SCALE
        el.radius = r * SCALE * 1.6
        el.size_x = max(0.01, d.length / 2) * SCALE
        el.rotation = (frame @ d).to_track_quat("X", "Z") if d.length > 1e-6 else (1, 0, 0, 0)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(ob)
    out = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(out)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    return out


def head_mesh(name, center, frame, shell=0.0, keep=None):
    """The head as a sphere squashed to size and pressed into a face. A shell sits off it, only where keep says."""
    cx, cy, cz = HEAD["at"]
    a, b, c = HEAD["size"]
    rings, segs = 48, 64
    verts, uvw = [], []
    for i in range(rings + 1):
        th = math.pi * i / rings
        for j in range(segs):
            ph = 2 * math.pi * j / segs
            # Unit direction: x toward the crown, y across, z out of the face.
            ux, uy, uz = math.cos(th), math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph)
            uvw.append((ux, uy, uz))
    faces = []
    for i in range(rings):
        for j in range(segs):
            j2 = (j + 1) % segs
            faces.append((i * segs + j, i * segs + j2, (i + 1) * segs + j2, (i + 1) * segs + j))
    for ux, uy, uz in uvw:
        sx = a * (HEAD["crown"] if ux > 0 else 1)
        # The jaw narrows toward the chin, the back of the skull is fuller than the face.
        sy = b * (1 - 0.22 * max(0, -ux) ** 1.6)
        sz = c * (1 - 0.12 * max(0, -ux) ** 2 if uz > 0 else 1.05)
        p = Vector((ux * sx, uy * sy, uz * sz))
        n = Vector((ux / sx, uy / sy, uz / sz)).normalized()
        if shell:
            p += n * shell
        else:
            for (fx, fy, fz), (sa, sb, sc), h in FACE:
                d2 = ((ux - fx) / sa) ** 2 + ((uy - fy) / sb) ** 2 + ((uz - fz) / sc) ** 2
                if d2 < 9:
                    p += n * h * math.exp(-d2)
        verts.append(tuple((center + frame @ (p + Vector((cx - 32, cy, cz)))) * SCALE))
    if keep:
        faces = [f for f in faces if all(keep(*uvw[k]) for k in f)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def paint(ob, colour):
    attr = ob.data.color_attributes["Col"]
    for i in range(len(ob.data.vertices)):
        attr.data[i].color = linear(colour)


def sleeper(center, yaw, mtl, skin):
    """Someone on their back, about the size of a player. Returns them, their BVH and their frame."""
    frame = Matrix.Rotation(math.radians(yaw), 3, "Z")
    body = blob("Sleeper", PARTS, center, frame)
    me = body.data
    attr = me.color_attributes["Col"]
    # Everything but the head has gone to fungus.
    inv = frame.inverted()
    for i, v in enumerate(me.vertices):
        x = (inv @ (Vector(v.co) / SCALE - center)).x + 32
        attr.data[i].color = linear(lerp_color(lerp_color(BODY_THIN, BODY_THICK, 0.45), SKIN, max(0, min(1, (x - 55) / 3))), 0.9)
    me.materials.append(mtl)

    head = head_mesh("Head", center, frame)
    paint(head, lerp_color(SKIN, (255, 255, 255), 0.0))
    head.data.materials.append(skin)
    # Short hair over the crown and round the back, clear of the face and ears.
    hair = head_mesh("Hair", center, frame, shell=0.35,
                     keep=lambda x, y, z: x > 0.42 - 0.5 * max(0, -z) or (z < -0.2 and abs(y) < 0.8 and x > -0.4))
    paint(hair, HAIR_COLOR)
    hair.data.materials.append(material("Hair", 0.65, 0.0, 0.0, (0.1, 0.1, 0.1), 0.8))

    verts, polys = [], []
    for ob in (body, head):
        base = len(verts)
        verts.extend(Vector(v.co) for v in ob.data.vertices)
        polys.extend([base + k for k in p.vertices] for p in ob.data.polygons)
    return body, BVHTree.FromPolygons(verts, polys), frame


def body_strands(center, frame, bvh, mtl):
    """The body: a cocoon wound round the sleeper, thick strands thrown over that down into the mat, and fibers into the face."""
    verts, faces, cols = [], [], []

    def colour(r):
        return lerp_color(BODY_THIN, BODY_THICK, (r - R_BODY[0]) / (R_BODY[1] - R_BODY[0]))

    def local(x, y, z):
        return center + frame @ Vector((x - 32, y, z))

    # The cocoon: fine strands wound round each limb in turn, close together, tucked under where they meet the floor.
    # The head too, thinner, leaving the face showing through.
    hx, hy, hz = HEAD["at"]
    ha, hb, hc = HEAD["size"]
    head = ((hx - ha * 1.05, hy, hz), (hx + ha * HEAD["crown"], hy, hz), max(hb, hc))
    for a, b, r in PARTS + [head]:
        on_head = (a, b, r) == head
        a, b = Vector(a), Vector(b)
        d = (b - a).normalized()
        u = Vector((0, 0, 1)) - d * d.z
        u.normalize()
        w = d.cross(u)
        length = (b - a).length + r * 0.8
        for k in range(int(length / COCOON_PITCH)):
            t = (k + rand.uniform(0, 0.6)) * COCOON_PITCH / length - 0.4 * r / max(length, 1)
            slant = rand.uniform(-0.12, 0.12)
            fr = rand.uniform(*R_COCOON) * (0.75 if on_head else 1)
            pts = []
            for i in range(21):
                phi = math.radians(-118 + 236 * i / 20)
                # Over the face it's a veil with gaps, not a wrapping.
                if on_head and t < 0.62 and abs(phi) < math.radians(55):
                    if len(pts) >= 5:
                        c = lerp_color(ROOT, BODY_THIN, rand.uniform(0.2, 1))
                        tube(pts, [fr] * len(pts), [c] * len(pts), verts, faces, cols, sides=5)
                    pts = []
                    continue
                tt = t + slant * (i / 20 - 0.5)
                axis = a + (b - a) * min(1.06, max(-0.06, tt))
                o = frame @ (u * math.cos(phi) + w * math.sin(phi))
                hit, *_ = bvh.ray_cast((local(*axis) + o * r * 4) * SCALE, -o)
                if hit is None or (hit / SCALE - local(*axis)).length > r * 2.4:
                    continue
                pts.append(hit / SCALE + o * fr * 0.7)
            if len(pts) < 5:
                continue
            c = lerp_color(ROOT, BODY_THIN, rand.uniform(0.2, 1))
            tube(pts, [fr] * len(pts), [c] * len(pts), verts, faces, cols, sides=5)

    # Over the top: from the mat on one side, over them, down to the mat on the other.
    for k in range(WRAPS):
        s0 = (k + rand.uniform(0, 1)) / WRAPS * 58
        lean = rand.uniform(-22, 22)
        r = rand.uniform(*R_BODY)
        pts = []
        side = rand.choice((-1, 1))
        for i in range(17):
            f = i / 16
            phi = side * (-1.25 + 2.5 * f) * math.pi / 2  # round from one side to the other
            s = s0 + lean * (f - 0.5)
            out = Vector((0, math.sin(phi), math.cos(phi)))
            axis = local(s, 0, 6)
            origin = (axis + (frame @ out) * 60) * SCALE
            hit, n, *_ = bvh.ray_cast(origin, -(frame @ out))
            if hit is None:
                continue
            pts.append(hit / SCALE + (frame @ out) * r * 0.9)
        if len(pts) < 6:
            continue
        # Run down off the sides into the mat.
        for end in (0, -1):
            p = pts[end]
            away = (p - local(rand.uniform(0, 64), 0, 0))
            away.z = 0
            out = away.normalized() * rand.uniform(8, 18)
            foot = floor_at(p.x, p.y, p.z + 5) + Vector((0, 0, r))
            # Slumps off them onto the floor and then lies along it.
            run = [foot + out * 0.25 + Vector((0, 0, (p.z - foot.z) * 0.3)), foot + out * 0.6, foot + out]
            if end == 0:
                pts[:0] = run[::-1]
            else:
                pts.extend(run)
        radii = [r * (0.8 + 0.3 * math.sin(i / len(pts) * math.pi)) for i in range(len(pts))]
        tube(pts, radii, [colour(x) for x in radii], verts, faces, cols)

    # Fine fibers up off the mat into the eyes, nose, mouth and ears.
    for s, y, z, sides in ((65.2, 1.5, 1, 1), (65.2, -2.7, 1, 1), (63.4, -0.6, 1, 1), (61.6, -0.6, 1, 2), (64.5, 3.6, 0, 1), (64.5, -4.8, 0, 1)):
        for _ in range(sides):
            out = Vector((0, math.copysign(1, y), 0)) if z == 0 else Vector((0, 0, 1))
            aim = local(s, y, 7 if z == 0 else 0)
            hit, *_ = bvh.ray_cast((aim + (frame @ out) * 40) * SCALE, -(frame @ out))
            if hit is None:
                continue
            hit = hit / SCALE
            side = math.copysign(1, y) if y else rand.choice((-1, 1))
            g = floor_at(*(local(s + rand.uniform(-6, 6), side * rand.uniform(14, 22), 10)))
            # Feels its way up: a lazy curve with a wobble in it, not a straight wire.
            across = (hit - g).cross(Vector((0, 0, 1))).normalized()
            bend, rise = rand.uniform(-4, 4), rand.uniform(4, 7)
            pts = []
            for i in range(9):
                f = i / 8
                p = g.lerp(hit, f) + across * (bend * math.sin(f * math.pi) + rand.uniform(-0.6, 0.6) * (0 < i < 8))
                pts.append(p + Vector((0, 0, 0.3 + rise * math.sin(f * math.pi) * (1 - f * 0.6))))
            tube(pts, [0.16 - 0.1 * i / 8 for i in range(9)], [BODY_THIN] * 9, verts, faces, cols, sides=4)

    # The vein from the neck down into the mat.
    neck = local(56.5, -1, 6)
    run = [floor_at(*local(x, y, 20)) + Vector((0, 0, 1.4)) for x, y in ((57, -9), (59, -15), (62, -21))]
    vein = [neck, local(56.8, -5, 3.2)] + run
    radii = [1.9, 1.8, 1.6, 1.2, 0.8]
    tube(vein, radii, [lerp_color(VEIN, BODY_THICK, 0.35)] * len(vein), verts, faces, cols, sides=9)
    return add_mesh("Body", verts, faces, cols, mtl)


# ------------------------------------------------------------------ shot

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = dict(zip(argv[::2], argv[1::2]))
    out = os.path.abspath(args.get("--out", "renders"))
    samples = int(args.get("--samples", 256))
    pct = int(args.get("--pct", 100))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    stage(os.path.abspath(args["--map"]))
    center = floor_at(*SPOT)

    fiber = material("Fiber", 0.5, 0.25, 0.1, (0.5, 0.35, 0.2), 0.25)
    flesh = material("Flesh", 0.38, 0.45, 0.12, (0.6, 0.2, 0.15), 0.35)
    fill = material("Fill", 0.32, 0.55, 0.2, (0.6, 0.2, 0.15), 0.5, blotch=True)
    nodes = grow_mat(center)
    mat_mesh(nodes, fiber)
    body, bvh, frame = sleeper(center, YAW, fill, flesh)
    body_strands(center, frame, bvh, flesh)

    # The only real light on them: a flashlight, from just over the camera.
    data = bpy.data.lights.new("Torch", "SPOT")
    data.energy, data.spot_size, data.spot_blend = TORCH["energy"], math.radians(TORCH["cone"]), TORCH["blend"]
    data.shadow_soft_size, data.color = 0.03, (1.0, 0.93, 0.8)
    ob = bpy.data.objects.new("Torch", data)
    scene.collection.objects.link(ob)
    ob.location = (center + Vector(CAMERA["at"]) + Vector(TORCH["at"])) * SCALE
    aim = center + frame @ Vector((10, 0, 4))
    ob.rotation_euler = (aim * SCALE - ob.location).to_track_quat("-Z", "Y").to_euler()

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = CAMERA["lens"]
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (center + Vector(CAMERA["at"])) * SCALE
    target = center + Vector(CAMERA["look"])
    cam.rotation_euler = (target * SCALE - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.dof.use_dof = True
    cam_data.dof.focus_distance = (target * SCALE - cam.location).length
    cam_data.dof.aperture_fstop = CAMERA["fstop"]
    scene.camera = cam

    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    try:
        scene.cycles.device = "GPU"
    except TypeError:
        pass
    scene.render.resolution_x, scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = pct
    scene.render.image_settings.file_format = "PNG"
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    scene.view_settings.exposure = EXPOSURE
    scene.render.filepath = os.path.join(out, "thumbnail.png")
    if args.get("--save"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args["--save"]))
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
