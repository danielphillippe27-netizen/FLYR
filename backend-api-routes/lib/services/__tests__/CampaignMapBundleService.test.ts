import assert from 'node:assert/strict';
import {
  isStrictCampaignMapBundleLink,
  normalizeCampaignMapBundleLinksForClient,
  shouldRepairCampaignMapBundleLinks,
  shouldRefreshBundleForCacheVersion,
  shouldRefreshBundleFromPersistedParcels,
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
  shouldRefreshBundleForCacheVersion('canonical-map-bundle-v5'),
  false,
  'keeps bundles written by the current bundle cache version'
);

assert.equal(
  shouldRefreshBundleFromPersistedParcels({
    currentParcelFeatures: 115,
    currentParcelSource: 'snapshot_pmtiles',
    persistedParcelCount: 196,
  }),
  true,
  'refreshes a partial snapshot parcel bundle once persisted parcels arrive'
);

assert.equal(
  shouldRefreshBundleFromPersistedParcels({
    currentParcelFeatures: 196,
    currentParcelSource: 'campaign_parcels',
    persistedParcelCount: 196,
  }),
  false,
  'keeps a current bundle that already uses all persisted parcels'
);

assert.equal(
  shouldRefreshBundleFromPersistedParcels({
    currentParcelFeatures: 115,
    currentParcelSource: 'snapshot_pmtiles',
    persistedParcelCount: 0,
  }),
  false,
  'does not churn snapshot parcel bundles when no persisted parcel layer exists'
);

assert.equal(
  shouldRepairCampaignMapBundleLinks({
    linksStatus: 'pending_provision',
    linkCount: 0,
    addressCount: 24,
    buildingCount: 10,
  }),
  true,
  'repairs pending bundle links when address and building inputs exist'
);

assert.equal(
  shouldRepairCampaignMapBundleLinks({
    linksStatus: 'pending_provision',
    linkCount: 0,
    addressCount: 24,
    buildingCount: 0,
  }),
  false,
  'does not run link repair when there are no building inputs'
);

assert.equal(
  shouldRepairCampaignMapBundleLinks({
    linksStatus: 'stale_reused',
    linkCount: 12,
    addressCount: 24,
    buildingCount: 10,
  }),
  true,
  'repairs stale reused bundle links'
);

assert.equal(
  shouldRepairCampaignMapBundleLinks({
    linksStatus: 'client_fallback_required',
    linkCount: 0,
    addressCount: 24,
    buildingCount: 10,
  }),
  false,
  'does not repeatedly repair bundles that already fell back to client linking'
);

assert.equal(
  shouldRepairCampaignMapBundleLinks({
    linksStatus: 'ok',
    linkCount: 12,
    addressCount: 24,
    buildingCount: 10,
  }),
  false,
  'keeps bundles whose canonical links are already ready'
);

assert.equal(
  isStrictCampaignMapBundleLink({
    id: 'loose-nearest',
    building_id: 'building-1',
    address_id: 'address-1',
    match_type: 'nearest_building_15m',
    confidence: 0.4,
    distance_meters: 16,
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

const unmappedLinks = normalizeCampaignMapBundleLinksForClient(
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
  new Map()
);

assert.equal(
  unmappedLinks[0]?.building_id,
  '9d55f5ef-a4fd-4fc0-810e-6d36d13604af',
  'does not fall back to campaign_addresses.building_gers_id when the building row lookup is unavailable'
);

console.log('CampaignMapBundleService polished-cache freshness tests passed.');
