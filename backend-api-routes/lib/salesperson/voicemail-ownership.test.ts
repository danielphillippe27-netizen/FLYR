import assert from 'node:assert/strict';
import test from 'node:test';
import { signPersonalVoicemailDrop } from '../dialer/voicemail-drops';

test('voicemail playback requires both personal row and object ownership', async () => {
  const signed: unknown[] = [];
  const admin = { storage: { from(bucket: string) { return { async createSignedUrl(path: string, ttl: number) {
    signed.push([bucket, path, ttl]); return { data: { signedUrl: 'short-lived-playback' }, error: null };
  } }; } } };
  const row = { workspace_id:'workspace', user_id:'hughes', storage_bucket:'dialer-voicemail-drops', storage_path:'workspace/hughes/recording.mp3', public_url:'old-public-url' };
  assert.equal((await signPersonalVoicemailDrop(admin as any,row as any,'workspace','hughes')).public_url,'short-lived-playback');
  for (const bad of [
    {...row,user_id:'phillippe'}, {...row,workspace_id:'other'},
    {...row,storage_path:'workspace/phillippe/recording.mp3'},
    {...row,storage_bucket:'other'},
  ]) await assert.rejects(signPersonalVoicemailDrop(admin as any,bad as any,'workspace','hughes'),/ownership/);
  assert.equal(signed.length,1);
  assert.deepEqual(signed[0],['dialer-voicemail-drops','workspace/hughes/recording.mp3',900]);
});
