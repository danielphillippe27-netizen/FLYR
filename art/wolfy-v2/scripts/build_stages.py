"""Original quadruped prototype. Blender 5; one stage until the on-device map gate passes.
Exports an editable skinned Blender source and GPU-ready mesh / sampled skin matrices.
Coordinates: metres, Z up, nose toward negative Y. No legacy assets are overwritten.
"""
import bpy, math, json, struct, hashlib, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
STAGE = sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'pup'
SHAPES = {
 'pup': ('Wolf Pup',1,1,1,1,1),
 'young': ('Young Wolf',1.10,1.28,1.36,.91,1.07),
 'street': ('Street Wolf',1.23,1.53,1.75,.82,1.14),
 'alpha': ('Alpha',1.55,1.62,1.91,.85,1.30),
 'legend': ('Grid Legend',1.67,1.80,2.13,.87,1.40)
}
TITLE,WIDTH,LENGTH,LEGS,HEAD,TAIL=SHAPES[STAGE]
OUT=ROOT/'art/wolfy-v2/stages'/STAGE; ART=OUT
# Draft stage exports stay outside the shipping bundle until animation/art QA.
def mapped(pos, head=False):
 x,y,z=pos
 if head:
  x*=HEAD; y=-.43+(y+.43)*HEAD; z=.83+(z-.83)*HEAD
 return (x*WIDTH,y*LENGTH,z*LEGS if z<.53 else .53*LEGS+(z-.53))
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
rig_data=bpy.data.armatures.new('WolfyQuadruped'); rig=bpy.data.objects.new('WolfyQuadruped',rig_data)
scene.collection.objects.link(rig); bpy.context.view_layer.objects.active=rig;rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
def bone(name,head,tail,parent=None):
 b=rig_data.edit_bones.new(name); b.head=mapped(head,name=="head" or name.startswith("ear"));b.tail=mapped(tail,name=="head" or name.startswith("ear"))
 if parent:b.parent=rig_data.edit_bones[parent]
bone('root',(0,0,0),(0,0,.1))
bone('body',(0,.25,.54),(0,-.23,.58),'root')
bone('neck',(0,-.23,.58),(0,-.37,.78),'body')
bone('head',(0,-.37,.78),(0,-.56,.82),'neck')
bone('tail',(0,.37,.53),(0,.68,.43),'body')
for side,x in [('l',-.16),('r',.16)]:
 for end,y in [('front',-.24),('rear',.27)]:
  n=end+'_'+side
  bone(n,(x,y,.53),(x,y,.27),'body');bone(n+'_lower',(x,y,.27),(x,y,.08),n)
 bone('ear_'+side,(x*.8,-.38,.92),(x*.8,-.36,1.12),'head')
bpy.ops.object.mode_set(mode='OBJECT');rig.select_set(False)
colors={'fur':(.27,.31,.35,1),'dark':(.12,.15,.19,1),'cream':(.76,.79,.78,1),'nose':(.025,.035,.045,1),'eye':(.80,.56,.19,1),'white':(.96,.97,.94,1)}
mats={}
for n,c in colors.items():
 m=bpy.data.materials.new(n);m.diffuse_color=c;m.use_nodes=True;m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=c;mats[n]=m
parts=[]
def part(name,loc,scale,color,joint,cone=False):
 head=joint=='head' or joint.startswith('ear')
 loc=mapped(loc,head)
 sx,sy,sz=scale
 scale=(sx*WIDTH*(HEAD if head else 1),sy*LENGTH*(HEAD if head else 1),sz*(HEAD if head else LEGS if 'lower' in joint or joint.startswith(('front','rear')) else 1))
 if name.startswith(('Eye','Pupil','Glint')):
  if STAGE!='pup':loc=(loc[0],loc[1]+.035*LENGTH,loc[2])
  scale=tuple(v*(1 if STAGE=='pup' else .80 if STAGE=='young' else .68) for v in scale)
 if name.startswith('Muzzle') and STAGE!='pup':scale=(scale[0]*.92,scale[1]*1.12,scale[2])
 if name=='Nose' and STAGE!='pup':loc=(loc[0],loc[1]-.038*LENGTH,loc[2])
 if name.startswith(('Tail','TailTip')):scale=(scale[0]*TAIL,scale[1],scale[2]*TAIL)
 if name=='Chest' and STAGE in ['alpha','legend']:scale=(scale[0]*1.12,scale[1],scale[2]*1.15)
 if cone:bpy.ops.mesh.primitive_cone_add(vertices=16,radius1=1,radius2=.04,depth=2,location=loc)
 else:bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=loc)
 o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(mats[color]);g=o.vertex_groups.new(name=joint);g.add(list(range(len(o.data.vertices))),1,'REPLACE')
 mod=o.modifiers.new('Skin','ARMATURE');mod.object=rig;o.parent=rig
 for p in o.data.polygons:p.use_smooth=True
 parts.append(o);return o
part('Torso',(0,.02,.54),(.225,.43,.245),'fur','body')
part('Chest',(0,-.24,.57),(.24,.22,.27),'cream','body')
part('Ruff',(0,-.29,.71),(.245,.22,.24),'fur','neck')
part('Head',(0,-.43,.83),(.235,.245,.245),'fur','head')
part('Muzzle',(0,-.635,.76),(.145,.19,.105),'cream','head')
part('Nose',(0,-.8,.79),(.072,.052,.052),'nose','head')
part('Chin',(0,-.65,.705),(.115,.125,.036),'dark','head')
for side,x in [('l',-.16),('r',.16)]:
 part('Cheek_'+side,(x,-.50,.76),(.105,.15,.12),'cream','head')
 part('Eye_'+side,(x*.92,-.621,.884),(.067,.043,.071),'eye','head')
 part('Pupil_'+side,(x*.92,-.659,.885),(.031,.014,.047),'nose','head')
 part('Glint_'+side,(x*.92-.011,-.673,.908),(.011,.006,.014),'white','head')
 part('Ear_'+side,(x,-.39,1.055),(.098,.080,.165),'dark','ear_'+side,True)
 part('InnerEar_'+side,(x,-.454,1.059),(.058,.017,.106),'cream','ear_'+side,True)
 for end,y in [('front',-.24),('rear',.27)]:
  n=end+'_'+side
  part(n+'_thigh',(x,y,.40),(.092,.11,.175),'fur',n)
  part(n+'_shin',(x,y,.205),(.064,.072,.145),'cream',n+'_lower')
  part(n+'_paw',(x,y-.045,.078),(.099,.133,.074),'cream',n+'_lower')
part('Tail',(0,.60,.43),(.125,.30,.13),'fur','tail')
part('TailTip',(0,.81,.40),(.10,.135,.102),'cream','tail')
# Small angular cheek ruff silhouettes, no fur simulation.
for s in [-1,1]:
 for i in range(3):
  o=part('RuffTuft',(s*(.19+i*.025),-.24,.68-i*.055),(.055,.08,.105),'fur','neck',True);o.rotation_euler.y=s*.8
names=[b.name for b in rig.data.bones];indices={n:i for i,n in enumerate(names)}
clips={}
for clip in ['idle','walk','trot','run','sit','look_around','celebrate']:
 action=bpy.data.actions.new(clip);action.use_fake_user=True;rig.animation_data_create();rig.animation_data.action=action
 for f in range(49):
  t=f/48;phase=t*math.tau
  for p in rig.pose.bones:p.rotation_mode='XYZ';p.rotation_euler=(0,0,0);p.location=(0,0,0)
  rig.pose.bones['body'].location.z=.008*math.sin(phase*2)
  rig.pose.bones['head'].rotation_euler.y=.04*math.sin(phase)
  rig.pose.bones['tail'].rotation_euler.z=.16*math.sin(phase*2)
  if clip in ['walk','trot','run']:
   amp={'walk':.30,'trot':.45,'run':.65}[clip]
   for n,offset in [('front_l',0),('rear_r',0),('front_r',math.pi),('rear_l',math.pi)]:
    a=phase+offset;rig.pose.bones[n].rotation_euler.x=amp*math.sin(a)
    rig.pose.bones[n+'_lower'].rotation_euler.x=-.32*max(0,math.cos(a))
  if clip=='look_around':rig.pose.bones['head'].rotation_euler.z=.32*math.sin(phase)
  if clip=='celebrate':
   rig.pose.bones['root'].location.z=.16*max(0,math.sin(phase))
   rig.pose.bones['tail'].rotation_euler.z=.5*math.sin(phase*3)
  if clip=='sit':
   rig.pose.bones['body'].rotation_euler.x=-.15
   for s in ['l','r']:rig.pose.bones['rear_'+s].rotation_euler.x=-.85;rig.pose.bones['rear_'+s+'_lower'].rotation_euler.x=1.2
  for p in rig.pose.bones:p.keyframe_insert('rotation_euler',frame=f);p.keyframe_insert('location',frame=f)
 matrices=[]
 for f in range(48):
  scene.frame_set(f)
  for b in rig.data.bones:
   m=rig.pose.bones[b.name].matrix @ b.matrix_local.inverted()
   matrices.extend(m[r][c] for c in range(4) for r in range(4))
 clips[clip]={'duration':2,'frames':48,'matrices':matrices}
rig.animation_data.action=None;scene.frame_set(0)
# Read undeformed mesh in rig-local coordinates; shader applies exported skin matrices.
verts=[];tris=[]
for o in parts:
 mesh=o.data;mesh.calc_loop_triangles();offset=len(verts)//16
 for v in mesh.vertices:
  pos=o.matrix_local @ v.co;normal=(o.matrix_local.to_3x3() @ v.normal).normalized()
  joint=indices[o.vertex_groups[v.groups[0].group].name];c=colors[o.data.materials[0].name]
  verts.extend([*pos,1,*normal,0,*c,float(joint),0,0,0])
 for tri in mesh.loop_triangles:tris.extend(offset+i for i in tri.vertices)
mesh_file=OUT/(STAGE+'-mesh.bin');mesh_file.write_bytes(struct.pack('<%sf'%len(verts),*verts)+struct.pack('<%sI'%len(tris),*tris))
clip_meta={}
for name,c in clips.items():
 p=OUT/(STAGE+'-'+name+'.bin');p.write_bytes(struct.pack('<%sf'%len(c['matrices']),*c['matrices']))
 clip_meta[name]={'file':p.name,'duration':c['duration'],'frames':c['frames']}
manifest={'version':2,'stage':TITLE,'prototype':True,'vertices':len(verts)//16,'indices':len(tris),'bones':names,'mesh':mesh_file.name,'clips':clip_meta}
manifest['files']={p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in OUT.glob(STAGE+'-*.bin')}
(OUT/(STAGE+'-manifest.json')).write_text(json.dumps(manifest,indent=2))
scene.render.engine='CYCLES';scene.cycles.samples=16;scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.world.color=(.16,.16,.16)
bpy.ops.object.light_add(type='AREA',location=(2,-3,4));bpy.context.object.data.energy=450;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=4
bpy.ops.object.camera_add(location=(3,-4,2.5));cam=bpy.context.object;cam.rotation_euler=(Vector((0,-.1,.7*LEGS))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.6*max(WIDTH,LENGTH);scene.camera=cam
bpy.ops.wm.save_as_mainfile(filepath=str(ART/(STAGE+'.blend')))
scene.render.filepath=str(ART/(STAGE+'.png'));bpy.ops.render.render(write_still=True)
print('DRAFT STAGE',manifest['vertices'],manifest['indices']//3,'triangles')
