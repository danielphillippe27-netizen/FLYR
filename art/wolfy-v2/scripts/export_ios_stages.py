"""Export the five Blender stage characters as RealityKit USDZ assets."""
import bpy
import hashlib
import json
import sys
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CHARACTERS = ROOT / "art/wolfy-v2/character"
RESOURCES = ROOT / "WolfGrid/Resources/Wolfy"
MANIFEST = RESOURCES / "wolfy_manifest.json"
STAGES = ("pup", "young", "street", "alpha", "legend")
STAGE_FACTORS = (1.0, 1.0, 1.0)
MAP_BONE = {
    "basic_collar":"neck", "bandana":"neck", "silver_chain":"neck", "gold_chain":"neck",
    "cap":"head", "beanie":"head", "hard_hat":"head", "glasses":"head",
    "sunglasses":"head", "headset":"head", "clipboard":"head", "tablet":"head",
    "backpack":"body", "hi_vis":"body", "storm_jacket":"body", "alpha_jacket":"body",
    "tool_belt":"body", "blue_aura":"body", "white_sneakers":"front_l_paw",
    "work_boots":"front_l_paw", "gloves":"front_r_lower",
    "street_shades":"head", "crucifix_chain":"neck", "midnight_cap":"head",
    "gold_hoops":"head", "diamond_studs":"head", "rose_bow":"head",
    "neon_glow":"body",
}
PINK_VARIANTS = {name: ("pink_chain" if name == "silver_chain" else f"pink_{name}")
                 for name in MAP_BONE}
MAP_BONE.update({variant: MAP_BONE[base] for base, variant in PINK_VARIANTS.items()})

ACCESSORY_COLORS = {
    "black":(.035,.045,.06,1), "blue":(.08,.28,.72,1),
    "gold":(.85,.55,.08,1), "silver":(.58,.64,.7,1),
    "red":(.75,.08,.1,1), "hi_vis":(.95,.55,.03,1),
    "rose":(.86,.25,.48,1), "diamond":(.82,.93,1,1),
    "pink":(.98,.30,.62,1), "pink_glow":(.98,.16,.55,1),
    "dark_lens":(.018,.026,.045,1),
    "glow_cyan":(.06,.85,1,1), "glow_white":(.65,1,1,1),
}

def accessory_material(color):
    name=f"wolfy_accessory_{color}"
    mat=bpy.data.materials.get(name)
    if mat is None:
        mat=bpy.data.materials.new(name)
        mat.diffuse_color=ACCESSORY_COLORS[color]
        mat.use_nodes=True
        shader=mat.node_tree.nodes["Principled BSDF"]
        shader.inputs["Base Color"].default_value=mat.diffuse_color
        if color.startswith("glow_") or color == "pink_glow":
            shader.inputs["Emission Color"].default_value=mat.diffuse_color
            shader.inputs["Emission Strength"].default_value=3.0
    return mat

def export_map_accessories(stage):
    """Export the Home stage's fitted wearables for the Metal session wolf."""
    map_resources = ROOT / "WolfGrid/Resources/WolfyV2"
    prototype = json.loads((map_resources / f"{stage}-manifest.json").read_text())
    bones = {name:index for index,name in enumerate(prototype["bones"])}
    data = bytearray()
    entries = {}
    for obj in sorted(bpy.context.scene.objects, key=lambda item:item.name):
        if not obj.name.startswith("wolfy_item_") or obj.type != "MESH": continue
        item = obj.name.removeprefix("wolfy_item_")
        mesh = obj.data
        mesh.calc_loop_triangles()
        matrix = obj.matrix_world
        normal_matrix = matrix.to_3x3().inverted().transposed()
        joint = float(bones[MAP_BONE[item]])
        data.extend(b"\0" * (-len(data) % 64))
        vertex_offset = len(data)
        for tri in mesh.loop_triangles:
            color=tuple(mesh.materials[tri.material_index].diffuse_color)
            for index in tri.vertices:
                vertex=mesh.vertices[index]
                position = matrix @ vertex.co
                normal = (normal_matrix @ vertex.normal).normalized()
                vertex_joint = joint
                if item in ("white_sneakers", "pink_white_sneakers", "work_boots", "pink_work_boots"):
                    # Rear toes extend slightly past Y=0; split at the gap
                    # between the front and rear footwear, not at the origin.
                    end = "front" if position.y < -.045 * STAGE_FACTORS[1] else "rear"
                    side = "l" if position.x < 0 else "r"
                    vertex_joint = float(bones[f"{end}_{side}_paw"])
                data.extend(struct.pack('<16f', *position, 1, *normal, 0, *color, vertex_joint, 0, 0, 0))
        index_offset = len(data)
        data.extend(struct.pack(f'<{len(mesh.loop_triangles)*3}I', *range(len(mesh.loop_triangles)*3)))
        entries[item] = {"vertexOffset":vertex_offset, "indexOffset":index_offset,
                         "indexCount":len(mesh.loop_triangles)*3}
    output = map_resources / f"wardrobe-{stage}-mesh.bin"
    output.write_bytes(data)
    (map_resources / f"wardrobe-{stage}-manifest.json").write_text(json.dumps({
        "version":1, "mesh":output.name, "bytes":len(data),
        "sha256":hashlib.sha256(data).hexdigest(), "items":entries,
    }, indent=2) + "\n")

def add_wearable(rig, name, bone, build):
    before = set(bpy.context.scene.objects)
    build()
    pieces = [obj for obj in bpy.context.scene.objects if obj not in before and obj.type == "MESH"]
    if not pieces:
        return
    bpy.ops.object.select_all(action="DESELECT")
    for obj in pieces:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    if len(pieces) > 1:
        bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = f"wolfy_item_{name}"
    obj.data.name = obj.name
    for vertex in obj.data.vertices:
        vertex.co.x *= STAGE_FACTORS[0]
        vertex.co.y *= STAGE_FACTORS[1]
        vertex.co.z *= STAGE_FACTORS[2]
    obj.location.x *= STAGE_FACTORS[0]
    obj.location.y *= STAGE_FACTORS[1]
    obj.location.z *= STAGE_FACTORS[2]
    # RealityKit merges skinned meshes that share this rig into the armature's
    # single ModelEntity. Hiding their named Xforms then has no visual effect.
    # Keep wardrobe pieces as independent meshes so isEnabled really controls
    # the rendered geometry. The base wolf alone remains skinned/animated.
    obj.select_set(False)

def add_pink_variants():
    """Keep the same fitted geometry and attachment bone for each colorway."""
    pink = accessory_material("pink")
    glow = accessory_material("pink_glow")
    for base, variant in PINK_VARIANTS.items():
        if variant == "pink_chain":
            continue
        original = bpy.data.objects.get(f"wolfy_item_{base}")
        if original is None:
            raise RuntimeError(f"Missing accessory for {variant}: {base}")
        copy = original.copy()
        copy.data = original.data.copy()
        copy.name = f"wolfy_item_{variant}"
        copy.data.name = copy.name
        bpy.context.scene.collection.objects.link(copy)
        copy.data.materials.clear()
        copy.data.materials.append(glow if base in ("blue_aura", "neon_glow") else pink)
        for polygon in copy.data.polygons:
            polygon.material_index = 0

def sphere(name, loc, scale, color):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(accessory_material(color))
    return obj

def torus(name, loc, major, minor, color):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=32, minor_segments=8, location=loc, rotation=(math.pi/2,0,0))
    obj=bpy.context.object; obj.name=name
    obj.data.materials.append(accessory_material(color))
    return obj

def box(name, loc, scale, color):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj=bpy.context.object;obj.name=name;obj.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(accessory_material(color))
    return obj

def bar(name,start,end,radius,color):
    from mathutils import Vector
    a,b=Vector(start),Vector(end)
    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=radius,depth=(b-a).length,location=(a+b)/2)
    obj=bpy.context.object;obj.name=name
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    obj.data.materials.append(accessory_material(color))
    return obj

def four_paw_footwear(name, scale, color):
    for side, x in (("left", -.18), ("right", .18)):
        for end, y in (("front", -.17), ("rear", .235)):
            sphere(f"{name} {end} {side}",(x,y-.08,.095),scale,color)

def render_accessory_thumbnails():
    scene=bpy.context.scene
    depsgraph=bpy.context.evaluated_depsgraph_get()
    scene.render.engine='CYCLES';scene.cycles.samples=8
    scene.render.resolution_x=384;scene.render.resolution_y=384;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
    scene.render.film_transparent=True
    scene.render.image_settings.color_depth='8'
    original={obj:obj.hide_render for obj in scene.objects}
    camera_data=bpy.data.cameras.new('WolfyAccessoryCamera')
    camera=bpy.data.objects.new('WolfyAccessoryCamera',camera_data);scene.collection.objects.link(camera)
    camera.data.type='ORTHO';scene.camera=camera
    lights=[]
    for name,loc,power,size in [('AccessoryKey',(2,-3,3),500,3),('AccessoryFill',(-2,-2,1.5),250,2)]:
        bpy.ops.object.light_add(type='AREA',location=loc)
        light=bpy.context.object;light.name=name;light.data.energy=power;light.data.shape='DISK';light.data.size=size
        lights.append(light)
    output=RESOURCES
    for accessory in [obj for obj in scene.objects if obj.name.startswith('wolfy_item_')]:
        for obj in scene.objects:
            if obj.type=='MESH':obj.hide_render=(obj is not accessory)
        depsgraph.update()
        corners=[accessory.matrix_world @ __import__('mathutils').Vector(corner) for corner in accessory.bound_box]
        lo=tuple(min(v[i] for v in corners) for i in range(3));hi=tuple(max(v[i] for v in corners) for i in range(3))
        center=tuple((lo[i]+hi[i])/2 for i in range(3));span=max(hi[0]-lo[0],hi[2]-lo[2],(hi[1]-lo[1])*.8,.22)
        footwear = accessory.name.removeprefix("wolfy_item_").removeprefix("pink_") in ("white_sneakers", "work_boots")
        camera.location=(center[0]+span*.9 if footwear else center[0],
                         center[1]-max(.8,span*3.2),
                         center[2]+span*1.2 if footwear else center[2]+span*.13)
        camera.rotation_euler=(__import__('mathutils').Vector(center)-camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.ortho_scale=span*(1.7 if footwear else 1.55)
        for light in lights:light.rotation_euler=(__import__('mathutils').Vector(center)-light.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(output/f"accessory_{accessory.name.removeprefix('wolfy_item_')}.png")
        bpy.ops.render.render(write_still=True)
    for obj,hidden in original.items():obj.hide_render=hidden
    scene.camera=None
    bpy.data.objects.remove(camera,do_unlink=True)
    for light in lights:bpy.data.objects.remove(light,do_unlink=True)

RESOURCES.mkdir(parents=True, exist_ok=True)
manifest = json.loads(MANIFEST.read_text())
manifest.setdefault("growthStages", {})
manifest.setdefault("files", {})
existing = {item["id"]: item for item in manifest["items"]}
PINK_NAMES = {
    "bandana":"Pink Bandana", "beanie":"Pink Beanie",
    "gold_chain":"Pink Heavy Chain", "glasses":"Pink Glasses",
    "sunglasses":"Pink Sunglasses", "hi_vis":"Pink Vest",
    "blue_aura":"Pink Aura", "white_sneakers":"Pink Sneakers",
    "gold_hoops":"Pink Hoop Earrings", "diamond_studs":"Pink Stud Earrings",
}
for base, variant in PINK_VARIANTS.items():
    source = existing[base]
    item = source.copy()
    item.update(id=variant,
                name="Pink Chain" if variant == "pink_chain" else PINK_NAMES.get(base, f"Pink {source['name']}"),
                description="Free pink cosmetic accessory",
                price=0, requiredLevel=1, asset=f"embedded:{variant}",
                thumbnail=f"accessory_{variant}.png",
                sortOrder=existing[variant]["sortOrder"] if variant in existing else len(manifest["items"]))
    if variant in existing:
        manifest["items"] = [item if existing_item["id"] == variant else existing_item for existing_item in manifest["items"]]
    else:
        manifest["items"].append(item)

for stage in (stage for stage in STAGES if "--stage=" not in " ".join(sys.argv) or f"--stage={stage}" in sys.argv):
    source = CHARACTERS / stage / f"{stage}.blend"
    target_name = f"wolfy_stage_{stage}.usdz"
    target = RESOURCES / target_name
    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig = bpy.data.objects.get("Wolfy")
    if rig is None:
        raise RuntimeError(f"Missing Wolfy armature in {source}")
    reference = bpy.data.objects.get("Wolfy continuous skin")
    if reference is None:
        raise RuntimeError(f"Missing character mesh in {source}")
    nose = bpy.data.objects.get("Rounded nose")
    if nose is not None and nose.type == 'MESH' and nose.data.materials:
        nose_material = nose.data.materials[0].copy()
        nose_material.name = "Wolfy_nose"
        nose_material.diffuse_color = (.065,.078,.095,1)
        if nose_material.use_nodes:
            nose_material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value=nose_material.diffuse_color
        nose.data.materials[0] = nose_material
    STAGE_FACTORS = tuple(reference.dimensions[i] / (0.65, 1.72, 1.01)[i] for i in range(3))
    # Compact, skinned quadruped wearables. Their local placement is stage-fit
    # and each accessory follows the same head/neck/body bones as the wolf.
    add_wearable(rig,"basic_collar","neck",lambda: torus("Collar",(0,-.30,.70),.205,.035,"blue"))
    add_wearable(rig,"bandana","neck",lambda: sphere("Bandana",(0,-.38,.61),(.19,.07,.13),"red"))
    add_wearable(rig,"silver_chain","neck",lambda: torus("Silver chain",(0,-.35,.66),.215,.018,"silver"))
    add_wearable(rig,"gold_chain","neck",lambda: torus("Gold chain",(0,-.35,.66),.215,.026,"gold"))
    add_wearable(rig,"cap","head",lambda: (sphere("Cap crown",(0,-.49,1.015),(.19,.17,.085),"gold"), sphere("Cap brim",(0,-.64,.985),(.22,.10,.025),"gold")))
    add_wearable(rig,"beanie","head",lambda: sphere("Beanie",(0,-.48,1.005),(.20,.18,.10),"black"))
    add_wearable(rig,"hard_hat","head",lambda: (sphere("Hard hat crown",(0,-.48,1.025),(.21,.18,.095),"hi_vis"), sphere("Hard hat brim",(0,-.60,.98),(.25,.17,.025),"hi_vis")))
    def glasses(color):
        for x in (-.13,.13): torus("Frame",(x,-.64,.87),.075,.012,color)
        sphere("Bridge",(0,-.65,.87),(.055,.02,.018),color)
    add_wearable(rig,"glasses","head",lambda: glasses("silver"))
    add_wearable(rig,"sunglasses","head",lambda: glasses("black"))
    add_wearable(rig,"backpack","body",lambda: sphere("Backpack",(0,.30,.72),(.22,.16,.22),"blue"))
    add_wearable(rig,"white_sneakers","front_l_paw",lambda: four_paw_footwear("Sneaker",(.12,.16,.075),"silver"))
    add_wearable(rig,"work_boots","front_l_paw",lambda: four_paw_footwear("Boot",(.13,.17,.09),"black"))
    add_wearable(rig,"gloves","front_r_paw",lambda: sphere("Glove",(.16,-.27,.11),(.13,.15,.09),"black"))
    add_wearable(rig,"hi_vis","body",lambda: sphere("Safety vest",(0,-.01,.60),(.245,.31,.17),"hi_vis"))
    add_wearable(rig,"storm_jacket","body",lambda: sphere("Storm jacket",(0,.02,.60),(.25,.34,.20),"blue"))
    add_wearable(rig,"alpha_jacket","body",lambda: sphere("Alpha jacket",(0,.02,.62),(.27,.35,.21),"red"))
    add_wearable(rig,"tool_belt","body",lambda: torus("Tool belt",(0,.02,.48),.24,.035,"black"))
    add_wearable(rig,"clipboard","head",lambda: box("Clipboard",(.28,-.48,.66),(.08,.20,.27),"blue"))
    add_wearable(rig,"tablet","head",lambda: box("Tablet",(.28,-.48,.66),(.085,.20,.27),"black"))
    add_wearable(rig,"headset","head",lambda: (sphere("Headset cup L",(-.22,-.43,.88),(.06,.07,.10),"black"),sphere("Headset cup R",(.22,-.43,.88),(.06,.07,.10),"black")))
    add_wearable(rig,"blue_aura","body",lambda: torus("Blue aura",(0,0,.72),.40,.025,"blue"))
    def neon_glow():
        torus("Outer cyan glow",(0,.02,.65),.51,.022,"glow_cyan")
        torus("Inner white glow",(0,-.015,.65),.47,.010,"glow_white")
        bpy.ops.mesh.primitive_torus_add(major_radius=.43,minor_radius=.021,major_segments=40,
                                         minor_segments=8,location=(0,0,.12))
        bpy.context.object.name="Ground glow"
        bpy.context.object.data.materials.append(accessory_material("glow_cyan"))
        for x,z in ((-.42,.82),(.42,.82),(-.30,1.06),(.30,1.06)):
            sphere("Glow spark",(x,-.12,z),(.027,.027,.027),"glow_white")
    add_wearable(rig,"neon_glow","body",neon_glow)
    def street_shades():
        for x in (-.13,.13):
            box("Smoked angular lens",(x,-.70,.81),(.18,.018,.13),"dark_lens")
            for z in (.74,.88):
                bar("Gold lens edge",(x-.095,-.71,z),(x+.095,-.71,z),.007,"gold")
            for edge in (x-.095,x+.095):
                bar("Gold lens side",(edge,-.71,.74),(edge,-.71,.88),.007,"gold")
        bar("Gold bridge",(-.04,-.716,.83),(.04,-.716,.83),.010,"gold")
    add_wearable(rig,"street_shades","head",street_shades)
    def crucifix_chain():
        # Share the Heavy Gold Chain's collar path; only its pendant extends
        # below the lowest link, against the front of the chest.
        torus("Jesus chain collar",(0,-.35,.66),.215,.026,"gold")
        bar("Pendant bail",(0,-.41,.46),(0,-.41,.42),.014,"gold")
        bar("Hanging cross",(0,-.41,.42),(0,-.41,.29),.020,"gold")
        bar("Cross arms",(-.065,-.41,.38),(.065,-.41,.38),.016,"gold")
        sphere("Jesus head",(0,-.435,.39),(.018,.012,.021),"silver")
        bar("Jesus torso",(0,-.435,.37),(0,-.435,.32),.009,"silver")
        bar("Jesus arms",(-.043,-.435,.365),(.043,-.435,.365),.008,"silver")
    add_wearable(rig,"crucifix_chain","neck",crucifix_chain)
    add_wearable(rig,"midnight_cap","head",lambda: (
        sphere("Midnight cap crown",(0,-.49,1.02),(.20,.18,.095),"black"),
        sphere("Midnight cap bill",(0,-.67,.98),(.235,.11,.024),"black"),
        sphere("Gold cap emblem",(0,-.657,1.025),(.042,.014,.035),"gold")))
    def gold_hoops():
        for x in (-.22,.22):torus("Gold hoop",(x,-.40,1.02),.062,.012,"gold")
    add_wearable(rig,"gold_hoops","head",gold_hoops)
    def diamond_studs():
        for x in (-.22,.22):
            sphere("Silver setting",(x,-.43,1.02),(.040,.020,.040),"silver")
            sphere("Diamond",(x,-.452,1.02),(.027,.012,.027),"diamond")
    add_wearable(rig,"diamond_studs","head",diamond_studs)
    add_wearable(rig,"rose_bow","head",lambda: (
        sphere("Left bow loop",(-.09,-.48,1.13),(.09,.035,.057),"rose"),
        sphere("Right bow loop",(.09,-.48,1.13),(.09,.035,.057),"rose"),
        sphere("Bow knot",(0,-.495,1.13),(.031,.036,.034),"gold")))
    add_pink_variants()
    def pink_chain():
        # Individual oval links and a small heart make this read as jewelry,
        # rather than a recolored collar at customizer size.
        for index in range(24):
            angle = math.tau * index / 24
            sphere("Pink chain link",(.215*math.cos(angle),-.35,.66+.215*math.sin(angle)),
                   (.024,.016,.018),"pink")
        sphere("Heart left",(-.024,-.383,.415),(.035,.018,.031),"pink")
        sphere("Heart right",(.024,-.383,.415),(.035,.018,.031),"pink")
        heart = box("Heart point",(0,-.383,.39),(.061,.025,.061),"pink")
        heart.rotation_euler[1] = math.pi/4
    add_wearable(rig,"pink_chain","neck",pink_chain)
    export_map_accessories(stage)
    if "--map-only" in sys.argv:
        print(f"Exported map wardrobe: {stage}")
        continue
    if stage == "pup" and "--skip-thumbnails" not in sys.argv:
        render_accessory_thumbnails()
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = 48
    bpy.ops.wm.usd_export(
        filepath=str(target),
        selected_objects_only=False,
        export_animation=True,
        export_meshes=True,
        export_materials=True,
        export_armatures=True,
        only_deform_bones=True,
        export_lights=False,
        export_cameras=False,
        convert_orientation=True,
        generate_preview_surface=True,
    )
    data = target.read_bytes()
    manifest["growthStages"][stage] = target_name
    manifest["files"][target_name] = {
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }
    print(f"Exported {stage}: {len(data):,} bytes")

MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
