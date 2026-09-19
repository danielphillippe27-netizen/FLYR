"""Rebuild WolfGrid's pushpin with a broad flat number plate and a status-coloured body.
Run with Blender --background --python refine_pushpin.py.
Exports preserve the ground origin, 5.15 m model height and split base/top contract.
"""
import bpy, math
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'WolfGrid/Resources/MapAssets'
ART = Path(__file__).resolve().parent
WIDTH_MULTIPLIER = 3.0  # Broader silhouette; all vertical dimensions stay unchanged.
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, metallic=0, roughness=.38):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metallic;p.inputs['Roughness'].default_value=roughness
    return m
red=material('Status cap - runtime tint',(.70,.008,.027),.05,.3)
graphite=material('Graphite needle',(.032,.039,.048),.35,.32)
white=material('Preview number only',(.97,.98,1),0,.7)

def lathe(name, profile, mat, segments=48):
    verts=[(WIDTH_MULTIPLIER*r*math.cos(i*2*math.pi/segments),WIDTH_MULTIPLIER*r*math.sin(i*2*math.pi/segments),z) for r,z in profile for i in range(segments)]
    faces=[]
    for j in range(len(profile)-1):
        for i in range(segments):
            a=j*segments+i;b=j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces += [tuple(reversed(range(segments))),tuple((len(profile)-1)*segments+i for i in range(segments))]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(mat)
    for p in mesh.polygons:p.use_smooth=len(p.vertices)==4
    return o
base=lathe('Graphite shaft',[(.008,0),(.15,.43),(.15,2.1),(.21,2.22)],graphite,32)
top=lathe('Status body and flat rim',[(.82,1.94),(.94,1.97),(1.02,2.05),(1.04,2.14),(1.00,2.24),(.82,2.38),(.60,2.56),(.56,2.76),(.62,4.13),(.71,4.29),(1.25,4.42),(1.48,4.5),(1.58,4.6),(1.62,4.72),(1.62,4.93),(1.59,5.03),(1.53,5.10),(1.46,5.12),(.08,5.12)],red,64)
collar=lathe('Graphite collar',[(.56,2.66),(.61,2.7),(.61,2.8),(.56,2.84)],graphite)
# Planar, status-coloured disk: every top-face vertex sits at z=5.15. No logo occupies it.
plate=lathe('Flat house-number plate',[(1.38,5.12),(1.42,5.135),(1.42,5.15)],red,64)

# Normalize the full assembled model to exactly 5.15 m while leaving its tip at zero.
parts=[base,top,collar,plate]
bpy.context.view_layer.update()
height=max((o.matrix_world @ Vector(c)).z for o in parts for c in o.bound_box)
for o in parts:
    o.location.z*=5.15/height;o.scale.z*=5.15/height
    bpy.context.view_layer.objects.active=o;o.select_set(True)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.select_set(False)

def export(name,objects):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/name),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)
export('PushPin.glb',parts)
export('PushPinBase.glb',[base,collar])
red.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(1,1,1,1);red.diffuse_color=(1,1,1,1)
export('PushPinTop.glb',[top,plate])
red.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.70,.008,.027,1);red.diffuse_color=(.70,.008,.027,1)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32
scene.world.color=(.18,.18,.18)
bpy.ops.object.camera_add(location=(10,-15,10));camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,2.5))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=12.0;scene.camera=camera
for loc,power,size in [((4,-6,10),1700,6),((-5,-2,6),1100,5),((2,5,7),1800,4)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size
    o.rotation_euler=(Vector((0,0,2.5))-o.location).to_track_quat('-Z','Y').to_euler()
scene.render.resolution_x=800;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.render.film_transparent=True
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'WolfGrid-PushPin.blend'))
scene.render.filepath=str(ART/'pin-refined.png');bpy.ops.render.render(write_still=True)
# Example only: never exported into the runtime models. The app supplies each home's number.
bpy.ops.object.text_add(location=(0,0,5.162));number=bpy.context.object
number.name='PREVIEW ONLY - house number supplied by app'
number.data.body='128';number.data.align_x='CENTER';number.data.align_y='CENTER'
number.data.size=1.12*WIDTH_MULTIPLIER;number.data.extrude=.002;number.data.materials.append(white)
scene.render.filepath=str(ART/'pin-number-preview.png');bpy.ops.render.render(write_still=True)
number.hide_render=True;number.hide_viewport=True
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'WolfGrid-PushPin.blend'))
print('PIN_EXPORT_COMPLETE',[(o.name,len(o.data.polygons)) for o in parts])
