import assert from 'node:assert/strict';
import {
  isStrictCampaignMapBundleLink,
  normalizeCampaignMapBundleLinksForClient,
  shouldRefreshBundleForCacheVersion,
  shouldRefreshBundleFromPolishedCache,
} from '../CampaignMapBundleService';

const staleBundleTimestamp = '2026-05-29T11:53:35.878Z';
const polishedCacheTimestamp = '2026-05-29T11:53:36.063Z';

assert.equal(
  shouldRefreshBundleFromPolishedCache({
    currentBuildingFeatures: 8,
    currentBuildingsFetchedAt: staleBundleTimestamp,
    polishedFeatureCount: 92,
    polishedUpdatedAt: polishedCacheTimestamp,
  }),
  true,
  'refreshes when the polished cache has more buildings than the current bundle'
);

assert.equal(
  shouldRefreshBundleFromPolishedCache({
    currentBuildingFeatures: 92,
    currentBuildingsFetchedAt: polishedCacheTimestamp,
    polishedFeatureCount: 92,
    polishedUpdatedAt: polishedCacheTimestamp,
  }),
  false,
  'keeps a current bundle that already matches the polished cache count'
);

assert.equal(
  shouldRefreshBundleFromPolishedCache({
    currentBuildingFeatures: 8,
    currentBuildingsFetchedAt: staleBundleTimestamp,
    polishedFeatureCount: 0,
    polishedUpdatedAt: polishedCacheTimestamp,
  }),
  false,
  'ignores empty polished cache metadata'
);

assert.equal(
  shouldRefreshBundleForCacheVersion(null),
  true,
  'refreshes old bundles that do not carry the current cache version'
);

assert.equal(
  shouldRefreshBundleForCacheVersion('canonical-map-bundle-v3'),
  false,
  'keeps bundles written by the current bundle cache version'
);

assert.equal(
  isStrictCampaignMapBundleLink({
    id: 'loose-nearest',
    building_id: 'building-1',
    address_id: 'address-1',
    match_type: 'nearest_building_15m',
    confidence: 0.4,
    distance_meters: 9,
  }),
  false,
  'rejects loose nearest-building links from the canonical map bundle'
);

const normalizedLinks = normalizeCampaignMapBundleLinksForClient(
  [
    {
      id: 'weak',
      building_id: '8e6c6457-cf84-4979-a2aa-ff6c1b30c578',
      address_id: 'address-1',
      match_type: 'nearest_building_15m',
      confidence: 0.7,
      distance_meters: 7,
    },
    {
      id: 'strong',
      building_id: '8e6c6457-cf84-4979-a2aa-ff6c1b30c578',
      address_id: 'address-1',
      match_type: 'containment_verified',
      confidence: 1,
      distance_meters: 0,
    },
  ],
  new Map([['8e6c6457-cf84-4979-a2aa-ff6c1b30c578', 'overture:building:abc']])
);

assert.deepEqual(
  normalizedLinks.map((link) => [link.id, link.building_id, link.address_id]),
  [['strong', 'overture:building:abc', 'address-1']],
  'normalizes internal building row ids to public map ids and keeps the best link per address'
);

const embeddedFallbackLinks = normalizeCampaignMapBundleLinksForClient(
  [
    {
      id: 'internal-only',
      building_id: '9d55f5ef-a4fd-4fc0-810e-6d36d13604af',
      address_id: 'address-2',
      match_type: 'containment_verified',
      confidence: 1,
      distance_meters: 0,
    },
  ],
  new Map(),
  [
    {
      id: 'embedded',
      building_id: 'overture:building:def',
      address_id: 'address-2',
      match_type: 'auto',
      confidence: 0.9,
      distance_meters: 0,
    },
  ]
);

assert.equal(
  embeddedFallbackLinks[0]?.building_id,
  'overture:building:def',
  'falls back to campaign_addresses.building_gers_id when the building row lookup is unavailable'
);

console.log('CampaignMapBundleService polished-cache freshness tests passed.');
