import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { isResidentialParcelFeature } from '../../geo/parcelFilters';
import { reconstructParcelFragments } from '../../geo/parcelFragments';
import { BedrockCountryService, BEDROCK_CANADA_CONFIG } from '../BedrockCountryService';

function rectangle(minLon: number, minLat: number, maxLon: number, maxLat: number): GeoJSON.Polygon {
  return {
    type: 'Polygon',
    coordinates: [[
      [minLon, minLat],
      [maxLon, minLat],
      [maxLon, maxLat],
      [minLon, maxLat],
      [minLon, minLat],
    ]],
  };
}

function collectPositions(geometry: GeoJSON.Polygon | GeoJSON.MultiPolygon): Array<[number, number]> {
  if (geometry.type === 'Polygon') return geometry.coordinates.flat() as Array<[number, number]>;
  return geometry.coordinates.flat(2) as Array<[number, number]>;
}

function geometryBbox(geometry: GeoJSON.Polygon | GeoJSON.MultiPolygon): [number, number, number, number] {
  const positions = collectPositions(geometry);
  return [
    Math.min(...positions.map((position) => position[0])),
    Math.min(...positions.map((position) => position[1])),
    Math.max(...positions.map((position) => position[0])),
    Math.max(...positions.map((position) => position[1])),
  ];
}

const scanMetric = {
  hits: 0,
  scanned: 0,
  bboxCandidates: 0,
  seconds: 0,
  queryEngine: 'duckdb_parquet' as const,
  touchedTiles: 0,
  timings: {
    manifestMs: 0,
    partitionMs: 0,
    queryMs: 0,
    filterMs: 0,
    totalMs: 0,
  },
};

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
  await test('PMTiles fragments with the same parcel id render as the full reconstructed parcel', () => {
    const [parcel] = reconstructParcelFragments([
      {
        id: 'parcel-1',
        geometry: rectangle(0, 0, 1, 1),
        properties: { source: 'bedrock_pmtiles' },
        include: true,
      },
      {
        id: 'parcel-1',
        geometry: rectangle(1, 0, 2, 1),
        properties: { source: 'bedrock_pmtiles' },
        include: false,
      },
    ]);

    assert.ok(parcel);
    assert.equal(parcel.properties?.parcel_id, 'parcel-1');
    assert.deepEqual(geometryBbox(parcel.geometry), [0, 0, 2, 1]);
  });

  await test('PMTiles fragment groups are excluded when no fragment overlaps the lasso polygon', () => {
    const parcels = reconstructParcelFragments([
      {
        id: 'outside-parcel',
        geometry: rectangle(5, 5, 6, 6),
        properties: { source: 'bedrock_pmtiles' },
        include: false,
      },
      {
        id: 'outside-parcel',
        geometry: rectangle(6, 5, 7, 6),
        properties: { source: 'bedrock_pmtiles' },
        include: false,
      },
    ]);

    assert.deepEqual(parcels, []);
  });

  await test('road, right-of-way, and pedestrian parcel classifications are filtered out', () => {
    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: { parcel_type: 'Road Reserve' },
    }), false);

    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: { legal_type: 'right_of_way corridor' },
    }), false);

    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: { parcel_type: 'Sidewalk Reserve' },
    }), false);

    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: { purpose: 'Shared-use path' },
    }), false);

    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: { sidewalk: true },
    }), false);
  });

  await test('residential parcels are not filtered out just because an address street contains Road', () => {
    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: {
        parcel_intent: 'Fee Simple Title',
        street_name: 'Pine Road',
      },
    }), true);
  });

  await test('Bedrock Canada snapshots expose parcel PMTiles metadata', () => {
    const service = new BedrockCountryService(BEDROCK_CANADA_CONFIG);
    const snapshot = service.snapshotForCampaign(
      'campaign-id',
      1,
      scanMetric,
      { partitioning: { scheme: 'web_mercator_xyz', tile_z: 12 } },
      'BC'
    );

    assert.equal(
      snapshot.metadata?.tile_metrics?.parcels_pmtiles_key,
      'bedrock/canada/current/parcels/parcels.pmtiles'
    );
    assert.equal(snapshot.s3_keys.parcels, 'bedrock/canada/current/parcels/parcels.pmtiles');
  });

  await test('persisted parcel RPC selects by intersection without clipping stored geometry', () => {
    const sql = readFileSync(
      resolve(process.cwd(), '../supabase/migrations/20260513190000_add_campaign_parcels_geojson_rpc.sql'),
      'utf8'
    );

    assert.match(sql, /ST_Intersects\(p\.geom,\s*v_boundary\)/);
    assert.match(sql, /ST_AsGeoJSON\(geom\)::jsonb/);
    assert.doesNotMatch(sql, /ST_Intersection/i);
  });
}

void main();
