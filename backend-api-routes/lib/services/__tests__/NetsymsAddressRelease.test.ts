import assert from 'node:assert/strict';
import { BedrockCountryService, BEDROCK_US_CONFIG, __bedrockCountryServiceTestHooks } from '../BedrockCountryService';

process.env.BEDROCK_US_ADDRESS_PREFIX='bedrock/usa/20261010-netsyms202605/addresses';
process.env.BEDROCK_US_ADDRESS_SOURCE='Netsyms Address Database 2026-05';
const metric={hits:0,scanned:0,bboxCandidates:0,seconds:0,queryEngine:'duckdb_parquet' as const,touchedTiles:0,timings:{}};
const snapshot=new BedrockCountryService(BEDROCK_US_CONFIG).snapshotForCampaign('fixture',3,metric,{partitioning:{scheme:'state'}},'NY');
assert.equal(snapshot.s3_keys.addresses,'bedrock/usa/20261010-netsyms202605/addresses/pmtiles_by_state/state=NY/addresses.pmtiles');
assert.equal(snapshot.s3_keys.buildings,'bedrock/usa/current/buildings/pmtiles_by_state/state=NY/buildings.pmtiles');
const metrics=snapshot.metadata?.tile_metrics as unknown as Record<string,unknown>;
assert.equal(metrics.addresses_parquet_prefix,'bedrock/usa/20261010-netsyms202605/addresses/parquet');
assert.equal(metrics.addresses_parquet_manifest_key,'bedrock/usa/20261010-netsyms202605/addresses/parquet-manifest.json');
assert.equal((metrics.sources as Record<string,string>).addresses,'Netsyms Address Database 2026-05');
const address=__bedrockCountryServiceTestHooks.normalizePmtilesAddress(BEDROCK_US_CONFIG,'fixture',{
  type:'Feature',geometry:{type:'Point',coordinates:[-73.82,40.71]},
  properties:{address_id:'netsyms:us:fixture',house_number:'1',street_name:'SEAM ST',unit:'APT 2',full_address:'1 SEAM ST APT 2 New York NY 10001',locality:'New York',region:'NY',postal_code:'10001',longitude:-73.828125,latitude:40.713},
});
assert.equal(address?.unit,'APT 2');
assert.deepEqual(address?.coordinate,{lon:-73.828125,lat:40.713});
assert.equal(address?.gers_id,'bedrock_us:netsyms:us:fixture');
console.log('PASS: mobile/Sales backend pins USA PMTiles and Parquet to the new address release and retains source coordinates, unit identity, and building source');
