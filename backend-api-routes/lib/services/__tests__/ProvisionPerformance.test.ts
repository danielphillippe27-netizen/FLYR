import assert from 'node:assert/strict';
import {
  ProvisionTimingRecorder,
  buildAutoBuildingLinksFromMemory,
  buildAutoBuildingLinksFromPreparedRows,
  buildParcelAddressLinksFromPreparedRows,
  prepareBuildingsFromRows,
} from '../ProvisionPerformance';

const campaignId = '00000000-0000-0000-0000-000000000001';

function rectangle(
  id: string,
  minLon: number,
  minLat: number,
  maxLon: number,
  maxLat: number
): GeoJSON.Feature<GeoJSON.Polygon> {
  return {
    type: 'Feature',
    properties: { gers_id: id, building_id: id },
    geometry: {
      type: 'Polygon',
      coordinates: [[
        [minLon, minLat],
        [maxLon, minLat],
        [maxLon, maxLat],
        [minLon, maxLat],
        [minLon, minLat],
      ]],
    },
  };
}

function pointAddress(id: string, lon: number, lat: number) {
  return {
    id,
    coordinate: { lon, lat },
  };
}

async function test(name: string, fn: () => void | Promise<void>) {
  try {
    await fn();
    console.log(`✓ ${name}`);
  } catch (error: unknown) {
    console.error(`✗ ${name}`);
    console.error(`  ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}

async function main() {
  await test('timing helper records successful async stages', async () => {
    const recorder = new ProvisionTimingRecorder();
    const result = await recorder.measure('source_resolution_ms', async () => 42);
    recorder.count('addresses_inserted', 7);
    const snapshot = recorder.snapshot();

    assert.equal(result, 42);
    assert.equal(snapshot.version, 1);
    assert.ok(snapshot.total_ms >= 0);
    assert.ok(snapshot.stages.source_resolution_ms >= 0);
    assert.equal(snapshot.counts.addresses_inserted, 7);
  });

  await test('timing helper records failed async stages without swallowing errors', async () => {
    const recorder = new ProvisionTimingRecorder();
    await assert.rejects(
      recorder.measure('address_insert_ms', async () => {
        throw new Error('insert failed');
      }),
      /insert failed/
    );

    assert.ok(recorder.snapshot().stages.address_insert_ms >= 0);
  });

  await test('bucketed linker matches flat scan for inside, nearby, outside, and boundary cases', () => {
    const buildings = prepareBuildingsFromRows([
      {
        id: 'building-a',
        gers_id: 'a',
        geom: rectangle('a', -111.90050, 33.50000, -111.90030, 33.50020).geometry,
        height_m: 4,
      },
      {
        id: 'building-b',
        gers_id: 'b',
        geom: rectangle('b', -111.89910, 33.50000, -111.89890, 33.50020).geometry,
        height_m: 5,
      },
      {
        id: 'building-boundary',
        gers_id: 'boundary',
        geom: rectangle('boundary', -111.90001, 33.50099, -111.89991, 33.50109).geometry,
        height_m: 6,
      },
    ]);
    const addresses = [
      pointAddress('inside', -111.90040, 33.50010),
      pointAddress('nearby', -111.89920, 33.50010),
      pointAddress('outside', -111.89500, 33.50010),
      pointAddress('boundary', -111.90000, 33.50100),
    ];

    const bucketed = buildAutoBuildingLinksFromPreparedRows({
      campaignId,
      addresses,
      buildings,
      useSpatialBuckets: true,
    });
    const flat = buildAutoBuildingLinksFromPreparedRows({
      campaignId,
      addresses,
      buildings,
      useSpatialBuckets: false,
    });

    assert.deepEqual(
      bucketed.map((link) => [link.address_id, link.building_id]),
      flat.map((link) => [link.address_id, link.building_id])
    );
    assert.deepEqual(
      bucketed.map((link) => link.address_id).sort(),
      ['boundary', 'inside', 'nearby']
    );
    assert.equal(bucketed.find((link) => link.address_id === 'inside')?.match_type, 'containment_verified');
    assert.equal(bucketed.find((link) => link.address_id === 'inside')?.confidence, 1);
  });

  await test('memory linker skips duplicate source features and unknown gers ids', () => {
    const sourceBuildings = [
      rectangle('known', -111.90050, 33.50000, -111.90030, 33.50020),
      rectangle('known', -111.90060, 33.50000, -111.90040, 33.50020),
      rectangle('unknown', -111.89910, 33.50000, -111.89890, 33.50020),
    ];
    const links = buildAutoBuildingLinksFromMemory({
      campaignId,
      addresses: [pointAddress('address-1', -111.90040, 33.50010)],
      materializedBuildings: [{ id: 'building-known', gers_id: 'known' }],
      sourceBuildings,
    });

    assert.equal(links.length, 1);
    assert.equal(links[0].building_id, 'building-known');
  });

  await test('canonical linker drops tiny and accessory building footprints', () => {
    const tinyBuildings = prepareBuildingsFromRows([
      {
        id: 'tiny-building',
        gers_id: 'tiny',
        geom: rectangle('tiny', -111.90050, 33.50000, -111.90045, 33.50005).geometry,
      },
      {
        id: 'garage-building',
        gers_id: 'garage',
        building_type: 'garage',
        geom: rectangle('garage', -111.90090, 33.50000, -111.90070, 33.50020).geometry,
      },
    ]);

    assert.equal(tinyBuildings.length, 0);

    const memoryLinks = buildAutoBuildingLinksFromMemory({
      campaignId,
      addresses: [pointAddress('garage-address', -111.90080, 33.50010)],
      materializedBuildings: [{ id: 'garage-building', gers_id: 'garage' }],
      sourceBuildings: [{
        ...rectangle('garage', -111.90090, 33.50000, -111.90070, 33.50020),
        properties: { gers_id: 'garage', building_type: 'garage' },
      }],
    });

    assert.equal(memoryLinks.length, 0);
  });

  await test('parcel bridge links an address to a same-parcel building beyond distance gate', () => {
    const buildings = prepareBuildingsFromRows([
      {
        id: 'building-on-parcel',
        gers_id: 'parcel-building',
        geom: rectangle('parcel-building', -111.90090, 33.50000, -111.90075, 33.50015).geometry,
        height_m: 5,
      },
    ]);

    const links = buildAutoBuildingLinksFromPreparedRows({
      campaignId,
      addresses: [pointAddress('parcel-address', -111.89870, 33.50160)],
      buildings,
      parcels: [{
        id: 'parcel-row-1',
        externalId: 'parcel-1',
        geometry: rectangle('parcel-1', -111.90120, 33.49980, -111.89840, 33.50190).geometry,
      }],
    });

    assert.equal(links.length, 1);
    assert.equal(links[0].address_id, 'parcel-address');
    assert.equal(links[0].building_id, 'building-on-parcel');
    assert.equal(links[0].match_type, 'parcel_bridge');
    assert.equal(links[0].link_source, 'auto_parcel');
  });

  await test('proximity rejects ambiguous nearest buildings inside the 15m cap', () => {
    const buildings = prepareBuildingsFromRows([
      {
        id: 'building-a',
        geom: rectangle('a', -111.90050, 33.50000, -111.90040, 33.50010).geometry,
      },
      {
        id: 'building-b',
        geom: rectangle('b', -111.90030, 33.50000, -111.90020, 33.50010).geometry,
      },
    ]);

    const links = buildAutoBuildingLinksFromPreparedRows({
      campaignId,
      addresses: [pointAddress('ambiguous', -111.90035, 33.50005)],
      buildings,
    });

    assert.equal(links.length, 0);
  });

  await test('proximity does not claim the same single-unit building twice', () => {
    const buildings = prepareBuildingsFromRows([
      {
        id: 'single-unit',
        geom: rectangle('single', -111.90050, 33.50000, -111.90040, 33.50010).geometry,
      },
    ]);

    const links = buildAutoBuildingLinksFromPreparedRows({
      campaignId,
      addresses: [
        pointAddress('first', -111.90055, 33.50005),
        pointAddress('second', -111.90056, 33.50005),
      ],
      buildings,
    });

    assert.deepEqual(links.map((link) => link.address_id), ['first']);
  });

  await test('proximity allows repeated links to known multi-unit buildings', () => {
    const buildings = prepareBuildingsFromRows([
      {
        id: 'multi-unit',
        units_count: 2,
        geom: rectangle('multi', -111.90050, 33.50000, -111.90040, 33.50010).geometry,
      },
    ]);

    const links = buildAutoBuildingLinksFromPreparedRows({
      campaignId,
      addresses: [
        pointAddress('first', -111.90055, 33.50005),
        pointAddress('second', -111.90056, 33.50005),
      ],
      buildings,
    });

    assert.deepEqual(links.map((link) => link.address_id), ['first', 'second']);
  });

  await test('parcel address links persist smallest containing parcel evidence', () => {
    const links = buildParcelAddressLinksFromPreparedRows({
      campaignId,
      addresses: [pointAddress('parcel-address', -111.89900, 33.50100)],
      parcels: [
        {
          id: 'outer-parcel',
          externalId: 'outer',
          geometry: rectangle('outer', -111.90120, 33.49980, -111.89840, 33.50190).geometry,
        },
        {
          id: 'inner-parcel',
          externalId: 'inner',
          geometry: rectangle('inner', -111.89920, 33.50080, -111.89880, 33.50120).geometry,
        },
      ],
    });

    assert.equal(links.length, 1);
    assert.equal(links[0].address_id, 'parcel-address');
    assert.equal(links[0].parcel_id, 'inner-parcel');
    assert.equal(links[0].match_type, 'centroid_in_parcel');
    assert.equal(links[0].confidence, 0.9);
  });
}

void main();
