import assert from 'node:assert/strict';
import test from 'node:test';

import { resolveCampaignRegion } from '../regionResolver';

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

async function withoutMapboxToken<T>(fn: () => Promise<T>): Promise<T> {
  const mapboxToken = process.env.MAPBOX_TOKEN;
  const nextPublicMapboxToken = process.env.NEXT_PUBLIC_MAPBOX_TOKEN;
  delete process.env.MAPBOX_TOKEN;
  delete process.env.NEXT_PUBLIC_MAPBOX_TOKEN;
  try {
    return await fn();
  } finally {
    if (mapboxToken == null) {
      delete process.env.MAPBOX_TOKEN;
    } else {
      process.env.MAPBOX_TOKEN = mapboxToken;
    }
    if (nextPublicMapboxToken == null) {
      delete process.env.NEXT_PUBLIC_MAPBOX_TOKEN;
    } else {
      process.env.NEXT_PUBLIC_MAPBOX_TOKEN = nextPublicMapboxToken;
    }
  }
}

test('Cape Town bbox resolves to Western Cape instead of country-level South Africa', async () => {
  const result = await withoutMapboxToken(() =>
    resolveCampaignRegion({
      polygon: rectangle(18.38, -33.95, 18.48, -33.88),
    })
  );

  assert.equal(result.regionCode, 'WC');
  assert.equal(result.source, 'bbox');
  assert.equal(result.shouldPersist, true);
  assert.equal(result.reason, 'missing');
});

test('country-level ZA campaign regions are refined from the campaign polygon', async () => {
  const result = await withoutMapboxToken(() =>
    resolveCampaignRegion({
      currentRegion: 'ZA',
      polygon: rectangle(18.38, -33.95, 18.48, -33.88),
    })
  );

  assert.equal(result.regionCode, 'WC');
  assert.equal(result.source, 'bbox');
  assert.equal(result.shouldPersist, true);
  assert.equal(result.reason, 'country_default');
});
