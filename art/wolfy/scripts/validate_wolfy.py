import bpy,json,hashlib
from pathlib import Path
from pxr import Usd,UsdSkel
root=Path(__file__).resolve().parents[3];out=root/'WolfGrid/Resources/Wolfy'
m=json.loads((out/'wolfy_manifest.json').read_text())
assert 20000<=m['triangles']<=45000
assert len(m['animations'])==28 and len(m['items'])==25
assert len(m['sockets'])==12
checks=[]
for name,info in m['files'].items():
 p=out/name;assert hashlib.sha256(p.read_bytes()).hexdigest()==info['sha256']
 stage=Usd.Stage.Open(str(p));assert stage
 skeletons=[p for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton)]
 assert skeletons, name+' missing skeleton'
 if name.startswith('wolfy_') and name!='wolfy_base.usdz':
  animations=[p for p in stage.Traverse() if p.IsA(UsdSkel.Animation)]
  assert animations,name+' missing animation'
  assert any(len(UsdSkel.Animation(p).GetRotationsAttr().GetTimeSamples())>1 for p in animations),name+' static animation'
 checks.append(name)
(root/'art/wolfy/manifests/validation.json').write_text(json.dumps({'validated':checks,'triangles':m['triangles'],'clips':28,'items':25},indent=2))
print('PASS',len(checks),'USDZ hashes, skeletons and animation samples')
