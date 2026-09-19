"""Wolfy character revision: continuous quadruped surface, two-bone skinning, five silhouettes.
Blender 5, Z up, nose -Y. Draft exports are reviewed before copying into Resources.
"""
import bpy, math, json, struct, hashlib, sys
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[3]
STAGES={'pup':('Wolf Pup',1,1,1,1,1), 'young':('Young Wolf',1.02,1.10,1.22,1.02,1.08), 'street':('Street Wolf',1.10,1.25,1.52,1.04,1.16), 'alpha':('Alpha',1.38,1.50,1.60,1.12,1.24), 'legend':('Veteran Alpha',1.5,1.68,1.68,1.17,1.38)}
requested=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(STAGES)
for stage in requested:
 title,W,L,LEGS,H,T=STAGES[stage]; out=ROOT/'art/wolfy-v2/character'/stage;out.mkdir(parents=True,exist_ok=True)
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 scene=bpy.context.scene
 def mapped(p):
  x,y,z=p
  # Grow the legs without stretching the face; the torso length changes independently.
  return Vector((x*W,y*L,z*LEGS if z<.4 else .4*LEGS+(z-.4)*H))
 mats={}
 palette={'fur':(.20,.255,.30,1),'cream':(.79,.85,.84,1),'dark':(.035,.065,.087,1),'amber':(1,.56,.07,1),'pupil':(.007,.018,.025,1),'white':(1,1,1,1)}
 for name,color in palette.items():
  m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True;m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=color;m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.62;mats[name]=m
 core=[]; details=[]
 def ellipsoid(name,loc,size,color='fur',joint=None):
  bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=16,location=mapped(loc));o=bpy.context.object;o.name=name
  o.scale=(size[0]*W,size[1]*L,size[2]*(LEGS if loc[2]<.4 else H));bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
  o.data.materials.append(mats[color]);o['joint']=joint or 'body'
  for p in o.data.polygons:p.use_smooth=True
  (details if joint else core).append(o);return o
 ellipsoid('Compact torso',(0,.055,.43),(.235,.31,.235))
 ellipsoid('Chest',(0,-.14,.47),(.25 if stage not in ('alpha','legend') else .295,.235,.25))
 ellipsoid('Neck',(0,-.23,.60),(.235,.21,.25))
 ellipsoid('Oversized head',(0,-.375,.73),(.31,.285,.29))
 muzzle_extension={'alpha':.07,'legend':.11}.get(stage,0)
 # Project beyond the forehead so the wolf silhouette reads from the map camera.
 ellipsoid('Long tapered muzzle',(0,-.715-muzzle_extension/2,.66),(.155,.215+muzzle_extension/2,.12))
 for s in [-1,1]:
  ellipsoid('Round cheek',(s*.193,-.53,.635),(.137,.17,.13))
  for y in [-.17,.235]:
   ellipsoid('Blended leg',(s*.18,y,.285),(.098,.108,.19))
   ellipsoid('Chunky paw',(s*.18,y-.04,.087),(.126,.158,.084))
  if stage in ('alpha','legend'):
   ellipsoid('Mane',(s*.23,-.12,.61),(.115,.20,.255))
   ellipsoid('Cheek ruff',(s*.255,-.37,.67),(.13,.12,.155))
 # Connected upward-curving plume, tapering to a soft tip.
 for i in range(10):
  t=i/9;r=(.13+.055*math.sin(t*math.pi))*(1-.68*t**3)*T
  ellipsoid('Tail plume',(0,.29+.49*t,.47+.08*t+.32*t*t),(r,r*1.05,r))
 # Voxel union and smoothing eliminate primitive seams throughout the skin.
 bpy.ops.object.select_all(action='DESELECT')
 for o in core:o.select_set(True)
 bpy.context.view_layer.objects.active=core[0];bpy.ops.object.join();body=bpy.context.object;body.name='Wolfy continuous skin'
 remesh=body.modifiers.new('Continuous forms','REMESH');remesh.mode='VOXEL';remesh.voxel_size=.025;remesh.use_smooth_shade=True
 bpy.ops.object.modifier_apply(modifier=remesh.name)
 smooth=body.modifiers.new('Soft transitions','SMOOTH');smooth.factor=1.25;smooth.iterations=5;bpy.ops.object.modifier_apply(modifier=smooth.name)
 dec=body.modifiers.new('Map mesh budget','DECIMATE');dec.ratio=min(1,7500/len(body.data.vertices));bpy.ops.object.modifier_apply(modifier=dec.name)
 for p in body.data.polygons:p.use_smooth=True
 # Clear dark sockets, ivory sclera, luminous amber irises and visible highlights.
 for side,s in [('l',-1),('r',1)]:
  x=s*.148
  ellipsoid('Eye socket',(x,-.595,.785),(.124,.044,.135),'dark','head')
  ellipsoid('Eye white',(x,-.624,.784),(.105,.038,.117),'cream','head')
  ellipsoid('Amber iris',(x,-.654,.781),(.079,.023,.094),'amber','head')
  ellipsoid('Pupil',(x,-.672,.783),(.043,.012,.064),'pupil','head')
  ellipsoid('Eye highlight',(x-.024,-.683,.818),(.024,.008,.029),'white','head')
  ellipsoid('Small glint',(x+.023,-.683,.76),(.009,.005,.012),'white','head')
  if stage in ('alpha','legend'):
   o=ellipsoid('Confident brow',(x,-.646,.875),(.12,.042,.03),'fur','head');o.rotation_euler.y=-s*.15
  # Rounded triangular ears built from elliptical cross-sections, not cones.
  def ear(name,inner=False):
   verts=[];faces=[];rings=[(0,1),(.25,.96),(.55,.70),(.8,.40),(.95,.18),(1,.06)]
   for t,r in rings:
    for j in range(16):
     a=j/16*math.tau
     p=(s*(.195+.035*t)+math.cos(a)*(.125 if not inner else .078)*r,
        -.345-(.082 if inner else 0)+math.sin(a)*(.075 if not inner else .009)*r,
        .90+t*(.26 if not inner else .20))
     verts.append(mapped(p))
   for i in range(len(rings)-1):
    for j in range(16):faces.append((i*16+j,i*16+(j+1)%16,(i+1)*16+(j+1)%16,(i+1)*16+j))
   faces.extend([tuple(reversed(range(16))),tuple((len(rings)-1)*16+j for j in range(16))])
   mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new(name,mesh);scene.collection.objects.link(o);o.data.materials.append(mats['cream' if inner else 'fur']);o['joint']='ear_'+side
   for p in mesh.polygons:p.use_smooth=True
   details.append(o)
  ear('Soft ear');ear('Inner ear',True)
 ellipsoid('Rounded nose',(0,-.915-muzzle_extension,.675),(.115,.075,.082),'pupil','head')
 ellipsoid('Nose shine',(-.028,-.973-muzzle_extension,.708),(.025,.008,.011),'cream','head')
 # A subtle continuous smile, no separate jaw plate.
 ellipsoid('Mouth',(0,-.897-muzzle_extension,.591),(.085,.009,.012),'dark','head')
 rig_data=bpy.data.armatures.new('Wolfy');rig=bpy.data.objects.new('Wolfy',rig_data);scene.collection.objects.link(rig)
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
 def bone(n,a,b,parent=None):
  q=rig_data.edit_bones.new(n);q.head=mapped(a);q.tail=mapped(b)
  if parent:q.parent=rig_data.edit_bones[parent]
 bone('root',(0,0,0),(0,0,.1));bone('body',(0,.22,.43),(0,-.15,.46),'root');bone('neck',(0,-.15,.46),(0,-.27,.65),'body');bone('head',(0,-.27,.65),(0,-.53,.73),'neck');bone('tail',(0,.32,.46),(0,.70,.74),'body')
 for side,s in [('l',-1),('r',1)]:
  for end,y in [('front',-.17),('rear',.235)]:
   n=end+'_'+side;bone(n,(s*.18,y,.40),(s*.18,y,.23),'body');bone(n+'_lower',(s*.18,y,.23),(s*.18,y-.035,.085),n);bone(n+'_paw',(s*.18,y-.035,.085),(s*.18,y-.12,.085),n+'_lower')
  bone('ear_'+side,(s*.195,-.345,.90),(s*.23,-.345,1.14),'head')
 bpy.ops.object.mode_set(mode='OBJECT');names=[b.name for b in rig_data.bones];jointIDs={n:i for i,n in enumerate(names)}
 vertices=[];indices=[];positions=[];joints=[];weights=[]
 def skin(pos):
  x,y,z=pos.x/W,pos.y/L,pos.z
  if y<-.30 and z>.46*LEGS:
   return 'head','neck',max(.35,min(1,(-y-.30)/.18))
  if z<.40*LEGS and abs(x)>.045 and -.45<y<.45:
   side='l' if x<0 else 'r';end='front' if y<.04 else 'rear';upper=end+'_'+side
   if z<.16*LEGS:return upper+'_paw',upper+'_lower',max(0,min(1,(.16*LEGS-z)/(.045*LEGS)))
   if z>.29*LEGS:return upper,'body',max(0,min(1,(.40*LEGS-z)/(.11*LEGS)))
   blend=max(0,min(1,(z-.17*LEGS)/(.12*LEGS)))
   return upper,upper+'_lower',blend
  if y>.33:return 'tail','body',max(0,min(1,(y-.33)/.20))
  return 'neck','body',max(0,min(.8,(-y-.05)/.24))*max(0,min(1,(z-.35*LEGS)/.2))
 for o in [body]+details:
  o.data.calc_loop_triangles();base=len(vertices)//16
  for v in o.data.vertices:
   p=o.matrix_world@v.co;n=(o.matrix_world.to_3x3()@v.normal).normalized()
   if o==body:
    a,b,w=skin(p)
    # Anatomical markings remain part of the continuous surface, with soft boundaries.
    x,y,z=p.x/W,p.y/L,(p.z-.4*LEGS)/H+.4 if p.z>=.4*LEGS else p.z/LEGS
    cream=max(0,min(1,(.18-z)*28))
    cheek=math.exp(-((y+.66+muzzle_extension/2)/(.27+muzzle_extension/2))**4-((z-.65)/.125)**4)
    chest=math.exp(-((y+.24)/.10)**4-((z-.45)/.20)**4)
    tip=max(0,min(1,(y-.68)*12))
    cream=max(cream,cheek,chest,tip)
    c=tuple(palette['fur'][i]*(1-cream)+palette['cream'][i]*cream for i in range(3))+(1,)
   else:a=b=o['joint'];w=1;c=tuple(o.data.materials[0].diffuse_color)
   vertices.extend([*p,1,*n,0,*c,jointIDs[a],jointIDs[b],1-w,0]);positions.append([*p,1]);joints.append([jointIDs[a],jointIDs[b]]);weights.append(w)
   for name,weight in [(a,w),(b,1-w)]:
    group=o.vertex_groups.get(name) or o.vertex_groups.new(name=name);group.add([v.index],weight,'ADD')
  for tri in o.data.loop_triangles:indices.extend(base+i for i in tri.vertices)
  mod=o.modifiers.new('Soft skin','ARMATURE');mod.object=rig
 # Vertex color material allows the source renders to show the exact GPU palette.
 colorAttr=body.data.color_attributes.new(name='WolfyColor',type='FLOAT_COLOR',domain='POINT')
 for i in range(len(body.data.vertices)):colorAttr.data[i].color=vertices[i*16+8:i*16+12]
 m=bpy.data.materials.new('Wolfy skin');m.use_nodes=True;node=m.node_tree.nodes.new('ShaderNodeVertexColor');node.layer_name='WolfyColor';m.node_tree.links.new(node.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color']);body.data.materials.clear();body.data.materials.append(m)
 pArray=np.array(positions);jArray=np.array(joints);wArray=np.array(weights)[:,None]
 clips={}
 for clip in ['idle','walk','trot','run','sit','look_around','celebrate','sniff','scratch','lie_down','get_up']:
  duration=24 if clip=='idle' else 2;frames=duration*24
  action=bpy.data.actions.new(clip);action.use_fake_user=True;rig.animation_data_create();rig.animation_data.action=action
  for f in range(frames+1):
   t=f/24;phase=t*math.pi*2;progress=f/frames
   for p in rig.pose.bones:p.rotation_mode='XYZ';p.rotation_euler=(0,0,0);p.location=(0,0,0);p.scale=(1,1,1)
   def env(start,end):
    return max(0,min(1,(t-start)/.7,(end-t)/.7))
   sniff=env(1,4) if clip=='idle' else 1 if clip=='sniff' else 0
   look=env(4,8) if clip=='idle' else 1 if clip=='look_around' else 0
   scratch=env(8,11) if clip=='idle' else math.sin(progress*math.pi)**2 if clip=='scratch' else 0
   sit=env(11,16) if clip=='idle' else math.sin(progress*math.pi)**2 if clip=='sit' else 0
   lie=env(16,23) if clip=='idle' else (math.sin(progress*math.pi/2)**2 if clip=='lie_down' else math.cos(progress*math.pi/2)**2 if clip=='get_up' else 0)
   bodyZ=.009*math.sin(phase/2)-(.12*sit+.27*lie)*LEGS
   rig.pose.bones['head'].rotation_euler.x=.30*sniff+.025*math.sin(phase/2)
   rig.pose.bones['head'].rotation_euler.z=.42*look*math.sin(t*1.8)+.15*scratch
   rig.pose.bones['tail'].rotation_euler.z=.25*math.sin(t*2.2)
   for side in ['l','r']:
    rig.pose.bones['ear_'+side].rotation_euler.x=.085*math.sin(t*3+(0 if side=='l' else .8))
    rig.pose.bones['rear_'+side].rotation_euler.x=-.8*sit-.9*lie
    rig.pose.bones['rear_'+side+'_lower'].rotation_euler.x=1.1*sit+1.3*lie
    rig.pose.bones['front_'+side].rotation_euler.x=-.65*lie
    rig.pose.bones['front_'+side+'_lower'].rotation_euler.x=1.15*lie
   rig.pose.bones['rear_l'].rotation_euler.x+=scratch*(-.9+.24*math.sin(t*19));rig.pose.bones['rear_l'].rotation_euler.z=.8*scratch
   if clip in ['walk','trot','run']:
    amp={'walk':.38,'trot':.48,'run':.65}[clip]
    rig.pose.bones['head'].rotation_euler.x=.075*math.sin(phase*2)
    bodyZ=.018*(1+math.sin(phase*2))
    for n,offset in [('front_l',0),('rear_r',0),('front_r',math.pi),('rear_l',math.pi)]:
     p=phase+offset;rig.pose.bones[n].rotation_euler.x=amp*math.sin(p);rig.pose.bones[n+'_lower'].rotation_euler.x=-.35*max(0,math.cos(p))
   if clip=='celebrate':rig.pose.bones['root'].location.y=.12*max(0,math.sin(phase));rig.pose.bones['tail'].rotation_euler.z=.6*math.sin(t*10)
   rig.pose.bones['body'].location=rig_data.bones['body'].matrix_local.to_3x3().inverted()@Vector((0,0,bodyZ))
   # Soft limb compression keeps the connected skin smooth in low rest poses.
   # Paws retain their volume and ground contact while the chest settles between them.
   bpy.context.view_layer.update()
   for side,sign in [('l',-1),('r',1)]:
    for end,y in [('front',-.17),('rear',.235)]:
     n=end+'_'+side;stepY=0;stepZ=0
     if clip in ['walk','trot','run']:
      offset=0 if n in ['front_l','rear_r'] else math.pi
      stepY=.085*L*math.sin(phase+offset);stepZ=.06*max(0,math.cos(phase+offset))
     stepY+=(-.10*lie if end=='front' else .035*sit)*L
     if n=='rear_l':stepY-=.18*scratch*L;stepZ+=scratch*(.16+.018*math.sin(t*19))
     if clip=='celebrate':stepZ+=.12*max(0,math.sin(phase))
     compression=max(.12,1-(.12*sit+.27*lie)/.32)
     skinMatrix=Matrix.Translation(Vector((0,stepY,.17*LEGS*(1-compression)+stepZ)))@Matrix.Diagonal((1,1,compression,1))
     for name in [n,n+'_lower']:
      rig.pose.bones[name].matrix=skinMatrix@rig_data.bones[name].matrix_local;bpy.context.view_layer.update()
     paw=n+'_paw';rig.pose.bones[paw].matrix=Matrix.Translation(Vector((0,stepY,stepZ)))@rig_data.bones[paw].matrix_local
     bpy.context.view_layer.update()
   for p in rig.pose.bones:p.keyframe_insert('rotation_euler',frame=f);p.keyframe_insert('location',frame=f);p.keyframe_insert('scale',frame=f)
  matrices=[]
  for f in range(frames):
   scene.frame_set(f);transforms=np.array([np.array(rig.pose.bones[b.name].matrix@b.matrix_local.inverted()) for b in rig_data.bones])
   skinned=(np.einsum('nij,nj->ni',transforms[jArray[:,0]],pArray)*wArray+np.einsum('nij,nj->ni',transforms[jArray[:,1]],pArray)*(1-wArray))
   # Keep paws above ground throughout transitions and oversized steps.
   correction=max(0,-float(skinned[:,2].min()));transforms[:,2,3]+=correction
   matrices.extend(transforms.transpose(0,2,1).flatten())
  file=out/f'{stage}-{clip}.bin';file.write_bytes(np.array(matrices,dtype='<f4').tobytes());clips[clip]={'file':file.name,'duration':duration,'frames':frames}
 rig.animation_data.action=None
 for p in rig.pose.bones:p.rotation_euler=(0,0,0);p.location=(0,0,0)
 scene.frame_set(0);bpy.context.view_layer.update()
 mesh=out/f'{stage}-mesh.bin';mesh.write_bytes(struct.pack('<%sf'%len(vertices),*vertices)+struct.pack('<%sI'%len(indices),*indices))
 manifest={'version':2,'prototype':True,'revision':'wolfy-character-4' if stage in ('alpha','legend') else 'wolfy-character-3','skinning':'two-bone','stage':title,'vertices':len(vertices)//16,'indices':len(indices),'bones':names,'mesh':mesh.name,'clips':clips}
 manifest['files']={p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in out.glob('*.bin')}
 (out/f'{stage}-manifest.json').write_text(json.dumps(manifest,indent=2))
 scene.render.engine='CYCLES';scene.cycles.samples=24;scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100;scene.world.color=(.2,.2,.2)
 for loc,power,size in [((2,-4,5),550,5),((-3,-1,2),350,4),((0,4,3),650,3)]:
  bpy.ops.object.light_add(type='AREA',location=loc);bpy.context.object.data.energy=power;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=size
 bpy.ops.object.camera_add(location=(2,-4,2.1));cam=bpy.context.object;cam.rotation_euler=(Vector((0,-.05,.6*LEGS))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.25*max(W,L);scene.camera=cam
 scene.render.film_transparent=True
 bpy.ops.wm.save_as_mainfile(filepath=str(out/f'{stage}.blend'));scene.render.filepath=str(out/f'{stage}.png');bpy.ops.render.render(write_still=True)
 cam.location=(0,-.05,5);cam.rotation_euler=(0,0,0);scene.render.filepath=str(out/f'{stage}-top.png');bpy.ops.render.render(write_still=True)
 print('WOLFY',stage,manifest['vertices'],'vertices',len(indices)//3,'triangles',flush=True)
