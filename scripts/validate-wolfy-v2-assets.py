"""Validate GPU prototype bounds, integrity and motion before loading on device."""
import json, struct, hashlib, math
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'WolfGrid/Resources/WolfyV2'
for manifest in sorted(root.glob('*-manifest.json')):
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
