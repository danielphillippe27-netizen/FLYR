"""Validate GPU prototype bounds, integrity and motion before loading on device."""
import json, struct, hashlib, math
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'WolfGrid/Resources/WolfyV2'
for manifest in sorted(p for p in root.glob('*-manifest.json') if not p.name.startswith('wardrobe-') and p.name != 'wardrobe-manifest.json'):
 m=json.loads(manifest.read_text())
 assert m['version']==2 and m['prototype'] and 0<len(m['bones'])<=64
 for name,info in m['files'].items():
  d=(root/name).read_bytes();assert len(d)==info['bytes'];assert hashlib.sha256(d).hexdigest()==info['sha256']
 d=(root/m['mesh']).read_bytes();offset=m['vertices']*64
 assert len(d)==offset+m['indices']*4
 vertices=struct.unpack('<%sf'%(offset//4),d[:offset]);indices=struct.unpack('<%sI'%m['indices'],d[offset:])
 assert all(math.isfinite(x) for x in vertices)
 assert all(i<m['vertices'] for i in indices)
 assert all(0<=vertices[i+12]<len(m['bones']) for i in range(0,len(vertices),16))
 if m.get('skinning')=='two-bone':
  assert all(0<=vertices[i+13]<len(m['bones']) and 0<=vertices[i+14]<=1 for i in range(0,len(vertices),16))
  assert all(clip in m['clips'] for clip in ['sniff','scratch','lie_down','get_up'])
 assert min(vertices[i+2] for i in range(0,len(vertices),16))>=-0.01
 for name,clip in m['clips'].items():
  d=(root/clip['file']).read_bytes();assert len(d)==clip['frames']*len(m['bones'])*64
  floats=struct.unpack('<%sf'%(len(d)//4),d);assert all(math.isfinite(x) for x in floats)
  if name in ['walk','trot','run']: assert d[:len(m['bones'])*64]!=d[12*len(m['bones'])*64:13*len(m['bones'])*64]
 print('PASS:',manifest.name,'indices, joints, finite matrices, hashes, ground contact and locomotion variation')
wardrobe=json.loads((root/'wardrobe-manifest.json').read_text())
data=(root/wardrobe['mesh']).read_bytes()
assert wardrobe['version']==1 and len(data)==wardrobe['bytes']
assert hashlib.sha256(data).hexdigest()==wardrobe['sha256']
bone_count=len(json.loads((root/'pup-manifest.json').read_text())['bones'])
for name,item in wardrobe['items'].items():
 vertex_start=item['vertexOffset'];index_start=item['indexOffset'];index_end=index_start+item['indexCount']*4
 assert vertex_start%64==0 and vertex_start<index_start<index_end<=len(data),name
 assert (index_start-vertex_start)%64==0 and item['indexCount']%3==0,name
 vertices=struct.unpack_from('<%sf'%((index_start-vertex_start)//4),data,vertex_start)
 indices=struct.unpack_from('<%sI'%item['indexCount'],data,index_start)
 assert all(math.isfinite(value) for value in vertices),name
 assert all(0<=index<(index_start-vertex_start)//64 for index in indices),name
 assert all(0<=vertices[i+12]<bone_count for i in range(0,len(vertices),16)),name
print('PASS: wardrobe-manifest.json',len(wardrobe['items']),'independent map accessories, hashes and bounds')
home=json.loads((root.parent/'Wolfy/wolfy_manifest.json').read_text())
expected_items={item['id'] for item in home['items'] if item.get('asset')}
for manifest_path in sorted(root.glob('wardrobe-*-manifest.json')):
 stage=manifest_path.name.removeprefix('wardrobe-').removesuffix('-manifest.json')
 home_asset=home['growthStages'][stage]
 home_bytes=(root.parent/'Wolfy'/home_asset).read_bytes()
 assert len(home_bytes)==home['files'][home_asset]['bytes']
 assert hashlib.sha256(home_bytes).hexdigest()==home['files'][home_asset]['sha256']
 wardrobe=json.loads(manifest_path.read_text())
 assert expected_items==set(wardrobe['items']),stage
 data=(root/wardrobe['mesh']).read_bytes()
 assert wardrobe['version']==1 and len(data)==wardrobe['bytes']
 assert hashlib.sha256(data).hexdigest()==wardrobe['sha256']
 stage_manifest=json.loads((root/f'{stage}-manifest.json').read_text())
 bone_count=len(stage_manifest['bones'])
 for name,item in wardrobe['items'].items():
  vertex_start=item['vertexOffset'];index_start=item['indexOffset'];index_end=index_start+item['indexCount']*4
  assert vertex_start%64==0 and vertex_start<index_start<index_end<=len(data),name
  assert (index_start-vertex_start)%64==0 and item['indexCount']%3==0,name
  vertices=struct.unpack_from('<%sf'%((index_start-vertex_start)//4),data,vertex_start)
  indices=struct.unpack_from('<%sI'%item['indexCount'],data,index_start)
  assert all(math.isfinite(value) for value in vertices),name
  assert all(0<=index<(index_start-vertex_start)//64 for index in indices),name
  assert all(0<=vertices[i+12]<bone_count for i in range(0,len(vertices),16)),name
 for name in ('work_boots','pink_work_boots','white_sneakers','pink_white_sneakers'):
  item=wardrobe['items'][name]
  vertices=struct.unpack_from('<%sf'%((item['indexOffset']-item['vertexOffset'])//4),data,item['vertexOffset'])
  joints={int(vertices[i+12]) for i in range(0,len(vertices),16)}
  expected={stage_manifest['bones'].index(f'{end}_{side}_paw') for end in ('front','rear') for side in ('l','r')}
  assert joints==expected,(stage,name,joints)
 print('PASS:',manifest_path.name,len(wardrobe['items']),'stage-fitted map accessories, hashes and bounds')
