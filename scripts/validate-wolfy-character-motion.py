"""Audit the same two-bone skinning used by Metal, including every exported pose."""
from pathlib import Path
import json
import numpy as np
root=Path(__file__).resolve().parents[1]/'WolfGrid/Resources/WolfyV2'
for path in root.glob('*-manifest.json'):
 m=json.loads(path.read_text())
 if m.get('skinning')!='two-bone':continue
 data=np.fromfile(root/m['mesh'],dtype='<f4',count=m['vertices']*16).reshape(-1,16)
 positions=data[:,:4];jointA=data[:,12].astype(int);jointB=data[:,13].astype(int);weight=data[:,14,None]
 for name,clip in m['clips'].items():
  matrices=np.fromfile(root/clip['file'],dtype='<f4').reshape(clip['frames'],len(m['bones']),4,4).transpose(0,1,3,2)
  for pose in matrices:
   points=np.einsum('nij,nj->ni',pose[jointA],positions)*(1-weight)+np.einsum('nij,nj->ni',pose[jointB],positions)*weight
   assert np.isfinite(points).all()
   assert points[:,2].min()>-.011,(path.name,name,'below ground')
   assert np.abs(points[:,:3]).max()<6,(path.name,name,'exploded mesh')
 print('PASS:',path.name,'all animated vertices finite, bounded and above ground')
