import { BedrockUkService } from '@/lib/services/BedrockUkService';

const smokeSize = process.env.BEDROCK_UK_SMOKE_SIZE === 'large' ? 'large' : 'small';
const smokeBounds =
  smokeSize === 'large'
    ? [-0.155, 51.493, -0.105, 51.519]
    : [-0.145, 51.505, -0.135, 51.512];

const polygon: GeoJSON.Polygon = {
  type: 'Polygon',
  coordinates: [[
    [smokeBounds[0], smokeBounds[1]],
    [smokeBounds[2], smokeBounds[1]],
    [smokeBounds[2], smokeBounds[3]],
    [smokeBounds[0], smokeBounds[3]],
    [smokeBounds[0], smokeBounds[1]],
  ]],
};

async function main() {
  const campaignId = `bedrock-uk-london-smoke-${Date.now()}`;
  const result = await BedrockUkService.provisionCampaign({
    campaignId,
    polygon,
    addressLimit: 10000,
    regionCode: 'GB',
  });

  const tileMetrics = result.snapshot.metadata?.tile_metrics as Record<string, unknown> | undefined;

  if (result.addresses.length === 0) {
    throw new Error('BEDROCK UK smoke returned zero UPRN anchors for the London polygon');
  }
  if (tileMetrics?.bedrock_country !== 'uk' || tileMetrics?.bedrock_country_code !== 'GB') {
    throw new Error(`Unexpected BEDROCK UK snapshot metadata: ${JSON.stringify(tileMetrics)}`);
  }
  if (!result.snapshot.s3_keys?.addresses?.includes('/addresses/addresses.pmtiles')) {
    throw new Error(`Unexpected address PMTiles key: ${result.snapshot.s3_keys?.addresses}`);
  }
  if (!result.snapshot.s3_keys?.buildings?.includes('/buildings/buildings.pmtiles')) {
    throw new Error(`Unexpected building PMTiles key: ${result.snapshot.s3_keys?.buildings}`);
  }

  const samples = result.addresses.slice(0, 5).map((address) => ({
    gers_id: address.gers_id,
    region: address.region,
    lat: address.lat,
    lon: address.lon,
  }));

  console.log(JSON.stringify({
    smoke_size: smokeSize,
    bbox: smokeBounds,
    campaign_id: campaignId,
    address_count: result.addresses.length,
    scanned: result.metrics.addresses.scanned,
    touched_tiles: result.metrics.addresses.touchedTiles,
    scan_seconds: result.metrics.addresses.seconds,
    partitioning: result.metrics.addresses.partitioning,
    tile_padding: result.metrics.addresses.tilePadding,
    snapshot: {
      bucket: result.snapshot.bucket,
      prefix: result.snapshot.prefix,
      buildings_key: result.snapshot.s3_keys?.buildings,
      addresses_key: result.snapshot.s3_keys?.addresses,
      metadata_key: result.snapshot.s3_keys?.metadata,
      bedrock_country: tileMetrics?.bedrock_country,
      bedrock_country_code: tileMetrics?.bedrock_country_code,
      addresses_parquet_prefix: tileMetrics?.addresses_parquet_prefix,
    },
    samples,
  }, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
