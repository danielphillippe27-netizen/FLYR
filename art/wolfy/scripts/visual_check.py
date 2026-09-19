"""Render each exported accessory in four poses from front and rear three-quarter views."""
import bpy,json
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[3];art=root/'art/wolfy';out=art/'renders/validation';out.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(art/'blender/Wolfy.blend'))
m=json.loads((art/'manifests/wolfy_manifest.json').read_text());scene=bpy.context.scene;rig=bpy.data.objects['WolfyRig']
scene.render.resolution_x=256;scene.render.resolution_y=256;scene.cycles.samples=12
accessories={i['id']:[o for o in bpy.data.objects if o.type=='MESH' and (o.name.startswith(i['id']+'_') or o.name in [i['id']+'-1',i['id']+'1',i['id']])] for i in m['items'] if i['asset']}
for objects in accessories.values():
 for o in objects:o.hide_render=True
for id,objects in accessories.items():
 for o in objects:o.hide_render=False
 for clip,frame in [('idle_neutral',12),('walk',12),('celebrate_sale',25),('equip_item',25)]:
  rig.animation_data.action=bpy.data.actions[clip];scene.frame_set(frame)
  for view,loc in [('front',(3,-6,2.7)),('rear',(-3,6,2.7))]:
   scene.camera.location=loc;scene.camera.rotation_euler=(Vector((0,0,1.05))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
   scene.render.filepath=str(out/(id+'_'+clip+'_'+view+'.png'));bpy.ops.render.render(write_still=True)
 for o in objects:o.hide_render=True
print('VISUAL_CONTACT_SHEETS_READY',len(accessories)*8)
