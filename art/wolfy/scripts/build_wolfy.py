"""Original WolfGrid geometry. Blender 5: --background --python build_wolfy.py.
Use -- --quick to omit movie; -- --assets-only to skip renders.
"""
import bpy, math, json, hashlib, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
ART=ROOT/'art/wolfy'; OUT=ROOT/'WolfGrid/Resources/Wolfy'
for d in [OUT,ART/'exports',ART/'renders',ART/'blender',ART/'manifests']: d.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=24
scene.render.resolution_x=768; scene.render.resolution_y=768; scene.render.resolution_percentage=100
scene.render.fps=24; scene.world.color=(.18,.18,.18)
M={}
def mat(name,color,metal=0):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=.65; p.inputs['Metallic'].default_value=metal; M[name]=m; return m
for n,c in {'fur':(.24,.28,.33),'light':(.79,.83,.86),'white':(.94,.96,.98),'black':(.015,.023,.035),'hood':(.035,.045,.065),'blue':(.025,.42,.93),'nose':(.035,.042,.049),'sole':(.61,.67,.72),'cargo':(.10,.14,.18),'pink':(.45,.28,.32),'hiVis':(.83,.93,.04),'gold':(.72,.43,.09),'silver':(.52,.59,.68)}.items(): mat(n,c,.65 if n in ['gold','silver'] else 0)
# All forms share the same armature and deterministic named joints.
rigdata=bpy.data.armatures.new('WolfySkeleton'); rig=bpy.data.objects.new('WolfyRig',rigdata); scene.collection.objects.link(rig); bpy.context.view_layer.objects.active=rig; rig.select_set(True); bpy.ops.object.mode_set(mode='EDIT')
bones={}
def bone(n,head,tail,parent=None):
 b=rigdata.edit_bones.new('wolfy_'+n); b.head=head; b.tail=tail
 if parent:b.parent=rigdata.edit_bones['wolfy_'+parent]
 bones[n]='wolfy_'+n
bone('root',(0,0,0),(0,0,.12)); bone('pelvis',(0,0,.55),(0,0,.72),'root'); bone('spine_01',(0,0,.72),(0,0,.91),'pelvis'); bone('spine_02',(0,0,.91),(0,0,1.07),'spine_01'); bone('chest',(0,0,1.07),(0,0,1.18),'spine_02'); bone('neck',(0,0,1.18),(0,0,1.28),'chest'); bone('head',(0,0,1.28),(0,0,1.87),'neck'); bone('jaw',(0,-.21,1.44),(0,-.36,1.4),'head')
for side,sgn in [('l',-1),('r',1)]:
 bone('ear_'+side,(sgn*.25,0,1.85),(sgn*.34,0,2.14),'head'); bone('eye_'+side,(sgn*.155,-.295,1.7),(sgn*.155,-.30,1.75),'head'); bone('brow_'+side,(sgn*.155,-.28,1.84),(sgn*.155,-.29,1.89),'head')
 bone('shoulder_'+side,(sgn*.18,0,1.13),(sgn*.29,0,1.10),'chest'); bone('upperarm_'+side,(sgn*.29,0,1.10),(sgn*.37,0,.91),'shoulder_'+side); bone('forearm_'+side,(sgn*.37,0,.91),(sgn*.40,-.03,.72),'upperarm_'+side); bone('hand_'+side,(sgn*.40,-.03,.72),(sgn*.41,-.07,.61),'forearm_'+side)
 bone('thigh_'+side,(sgn*.14,0,.61),(sgn*.16,0,.39),'pelvis'); bone('shin_'+side,(sgn*.16,0,.39),(sgn*.16,0,.18),'thigh_'+side); bone('foot_'+side,(sgn*.16,0,.18),(sgn*.16,-.19,.10),'shin_'+side)
bone('tail_01',(0,.15,.65),(0,.35,.61),'pelvis');bone('tail_02',(0,.35,.61),(0,.53,.75),'tail_01');bone('tail_03',(0,.53,.75),(0,.57,.97),'tail_02')
bpy.ops.object.mode_set(mode='OBJECT');rig.select_set(False)
base=[]
def bind(o,joint,collection=base):
 g=o.vertex_groups.new(name=bones[joint]);g.add(list(range(len(o.data.vertices))),1,'REPLACE');mod=o.modifiers.new('WolfySkin','ARMATURE');mod.object=rig;o.parent=rig;collection.append(o);return o
def finish(o,name,material):
 o.name=name;o.data.materials.append(M[material]);
 for p in o.data.polygons:p.use_smooth=True
 return o
def orb(name,loc,scale,material,joint=None,collection=base):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=loc);o=bpy.context.object;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);finish(o,name,material)
 if joint:bind(o,joint,collection)
 return o
def box(name,loc,scale,material,joint=None,collection=base,bevel=.035):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);m=o.modifiers.new('SoftEdges','BEVEL');m.width=bevel;m.segments=3;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=m.name);finish(o,name,material)
 if joint:bind(o,joint,collection)
 return o
def cone(name,loc,scale,material,joint,collection=base):
 bpy.ops.mesh.primitive_cone_add(vertices=16,radius1=1,radius2=.09,depth=2,location=loc);o=bpy.context.object;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);finish(o,name,material);bind(o,joint,collection);return o
orb('HoodieBody',(0,0,.92),(.29,.205,.34),'hood','chest');orb('Hood',(0,.045,1.19),(.29,.20,.18),'hood','chest');box('HoodieHem',(0,-.015,.66),(.49,.33,.075),'black','pelvis');box('KangarooPocket',(0,-.20,.79),(.30,.04,.115),'black','chest')
# Original geometric W chest mark, raised just above the cloth.
for i,(x,angle) in enumerate([(-.075,-.32),(-.025,.32),(.025,-.32),(.075,.32)]):
 o=box('WolfGrid_W_'+str(i),(x,-.206,1.035),(.024,.012,.115),'white','chest',bevel=.005);o.rotation_euler.y=angle
for x in [-.07,.07]:box('Drawstring',(x,-.208,1.14),(.012,.016,.11),'sole','chest',bevel=.004)
orb('Head',(0,0,1.63),(.37,.29,.40),'fur','head');orb('Muzzle',(0,-.263,1.48),(.255,.17,.15),'light','head');orb('LowerJaw',(0,-.255,1.405),(.17,.11,.057),'white','jaw');orb('Nose',(0,-.424,1.52),(.080,.048,.055),'nose','head');box('Smile',(0,-.365,1.405),(.12,.012,.016),'nose','jaw',bevel=.008)
for side,x in [('l',-.16),('r',.16)]:
 orb('EyeWhite_'+side,(x,-.258,1.72),(.116,.062,.13),'white','eye_'+side);orb('Iris_'+side,(x,-.311,1.719),(.066,.026,.079),'blue','eye_'+side);orb('Pupil_'+side,(x,-.333,1.719),(.031,.010,.049),'black','eye_'+side);orb('EyeShine_'+side,(x-.018,-.344,1.751),(.018,.009,.020),'white','eye_'+side)
 o=orb('Brow_'+side,(x,-.282,1.85),(.112,.038,.038),'fur','brow_'+side);o.rotation_euler.y=(-.15 if x<0 else .15)
 o=cone('Ear_'+side,(x*1.8,.015,1.97),(.13,.09,.24),'fur','ear_'+side);o.rotation_euler.y=(-.20 if x<0 else .20)
 o=cone('InnerEar_'+side,(x*1.82,-.066,1.985),(.085,.020,.16),'light','ear_'+side);o.rotation_euler.y=(-.20 if x<0 else .20)
 orb('Cheek_'+side,(x*1.70,-.14,1.50),(.16,.12,.16),'light','head')
 for i in range(3):
  o=cone('CheekTuft_'+side+str(i),(x*2.02,-.09,1.45+i*.07),(.065,.07,.12),'light','head');o.rotation_euler.y=(-1.0 if x<0 else 1.0)
 s=-1 if x<0 else 1
 orb('Sleeve_'+side,(s*.31,0,1.025),(.125,.15,.21),'hood','upperarm_'+side);orb('ForeSleeve_'+side,(s*.39,-.02,.83),(.095,.12,.14),'hood','forearm_'+side);box('Cuff_'+side,(s*.40,-.02,.73),(.18,.19,.055),'black','forearm_'+side)
 orb('Paw_'+side,(s*.41,-.035,.66),(.105,.115,.115),'fur','hand_'+side)
 for i in range(3):orb('Finger_'+side+str(i),(s*.41+(i-1)*.043,-.115,.64),(.026,.035,.04),'light','hand_'+side)
 orb('CargoLeg_'+side,(s*.15,0,.48),(.13,.14,.23),'cargo','thigh_'+side);box('CargoPocket_'+side,(s*.25,-.005,.48),(.07,.19,.16),'cargo','thigh_'+side);box('PocketFlap_'+side,(s*.285,-.01,.52),(.014,.18,.04),'sole','thigh_'+side,bevel=.006)
 orb('TrouserCuff_'+side,(s*.16,0,.27),(.115,.13,.12),'cargo','shin_'+side);box('Shoe_'+side,(s*.16,-.065,.135),(.245,.34,.16),'black','foot_'+side);box('Sole_'+side,(s*.16,-.065,.055),(.255,.35,.06),'white','foot_'+side)
 for i in range(3):box('Lace_'+side+str(i),(s*.16,-.08+i*.045,.22),(.13,.016,.014),'white','foot_'+side,bevel=.005)
orb('TailBase',(0,.29,.65),(.14,.25,.13),'fur','tail_01');orb('TailMiddle',(0,.47,.77),(.17,.14,.23),'fur','tail_02');orb('TailTip',(0,.55,.95),(.13,.11,.17),'light','tail_03')
# Batch the character by material while preserving shared joint weights.
# This reduces the runtime from many construction meshes to one skinned mesh per material.
merged=[]
for material in M.values():
 group=[o for o in base if o.data.materials and o.data.materials[0]==material]
 if not group:continue
 base=[o for o in base if o not in group]
 bpy.ops.object.select_all(action='DESELECT')
 for o in group:o.select_set(True)
 bpy.context.view_layer.objects.active=group[0]
 if len(group)>1:bpy.ops.object.join()
 result=bpy.context.object;result.name='WolfySkin_'+material.name;merged.append(result)
base=merged
sockets={
'head':('head',(0,0,2.025)),'face':('head',(0,-.32,1.72)),'neck':('chest',(0,-.03,1.22)),'chest':('chest',(0,-.20,1.01)),'back':('chest',(0,.22,1.0)),
'hand_l':('hand_l',(-.41,-.07,.66)),'hand_r':('hand_r',(.41,-.07,.66)),'waist':('pelvis',(0,0,.67)),'feet':('root',(0,0,0)),'tail':('tail_03',(0,.55,.97)),'aura':('root',(0,0,0)),'vehicle_scene':('root',(0,0,0))}
for name,(joint,pos) in sockets.items():
 o=bpy.data.objects.new('socket_'+name,None);scene.collection.objects.link(o);o.parent=rig;o.parent_type='BONE';o.parent_bone=bones[joint];bpy.context.view_layer.update();o.matrix_world.translation=pos
clips='idle_neutral idle_happy idle_focused idle_tired blink look_around tail_wag thinking talking listening concerned encouraging celebrate_lead celebrate_appointment celebrate_sale goal_completed streak_saved level_up rank_up equip_item wave walk run eat_treat play train sleep wake_up'.split()
loops=set(clips[:7]+['thinking','talking','listening','walk','run','sleep'])
actions={}
for clip in clips:
 action=bpy.data.actions.new(clip);rig.animation_data_create();rig.animation_data.action=action;actions[clip]=action
 length=48 if clip in loops else 72
 for f in range(1,length+1,3):
  t=(f-1)/(length-1);wave=math.sin(t*math.tau);beat=math.sin(t*math.tau*2);pulse=math.sin(t*math.pi)
  for p in rig.pose.bones:p.rotation_mode='XYZ';p.rotation_euler=(0,0,0);p.location=(0,0,0);p.scale=(1,1,1)
  rig.pose.bones['wolfy_chest'].rotation_euler.y=.025*wave
  rig.pose.bones['wolfy_head'].rotation_euler.z=.025*wave
  rig.pose.bones['wolfy_tail_01'].rotation_euler.y=.14*wave
  rig.pose.bones['wolfy_tail_02'].rotation_euler.y=.16*beat
  for side in ['l','r']:
   rig.pose.bones['wolfy_ear_'+side].rotation_euler.x=.045*beat
   if clip in ['blink','idle_neutral','idle_happy'] and .44<t<.57:rig.pose.bones['wolfy_eye_'+side].scale.z=.12
  if clip=='idle_happy':rig.pose.bones['wolfy_tail_01'].rotation_euler.y=.32*beat
  if clip in ['idle_focused','train']:rig.pose.bones['wolfy_head'].rotation_euler.x=.10
  if clip in ['idle_tired','sleep']:rig.pose.bones['wolfy_head'].rotation_euler.x=.17;rig.pose.bones['wolfy_eye_l'].scale.z=.15;rig.pose.bones['wolfy_eye_r'].scale.z=.15
  if clip in ['look_around','listening']:rig.pose.bones['wolfy_head'].rotation_euler.z=.23*wave
  if clip in ['thinking','concerned']:rig.pose.bones['wolfy_head'].rotation_euler.y=.16;rig.pose.bones['wolfy_brow_l'].rotation_euler.y=.2
  if clip in ['talking','eat_treat']:rig.pose.bones['wolfy_jaw'].rotation_euler.x=.17*abs(beat)
  if clip in ['wave','encouraging','equip_item','play','wake_up','eat_treat']:rig.pose.bones['wolfy_upperarm_r'].rotation_euler.z=-.9*pulse;rig.pose.bones['wolfy_forearm_r'].rotation_euler.x=-.4*pulse
  if clip.startswith('celebrate') or clip in ['goal_completed','streak_saved','level_up','rank_up']:
   power=1.0 if clip in ['celebrate_sale','rank_up'] else .55
   rig.pose.bones['wolfy_upperarm_l'].rotation_euler.z=1.6*power*pulse;rig.pose.bones['wolfy_upperarm_r'].rotation_euler.z=-1.6*power*pulse;rig.pose.bones['wolfy_tail_01'].rotation_euler.y=.45*beat
   rig.pose.bones['wolfy_root'].location.y=.07*power*max(0,beat)
  if clip in ['walk','run']:
   for side,sgn in [('l',1),('r',-1)]:
    rig.pose.bones['wolfy_thigh_'+side].rotation_euler.x=.45*wave*sgn;rig.pose.bones['wolfy_upperarm_'+side].rotation_euler.x=-.35*wave*sgn;rig.pose.bones['wolfy_shin_'+side].rotation_euler.x=.25*max(0,-wave*sgn)
  for p in rig.pose.bones:
   p.keyframe_insert(data_path='rotation_euler',frame=f);p.keyframe_insert(data_path='location',frame=f);p.keyframe_insert(data_path='scale',frame=f)
 # Match first and final poses for loops.
 if True:
  scene.frame_set(1)
  for p in rig.pose.bones:
   for prop in ['rotation_euler','location','scale']:p.keyframe_insert(data_path=prop,frame=length)
 action.use_fake_user=True
rig.animation_data.action=actions['idle_neutral'];scene.frame_start=1;scene.frame_end=48;scene.frame_set(1)
# Catalog uses stable IDs. Fitted accessories share the master skeleton; rigid items use sockets.
catalog=[]
entries=[('default_hoodie','Black W Hoodie','tops','chest',0,1),('default_pants','Dark Cargo Pants','pants','waist',0,1),('default_shoes','Black and White Sneakers','feet','feet',0,1),('basic_collar','Basic Collar','neck','neck',0,1),('default_den','Default Den','den','vehicle_scene',0,1),('cap','WolfGrid Cap','head','head',150,1),('beanie','Black Beanie','head','head',100,1),('silver_chain','Silver Chain','neck','neck',200,1),('glasses','Clear Glasses','face','face',150,1),('sunglasses','Dark Sunglasses','face','face',200,1),('bandana','Black Bandana','neck','neck',100,1),('white_sneakers','White Sneakers','feet','feet',300,1),('gloves','Work Gloves','hands','hand_r',200,1),('hard_hat','Roofing Hard Hat','head','head',500,10),('hi_vis','High Visibility Vest','outerwear','chest',500,10),('tool_belt','Tool Belt','waist','waist',600,10),('clipboard','Clipboard','hands','hand_l',400,10),('backpack','WolfGrid Backpack','back','back',700,10),('storm_jacket','Storm Jacket','outerwear','chest',900,10),('work_boots','Premium Work Boots','feet','feet',650,10),('headset','Headset','head','head',450,10),('alpha_jacket','Alpha Bomber','outerwear','chest',1800,50),('gold_chain','Heavy Gold Chain','neck','neck',1500,25),('tablet','Sales Tablet','hands','hand_l',1200,25),('blue_aura','Electric Blue Aura','auras','aura',2500,25)]
accessories={}
for id,title,category,socket,price,level in entries:
 objs=[];x,y,z=sockets[socket][1];joint=sockets[socket][0]
 def B(n,loc,scale,material):return box(id+'_'+n,loc,scale,material,joint,objs)
 def O(n,loc,scale,material):return orb(id+'_'+n,loc,scale,material,joint,objs)
 if id in ['default_hoodie','default_pants','default_shoes','default_den']:
  pass
 elif category=='head':
  if id=='headset':
   for s in [-1,1]:O('earcup'+str(s),(s*.36,0,1.72),(.06,.1,.11),'black')
   B('band',(0,.04,1.99),(.66,.07,.06),'black');B('mic',(.25,-.34,1.5),(.20,.03,.035),'black')
  else:
   O('crown',(0,.01,1.99),(.285,.25,.15),'hiVis' if id=='hard_hat' else 'black')
   if id in ['cap','hard_hat']:B('brim',(0,-.20,1.94),(.57,.26,.035),'hiVis' if id=='hard_hat' else 'black')
   if id=='cap':B('badge',(0,-.229,2.02),(.10,.018,.07),'white')
 elif category=='face':
  for s in [-1,1]:
   B('frame'+str(s),(s*.16,-.35,1.72),(.25,.025,.17),'black')
   B('lens'+str(s),(s*.16,-.368,1.72),(.205,.010,.125),'blue' if id=='glasses' else 'nose')
  B('bridge',(0,-.36,1.72),(.10,.02,.025),'silver')
 elif category=='neck':
  if id=='bandana':B('cloth',(0,-.20,1.2),(.30,.035,.10),'black')
  else:
   for i in range(14):
    a=math.tau*i/14;O('link'+str(i),(.22*math.cos(a),.15*math.sin(a)-.02,1.2-.055*max(0,-math.sin(a))),(.035,.025,.025),'gold' if id=='gold_chain' else 'silver')
 elif category=='back':
  B('pack',(0,.29,1.02),(.40,.19,.43),'cargo');B('pocket',(0,.405,.96),(.29,.06,.18),'black')
  for s in [-1,1]:B('strap'+str(s),(s*.19,.16,1.04),(.04,.05,.38),'sole')
 elif category=='outerwear':
  O('vest',(0,0,.95),(.305,.219,.29),'hiVis' if id=='hi_vis' else 'cargo' if id=='storm_jacket' else 'black')
  B('zip',(0,-.222,.98),(.017,.01,.40),'silver')
  for s in [-1,1]:B('pocket'+str(s),(s*.15,-.21,.83),(.12,.035,.10),'black')
 elif category=='waist':
  B('belt',(0,0,.68),(.55,.36,.065),'black')
  for s in [-1,1]:B('pouch'+str(s),(s*.25,-.12,.61),(.12,.12,.15),'cargo')
 elif category=='feet':
  for s in [-1,1]:
   o=box(id+str(s),(s*.16,-.065,.135),(.255,.35,.18),'white' if id=='white_sneakers' else 'cargo','foot_l' if s<0 else 'foot_r',objs)
 elif id=='gloves':O('glove',(.41,-.04,.67),(.115,.12,.13),'black')
 elif id in ['clipboard','tablet']:
  B('board',(-.43,-.15,.79),(.25,.045,.34),'cargo' if id=='clipboard' else 'black');B('paper',(-.43,-.18,.79),(.21,.013,.27),'white' if id=='clipboard' else 'blue')
 elif id=='blue_aura':
  bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=8,location=(0,0,.035),major_radius=.49,minor_radius=.016);o=bpy.context.object;finish(o,id,'blue');bind(o,'root',objs)
 accessories[id]=objs
 catalog.append(dict(id=id,name=title,description=title+' • cosmetic only',category=category,socket='socket_'+socket,rarity='common' if level==1 else 'rare' if level==10 else 'epic',price=price,requiredLevel=level,asset=id+'.usdz' if objs else None,thumbnail=id+'.png',compatibility=['wolfy-v1'],active=True,sortOrder=len(catalog),bundled=True))
 for o in objs:o.hide_render=True;o.hide_set(True)
# Camera, studio lights and floor exist only in source/renders, never runtime files.
def point(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(3,-6,2.8));camera=bpy.context.object;point(camera,(0,0,1.05));camera.data.type='ORTHO';camera.data.ortho_scale=2.75;scene.camera=camera
for name,loc,power,size in [('Key',(-3,-4,5),500,4),('Fill',(3,-2,3),300,3),('Rim',(1,3,4),650,3)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;point(o,(0,0,1))
floor=box('StudioFloor',(0,0,0),(200,200,.05),'sole')
scene.view_settings.view_transform='AgX'
def select_base(extra=[]):
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
 for o in base+extra:o.hide_set(False);o.select_set(True)
 for o in rig.children:
  if o.type=='EMPTY':o.select_set(True)
 bpy.context.view_layer.objects.active=rig

def usd(path,animation=True):
 bpy.ops.wm.usd_export(filepath=str(path),selected_objects_only=True,export_animation=animation,export_armatures=True,export_shapekeys=True,export_materials=True,export_subdivision='IGNORE',generate_materialx_network=False,export_lights=False,export_cameras=False,triangulate_meshes=True,root_prim_path='/Wolfy',convert_orientation=True,export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y')
select_base();usd(OUT/'wolfy_base.usdz',False)
# GLB stores all named actions as NLA tracks.
for name,action in actions.items():
 track=rig.animation_data.nla_tracks.new();track.name=name;track.strips.new(name,1,action)
rig.animation_data.action=None
bpy.ops.export_scene.gltf(filepath=str(ART/'exports/wolfy.glb'),use_selection=True,export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS')
for track in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(track)
for name,action in actions.items():
 rig.animation_data.action=action;scene.frame_end=48 if name in loops else 72;scene.frame_set(1);select_base();usd(OUT/('wolfy_'+name+'.usdz'))
rig.animation_data.action=actions['idle_neutral'];scene.frame_end=48;scene.frame_set(1)
for id,objs in accessories.items():
 if not objs:continue
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
 for o in objs:o.hide_set(False);o.hide_render=False;o.select_set(True)
 usd(OUT/(id+'.usdz'),False)
 bpy.ops.export_scene.gltf(filepath=str(ART/'exports'/(id+'.glb')),use_selection=True,export_format='GLB',export_animations=False)
 if '--assets-only' not in sys.argv:
  scene.render.resolution_x=256;scene.render.resolution_y=256;scene.render.filepath=str(ART/'renders'/(id+'.png'));bpy.ops.render.render(write_still=True)
 for o in objs:o.hide_set(True);o.hide_render=True
scene.render.resolution_x=768;scene.render.resolution_y=768
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'blender/Wolfy.blend'))
if '--assets-only' not in sys.argv:
 for name,loc in [('front',(0,-6,1.5)),('side',(6,0,1.5)),('rear',(0,6,1.5)),('poster',(3,-6,2.8))]:
  camera.location=loc;point(camera,(0,0,1.06));scene.render.filepath=str(ART/'renders'/(name+'.png'));bpy.ops.render.render(write_still=True)
 import shutil
 shutil.copy(ART/'renders/poster.png',OUT/'wolfy_poster.png')
 for i in range(24):
  angle=math.tau*i/24;camera.location=(6*math.sin(angle),-6*math.cos(angle),2.4);point(camera,(0,0,1.06));scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.filepath=str(ART/'renders'/('turntable_%03d.png'%i));bpy.ops.render.render(write_still=True)
triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in base)
manifest=dict(version=1,compatibility='wolfy-v1',base='wolfy_base.usdz',poster='wolfy_poster.png',triangles=triangles,bones=list(bones.values()),sockets=['socket_'+s for s in sockets],animations=[dict(name=n,file='wolfy_'+n+'.usdz',loop=n in loops,duration=2 if n in loops else 3) for n in clips],items=catalog,files={p.name:dict(sha256=hashlib.sha256(p.read_bytes()).hexdigest(),bytes=p.stat().st_size) for p in OUT.glob('*.usdz')})
for p in [OUT/'wolfy_manifest.json',ART/'manifests/wolfy_manifest.json']:p.write_text(json.dumps(manifest,indent=2))
if '--assets-only' not in sys.argv:
 import shutil
 for item in catalog:
  thumbnail=ART/'renders'/item['thumbnail']
  shutil.copy(thumbnail if thumbnail.exists() else ART/'renders/poster.png',OUT/item['thumbnail'])
print('WOLFY_COMPLETE',triangles,'triangles',len(clips),'clips',len(catalog),'items')
