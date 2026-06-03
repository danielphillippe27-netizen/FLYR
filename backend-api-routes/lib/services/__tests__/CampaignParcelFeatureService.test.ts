import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  isLikelyInfrastructureParcelFeature,
  isResidentialParcelFeature,
} from '../../geo/parcelFilters';
import { reconstructParcelFragments } from '../../geo/parcelFragments';
import {
  BedrockCountryService,
  BEDROCK_CANADA_CONFIG,
  BEDROCK_NZ_CONFIG,
  BEDROCK_US_CONFIG,
} from '../BedrockCountryService';
import { BedrockUsService } from '../BedrockUsService';

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

  await test('PMTiles wrapped parcel longitudes are normalized before reconstruction', () => {
    const [parcel] = reconstructParcelFragments([
      {
        id: 'wrapped-parcel',
        geometry: rectangle(-78.7896, 43.9194, -78.7894, 43.9196),
        properties: { source: 'bedrock_pmtiles' },
        include: true,
      },
      {
        id: 'wrapped-parcel',
        geometry: rectangle(281.2104, 43.9194, 281.2106, 43.9196),
        properties: { source: 'bedrock_pmtiles' },
        include: true,
      },
    ]);

    assert.ok(parcel);
    const [minLon, , maxLon] = geometryBbox(parcel.geometry);
    assert.ok(minLon >= -180, `expected normalized min longitude, got ${minLon}`);
    assert.ok(maxLon <= 180, `expected normalized max longitude, got ${maxLon}`);
    const bbox = geometryBbox(parcel.geometry);
    assert.ok(Math.abs(bbox[0] - -78.7896) < 1e-9);
    assert.ok(Math.abs(bbox[1] - 43.9194) < 1e-9);
    assert.ok(Math.abs(bbox[2] - -78.7894) < 1e-9);
    assert.ok(Math.abs(bbox[3] - 43.9196) < 1e-9);
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

  await test('parcel infrastructure aliases are filtered without geometry work', () => {
    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: { lot_type: 'Road Allowance' },
    }), false);

    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: { property_use: 'Sidewalk Easement' },
    }), false);

    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: { municipal_use: 'Utility Corridor' },
    }), false);

    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: { path: true },
    }), false);
  });

  await test('residential parcels are not filtered out just because an address street contains Road', () => {
    assert.equal(isResidentialParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 1, 1),
      properties: {
        parcel_intent: 'Fee Simple Title',
        street_name: 'Pine Road',
        address_line: '100 Pathway Court',
      },
    }), true);
  });

  await test('unlabeled skinny right-of-way parcel geometry is treated as infrastructure', () => {
    assert.equal(isLikelyInfrastructureParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 0.00002, 0.002),
      properties: {},
    }), true);
  });

  await test('normal unlabeled residential parcel geometry is not treated as infrastructure', () => {
    assert.equal(isLikelyInfrastructureParcelFeature({
      type: 'Feature',
      geometry: rectangle(0, 0, 0.0004, 0.0004),
      properties: {},
    }), false);
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

  await test('Bedrock USA snapshots expose per-state parcel PMTiles metadata', () => {
    const service = new BedrockCountryService(BEDROCK_US_CONFIG);
    const snapshot = service.snapshotForCampaign(
      'campaign-id',
      1,
      scanMetric,
      { partitioning: { scheme: 'web_mercator_xyz', tile_z: 12 } },
      'TX'
    );

    assert.equal(
      snapshot.metadata?.tile_metrics?.parcels_pmtiles_key,
      'bedrock/usa/current/parcels/pmtiles_by_state/state=TX/parcels.pmtiles'
    );
    assert.equal(
      snapshot.s3_keys.parcels,
      'bedrock/usa/current/parcels/pmtiles_by_state/state=TX/parcels.pmtiles'
    );
  });

  await test('Bedrock USA provider only advertises full PMTiles coverage regions', () => {
    assert.equal(BedrockUsService.isUsRegion('TX'), true);
    assert.equal(BedrockUsService.isUsRegion('DC'), true);
    assert.equal(BedrockUsService.isUsRegion('PR'), false);
    assert.equal(BedrockUsService.isUsRegion('VI'), false);
  });

  await test('Bedrock New Zealand snapshots use the shared country provision metadata', () => {
    const service = new BedrockCountryService(BEDROCK_NZ_CONFIG);
    const snapshot = service.snapshotForCampaign(
      'campaign-id',
      1,
      scanMetric,
      {
        single_file_key: 'bedrock/new-zealand/current/addresses/parquet/addresses.spatial.parquet',
        partitioning: { scheme: 'single_file_spatial', tile_z: 12 },
      },
      'NZ'
    );

    assert.equal(snapshot.metadata?.tile_metrics?.bedrock_country_code, 'NZ');
    assert.equal(
      snapshot.metadata?.tile_metrics?.addresses_pmtiles_key,
      'bedrock/new-zealand/current/addresses/addresses.pmtiles'
    );
    assert.equal(
      snapshot.metadata?.tile_metrics?.buildings_geojson_key,
      'bedrock/new-zealand/current/buildings/buildings.geojson.gz'
    );
    assert.equal(snapshot.s3_keys.parcels, 'bedrock/new-zealand/current/parcels/parcels.pmtiles');
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

  await test('parcel metadata reconciliation promotes persisted parcels as bundle source of truth', () => {
    const sql = readFileSync(
      resolve(process.cwd(), '../supabase/migrations/20260529203000_reconcile_campaign_parcel_metadata.sql'),
      'utf8'
    );

    assert.match(sql, /parcel_enrichment_status[\s\S]*'ready'/);
    assert.match(sql, /parcel_source_id = COALESCE\(c\.parcel_source_id, 'campaign_parcels'\)/);
    assert.match(sql, /cmb\.counts->>'parcel_source'[\s\S]*'campaign_parcels'/);
    assert.match(sql, /is_current = FALSE/);
  });

  await test('PMTiles parcel fallback backfills campaign parcel state for downstream surfaces', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'lib/services/CampaignParcelFeatureService.ts'),
      'utf8'
    );

    assert.match(source, /function backfillResolvedPmtilesParcels/);
    assert.match(source, /from\('campaign_parcels'\)[\s\S]*\.upsert\(chunk, \{ onConflict: 'campaign_id,external_id' \}\)/);
    assert.match(source, /error\.code === '42P10'/);
    assert.match(source, /function insertMissingCampaignParcelRows/);
    assert.match(source, /function parcelStorageGeometry/);
    assert.match(source, /parcel_source_id:\s*'snapshot_pmtiles'/);
    assert.match(source, /backfilled \? 'campaign_parcels' : 'snapshot_pmtiles'/);
  });

  await test('legacy preloaded PMTiles parcel sets are repaired from snapshot PMTiles', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'lib/services/CampaignParcelFeatureService.ts'),
      'utf8'
    );

    assert.match(source, /function isLegacyPreloadedParcelSource/);
    assert.match(source, /parcel_source_id, parcel_enrichment_status, parcel_enrichment_debug/);
    assert.match(source, /snapshotParcels\.length > residentialPersistedParcels\.length/);
    assert.match(source, /Legacy preloaded parcel repair failed/);
  });

  await test('campaign parcel backfill has a database conflict target', () => {
    const sql = readFileSync(
      resolve(process.cwd(), '../supabase/migrations/20260601090000_ensure_campaign_parcels_external_unique.sql'),
      'utf8'
    );

    assert.match(sql, /PARTITION BY campaign_id,\s*external_id/);
    assert.match(sql, /CREATE UNIQUE INDEX campaign_parcels_campaign_external_id_uidx/);
    assert.match(sql, /\(campaign_id,\s*external_id\)/);
  });

  await test('Bedrock snapshot PMTiles parcel extraction does not require a gold parcel region', () => {
    const enrichmentSource = readFileSync(
      resolve(process.cwd(), 'lib/services/ParcelEnrichmentService.ts'),
      'utf8'
    );
    const snapshotAttemptIndex = enrichmentSource.indexOf('this.loadSnapshotPmtilesParcels');
    const regionMetadataIndex = enrichmentSource.lastIndexOf('const regionMetadata = getRegionMetadata(regionCode)');
    assert.ok(snapshotAttemptIndex > -1);
    assert.ok(regionMetadataIndex > -1);
    assert.ok(snapshotAttemptIndex < regionMetadataIndex);

    const provisionSource = readFileSync(
      resolve(process.cwd(), 'app/api/campaigns/provision/route.ts'),
      'utf8'
    );
    assert.match(provisionSource, /function snapshotHasStaticParcelPmtiles/);
    assert.match(provisionSource, /!params\.snapshotOnly && !isParcelRegionSupported/);
    assert.match(provisionSource, /hasPreparedLinkGeometryParcels \|\| isParcelRegionSupported\(regionCode\) \|\| hasSnapshotParcelPmtiles/);
  });

  await test('campaign parcel annotation reads address points from coordinate or geom columns', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'lib/services/CampaignParcelFeatureService.ts'),
      'utf8'
    );

    assert.match(source, /\.select\('id, coordinate, geom'\)/);
    assert.match(source, /function coordinatePairFromCoordinate/);
    assert.match(source, /function coordinatePairFromGeometry/);
    assert.doesNotMatch(source, /\.select\('id, lat, lon'\)/);
  });
}

void main();
