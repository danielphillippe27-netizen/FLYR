"""Fresh, unrigged quadruped concept. Never reads or exports runtime assets."""
import bpy, math, os
from pathlib import Path
from mathutils import Vector

OUT = Path(__file__).resolve().parent
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in list(bpy.data.materials): bpy.data.materials.remove(block)

def mat(name, color, rough=.6):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=rough
    return m
dark=mat('Charcoal eyelids and mouth',(.035,.045,.055))
nosemat=mat('Soft graphite nose',(.045,.055,.064),.32)
ivory=mat('Warm silver fur',(.68,.71,.72))
inner=mat('Muted warm inner ears',(.29,.22,.22))
iris=mat('Natural amber eyes',(.42,.23,.065),.25)
pupil=mat('Deep pupils',(.008,.013,.018),.2)
white=mat('Eye catchlight',(.95,.98,1),.2)
parts=[]
def ell(name, pos, scale, material=None, organic=False):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40,ring_count=24,location=pos)
    o=bpy.context.object; o.name=name; o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for p in o.data.polygons:p.use_smooth=True
    if material:o.data.materials.append(material)
    if organic:parts.append(o)
    return o
def link(name,a,b,r1,r2=None):
    a,b=Vector(a),Vector(b); d=b-a
    o=ell(name,(a+b)/2,(r1,r2 or r1,d.length/2+r1*.5),organic=True)
    o.rotation_mode='QUATERNION';o.rotation_quaternion=d.to_track_quat('Z','Y')
    return o

# Entire silhouette is authored here as canine anatomy, with no imported mesh.
ell('Long ribcage',(-.12,0,1.47),(.98,.40,.49),organic=True)
ell('Tucked abdomen',(.58,0,1.40),(.58,.31,.34),organic=True)
ell('Canine pelvis',(.91,0,1.49),(.44,.37,.43),organic=True)
ell('Withers',(-.68,0,1.65),(.46,.40,.48),organic=True)
link('Sloping wolf neck',(-.71,0,1.55),(-1.17,0,2.08),.37,.36)
ell('Ruff',(-.94,0,1.91),(.40,.43,.49),organic=True)
ell('Cranium',(-1.32,0,2.23),(.48,.40,.45),organic=True)
ell('Cheek L',(-1.27,-.28,2.08),(.33,.22,.29),organic=True)
ell('Cheek R',(-1.27,.28,2.08),(.33,.22,.29),organic=True)
ell('Tapered muzzle bridge',(-1.70,0,2.13),(.43,.245,.205),organic=True)
ell('Muzzle tip',(-1.96,0,2.08),(.22,.215,.15),organic=True)
ell('Lower jaw',(-1.70,0,1.98),(.37,.21,.105),organic=True)

for side in [-1,1]:
    y=side*.285
    # Forelegs descend beneath the withers, with narrow wrists and broad paws.
    link('Foreleg upper',(-.69,y,1.52),(-.65,y,.88),.155,.17)
    link('Foreleg cannon',(-.65,y,.96),(-.76,y,.30),.093,.095)
    ell('Front wrist',(-.76,y,.29),(.10,.105,.14),organic=True)
    link('Front pastern',(-.76,y,.30),(-.82,y,.15),.10)
    ell('Front paw',(-.87,y,.135),(.22,.145,.135),organic=True)
    # Real canine stifle points forward; hock angles back, then metatarsus down.
    ell('Hind haunch',(.93,y,1.27),(.32,.22,.43),organic=True)
    link('Hind thigh',(.95,y,1.35),(.66,y,.87),.20,.175)
    link('Hind shin',(.66,y,.89),(1.14,y,.47),.115,.12)
    ell('Hock',(1.14,y,.46),(.115,.10,.125),organic=True)
    link('Hind pastern',(1.14,y,.46),(1.04,y,.16),.073,.085)
    ell('Rear paw',(.98,y,.125),(.20,.135,.125),organic=True)

# A single swept tail volume avoids a chain of spherical lumps.
tail_path=[(1.13,.04,1.63,.13),(1.40,.065,1.55,.21),(1.66,.09,1.38,.26),(1.88,.09,1.15,.26),(2.03,.07,.91,.215),(2.06,.05,.71,.14),(1.99,.03,.54,.018)]
verts=[]; faces=[]; ring=20
for i,(x,y,z,r) in enumerate(tail_path):
    prev=Vector(tail_path[max(0,i-1)][:3]); nxt=Vector(tail_path[min(len(tail_path)-1,i+1)][:3]); tangent=(nxt-prev).normalized()
    u=Vector((0,1,0)); v=tangent.cross(u).normalized()
    for j in range(ring):
        t=2*math.pi*j/ring; pt=Vector((x,y,z))+r*(math.cos(t)*u+math.sin(t)*v);verts.append(tuple(pt))
for i in range(len(tail_path)-1):
    for j in range(ring):faces.append((i*ring+j,i*ring+(j+1)%ring,(i+1)*ring+(j+1)%ring,(i+1)*ring+j))
faces.extend([tuple(reversed(range(ring))),tuple((len(tail_path)-1)*ring+j for j in range(ring))])
mesh=bpy.data.meshes.new('Swept fluffy tail');mesh.from_pydata(verts,[],faces);mesh.update()
tail=bpy.data.objects.new('Swept fluffy tail',mesh);bpy.context.collection.objects.link(tail);parts.append(tail)

def ear(name,side, inset=False):
    # Rounded triangular volume, broad root and pointed tip, not a cone.
    y=side*.30
    if not inset:
        levels=[(2.46,-1.22,y,.235,.15),(2.67,-1.18,y+side*.035,.18,.11),(2.94,-1.10,y+side*.07,.073,.047),(3.035,-1.065,y+side*.08,.008,.008)]
    else:
        levels=[(2.61,-1.392,y,.013,.092),(2.76,-1.32,y+side*.04,.012,.069),(2.96,-1.145,y+side*.073,.005,.008)]
    verts=[];faces=[]; n=12
    for z,x,cy,rx,ry in levels:
        for j in range(n):
            t=j*2*math.pi/n;verts.append((x+rx*math.cos(t),cy+ry*math.sin(t),z))
    for k in range(len(levels)-1):
        for j in range(n):faces.append((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j))
    faces.extend([tuple(reversed(range(n))),tuple((len(levels)-1)*n+j for j in range(n))])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o)
    if inset:o.data.materials.append(inner)
    else:parts.append(o)
    for p in mesh.polygons:p.use_smooth=True
    return o
for side in [-1,1]:ear('Pointed wolf ear',side)

# Small swept cheek tufts give the ruff a wolf silhouette without separate plates.
for side in [-1,1]:
    for base,tip,radius in [((-1.17,side*.32,2.10),(-.88,side*.49,2.01),.16),((-1.11,side*.31,1.98),(-.87,side*.44,1.84),.14)]:
        a,b=Vector(base),Vector(tip); d=b-a
        bpy.ops.mesh.primitive_cone_add(vertices=24,radius1=radius,radius2=.01,depth=d.length,location=(a+b)/2)
        o=bpy.context.object;o.name='Swept cheek fur';o.rotation_mode='QUATERNION';o.rotation_quaternion=d.to_track_quat('Z','Y');parts.append(o)

# Unite the complete sculpt so neck, legs and body have continuous transitions.
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join()
body=bpy.context.object;body.name='Wolfy • fresh quadruped sculpt'
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
r=body.modifiers.new('Continuous organic surface','REMESH');r.mode='VOXEL';r.voxel_size=.022;r.use_smooth_shade=True
bpy.ops.object.modifier_apply(modifier=r.name)
s=body.modifiers.new('Relax sculpt transitions','SMOOTH');s.factor=1.25;s.iterations=6
bpy.ops.object.modifier_apply(modifier=s.name)
sub=body.modifiers.new('Silhouette polish','SUBSURF');sub.levels=1

# A packed continuous coat lookup keeps markings smooth in the preview render.
# Generated X/Z coordinates need no external texture files or production UVs.
body.data.materials.clear()
def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def blend(a,b,t):return tuple(a[i]*(1-t)+b[i]*t for i in range(3))
def coat(x,z):
    color=(.12,.16,.21)
    color=blend(color,(.006,.011,.020),smooth(1.5,1.92,z)*smooth(-1.35,-.75,x))
    color=blend(color,(.018,.03,.05),smooth(2.18,2.49,z)*(1-smooth(-1.0,-.8,x)))
    muzzle=(1-smooth(-1.80,-1.43,x))*(1-smooth(2.14,2.30,z))
    paws=1-smooth(.19,.34,z)
    chest=(1-smooth(-1.12,-.8,x))*(1-smooth(1.72,1.95,z))
    underside=(1-smooth(1.17,1.37,z))*smooth(-.7,-.3,x)*(1-smooth(.6,.9,x))
    return blend(color,(.66,.69,.71),max(muzzle,paws,chest,underside*.7))
xmin=min(v.co.x for v in body.data.vertices);xmax=max(v.co.x for v in body.data.vertices)
zmin=min(v.co.z for v in body.data.vertices);zmax=max(v.co.z for v in body.data.vertices)
size=512;pixels=[]
for iz in range(size):
    for ix in range(size):pixels.extend((*coat(xmin+(xmax-xmin)*ix/(size-1),zmin+(zmax-zmin)*iz/(size-1)),1))
texture=bpy.data.images.new('Wolfy continuous coat',width=size,height=size,float_buffer=True)
texture.colorspace_settings.name='Non-Color';texture.pixels.foreach_set(pixels);texture.pack()
fur=mat('Continuous silver charcoal coat',(.12,.16,.21),.75);body.data.materials.append(fur)
for face in body.data.polygons:face.material_index=0
ns=fur.node_tree.nodes;ls=fur.node_tree.links;bs=ns.get('Principled BSDF')
coord=ns.new('ShaderNodeTexCoord');sep=ns.new('ShaderNodeSeparateXYZ');combine=ns.new('ShaderNodeCombineXYZ');tex=ns.new('ShaderNodeTexImage');tex.image=texture;tex.interpolation='Linear';tex.extension='EXTEND'
ls.new(coord.outputs['Generated'],sep.inputs[0]);ls.new(sep.outputs['X'],combine.inputs['X']);ls.new(sep.outputs['Z'],combine.inputs['Y']);ls.new(combine.outputs[0],tex.inputs['Vector']);ls.new(tex.outputs['Color'],bs.inputs['Base Color'])
noise=ns.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=145
bump=ns.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.08;bump.inputs['Distance'].default_value=.012
ls.new(noise.outputs['Fac'],bump.inputs['Height']);ls.new(bump.outputs['Normal'],bs.inputs['Normal'])
body.data.update()
for side in [-1,1]:ear('Velvet inner ear',side,True)

def oriented(name,center,scale,material,normal):
    o=ell(name,center,scale,material);o.rotation_mode='QUATERNION';o.rotation_quaternion=Vector(normal).to_track_quat('Z','Y');return o
for side in [-1,1]:
    center=Vector((-1.58,side*.321,2.29));normal=Vector((-.69,side*.72,.045)).normalized()
    oriented('Soft eye surround',center,(.140,.114,.034),dark,normal)
    oriented('Amber iris',center+normal*.030,(.100,.095,.022),iris,normal)
    oriented('Round pupil',center+normal*.052,(.043,.060,.012),pupil,normal)
    ell('Eye glint',center+normal*.067+Vector((-.017,-.014,.033)),(.019,.019,.019),white)
    # Brows are gentle fur volumes, not human eyebrows.


ell('Canine nose',(-2.115,0,2.105),(.115,.177,.105),nosemat)
for side in [-1,1]:ell('Nostril',(-2.207,side*.084,2.112),(.014,.039,.022),dark)
def curve(name, points, radius, material):
    cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.bevel_depth=radius;cu.bevel_resolution=3
    sp=cu.splines.new('BEZIER');sp.bezier_points.add(len(points)-1)
    for b,p in zip(sp.bezier_points,points):b.co=p;b.handle_left_type='AUTO';b.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(o);cu.materials.append(material)
for side in [-1,1]:
    curve('Quiet canine mouth',[(-2.07,side*.13,1.99),(-1.90,side*.20,1.97),(-1.69,side*.218,1.985),(-1.55,side*.22,2.03)],.010,dark)
    for x,y in [(-.87,side*.285),(.98,side*.285)]:
        for dy in [-.045,.045]:curve('Paw toe crease',[(x-.175,y+dy,.105),(x-.17,y+dy,.155),(x-.12,y+dy,.20)],.0045,nosemat)

# Neutral ground is part of the render environment, never a character pedestal.
floor=mat('Warm neutral studio',(.28,.30,.31),.82)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,.026));bpy.context.object.name='Studio floor';bpy.context.object.data.materials.append(floor)
world=bpy.context.scene.world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.37,.42,.48,1);world.node_tree.nodes['Background'].inputs[1].default_value=.45
def area(name,location,power,size,color):
    bpy.ops.object.light_add(type='AREA',location=location);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.data.color=color;o.rotation_euler=(Vector((0,0,1.3))-o.location).to_track_quat('-Z','Y').to_euler()
area('Large warm key',(-3,-4,7),950,5,(1,.91,.81))
area('Cool fill',(-1,4,4.5),700,4,(.78,.87,1))
area('Tail rim',(4,1,5),1100,3,(1,.95,.86))
bpy.ops.object.camera_add();camera=bpy.context.object;camera.name='Design review camera';camera.data.type='ORTHO';bpy.context.scene.camera=camera
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=64;scene.cycles.use_denoising=True
scene.render.resolution_x=2048;scene.render.resolution_y=2048;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
scene['design_stage']='UNRIGGED QUADRUPED DESIGN REVIEW — no runtime export'
scene['source']='Created from empty scene; no humanoid assets imported'
views={'front':((-7,0,3.0),(-.25,0,1.46),4.05),'side':((0,-8,2.7),(0,0,1.48),5.1),'three-quarter':((-6,-8,4.1),(-.05,0,1.40),4.95)}
def setview(name):
    loc,target,scale=views[name];camera.location=loc;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale
setview('three-quarter')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Wolfy-Quadruped-Review.blend'))
for name in views:
    setview(name);scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
setview('three-quarter');scene.render.resolution_x=390;scene.render.resolution_y=390;scene.render.filepath=str(OUT/'iphone-size.png');bpy.ops.render.render(write_still=True)
print('QUADRUPED_REVIEW_COMPLETE',flush=True)
