import assert from 'node:assert/strict';
import {
  applyLinksToFeatureCollections,
  applyParcelLinksToAddresses,
  canonicalizeCampaignMapBundleAddresses,
  canonicalizeCampaignMapBundleLinksForDisplay,
  canonicalizeCampaignMapBundleParcels,
  isStrictCampaignMapBundleLink,
  linksStatusForStoredLinks,
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
  true,
  'refreshes v5 bundles so duplicate address aliases are canonicalized'
);

assert.equal(
  shouldRefreshBundleForCacheVersion('canonical-map-bundle-v6'),
  true,
  'refreshes v6 bundles so multi-address parcels receive a primary address_id'
);

assert.equal(
  shouldRefreshBundleForCacheVersion('canonical-map-bundle-v7'),
  true,
  'refreshes v7 bundles so ordinal-only address labels are sanitized'
);

assert.equal(
  shouldRefreshBundleForCacheVersion('canonical-map-bundle-v8'),
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
  linksStatusForStoredLinks(
    [{
      id: 'legacy-null-source',
      building_id: 'overture:building:legacy',
      address_id: 'address-legacy',
      match_type: 'containment_suspect',
      link_source: 'auto',
      confidence: 0.7,
      distance_meters: 0,
      source_version: null,
    }],
    'current-link-source-version'
  ),
  'ok',
  'accepts legacy null-version links as current so PMTiles-backed campaigns do not run destructive repair'
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

assert.equal(
  isStrictCampaignMapBundleLink({
    id: 'contained-without-street-confidence',
    building_id: 'overture:building:contained',
    address_id: 'address-contained',
    match_type: 'containment_suspect',
    confidence: 0.7,
    distance_meters: 0,
  }),
  true,
  'keeps zero-distance containment_suspect links so Bedrock/Diamond containment links hydrate map selection'
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

const duplicateAddressBundle = canonicalizeCampaignMapBundleAddresses({
  type: 'FeatureCollection',
  features: [
    {
      type: 'Feature',
      id: 'b346a269-5f4c-46b7-bab6-cb601c4f02b6',
      geometry: { type: 'Point', coordinates: [-96.1, 32.1] },
      properties: {
        id: 'b346a269-5f4c-46b7-bab6-cb601c4f02b6',
        formatted: '2703 Addison Avenue, Addison, TX',
        house_number: '2703',
        street_name: 'Addison Avenue',
        locality: 'Addison',
        source: 'lambda',
      },
    },
    {
      type: 'Feature',
      id: '629f3b30-db06-4127-aa61-65e455c69b47',
      geometry: { type: 'Point', coordinates: [-96.1, 32.1] },
      properties: {
        id: '629f3b30-db06-4127-aa61-65e455c69b47',
        formatted: '2703 ADDISON AVE',
        house_number: '2703',
        street_name: 'ADDISON AVE',
        locality: 'Addison',
        source: 'lambda',
      },
    },
  ],
});

assert.equal(
  duplicateAddressBundle.addresses.features.length,
  1,
  'collapses display-equivalent address aliases'
);
assert.equal(
  duplicateAddressBundle.counts.duplicate_address_aliases,
  1,
  'reports duplicate alias count'
);
assert.deepEqual(
  duplicateAddressBundle.addresses.features[0]?.properties?.alias_address_ids,
  [
    '629f3b30-db06-4127-aa61-65e455c69b47',
    'b346a269-5f4c-46b7-bab6-cb601c4f02b6',
  ],
  'keeps alias ids on the canonical address feature'
);

const unitAddressBundle = canonicalizeCampaignMapBundleAddresses({
  type: 'FeatureCollection',
  features: [
    {
      type: 'Feature',
      id: 'unit-a',
      geometry: { type: 'Point', coordinates: [-96.1, 32.1] },
      properties: {
        id: 'unit-a',
        formatted: '2703 ADDISON AVE UNIT A',
        house_number: '2703',
        street_name: 'ADDISON AVE',
      },
    },
    {
      type: 'Feature',
      id: 'unit-b',
      geometry: { type: 'Point', coordinates: [-96.1, 32.1] },
      properties: {
        id: 'unit-b',
        formatted: '2703 ADDISON AVE UNIT B',
        house_number: '2703',
        street_name: 'ADDISON AVE',
      },
    },
  ],
});

assert.equal(
  unitAddressBundle.addresses.features.length,
  2,
  'keeps distinct units as distinct visible homes'
);

const ordinalOnlyAddressBundle = canonicalizeCampaignMapBundleAddresses({
  type: 'FeatureCollection',
  features: [
    {
      type: 'Feature',
      id: 'ordinal-only',
      geometry: { type: 'Point', coordinates: [-80.29, 25.67] },
      properties: {
        id: 'ordinal-only',
        formatted: '61ST',
        house_number: '61ST',
        house_number_label: '61ST',
        street_name: '61ST',
        locality: 'miami-dade',
        source: 'diamond',
      },
    },
    {
      type: 'Feature',
      id: 'ordinal-street-real-house',
      geometry: { type: 'Point', coordinates: [-80.28, 25.67] },
      properties: {
        id: 'ordinal-street-real-house',
        formatted: '11089 51st St',
        house_number: '11089',
        house_number_label: '11089',
        street_name: '51st St',
        locality: 'miami-dade',
        source: 'diamond',
      },
    },
  ],
});

assert.deepEqual(
  ordinalOnlyAddressBundle.addresses.features.map((feature) => ({
    id: feature.id,
    formatted: feature.properties?.formatted,
    house_number: feature.properties?.house_number,
    house_number_label: feature.properties?.house_number_label,
    street_name: feature.properties?.street_name,
  })),
  [
    {
      id: 'ordinal-only',
      formatted: null,
      house_number: null,
      house_number_label: null,
      street_name: null,
    },
    {
      id: 'ordinal-street-real-house',
      formatted: '11089 51st St',
      house_number: '11089',
      house_number_label: '11089',
      street_name: '51st St',
    },
  ],
  'drops ordinal-only house labels while keeping real house numbers on ordinal streets'
);

const duplicateDisplayLinks = canonicalizeCampaignMapBundleLinksForDisplay(
  [
    {
      id: 'duplicate-a',
      building_id: 'overture:building:duplicate',
      address_id: '629f3b30-db06-4127-aa61-65e455c69b47',
      match_type: 'containment_verified',
      confidence: 1,
      distance_meters: 0,
      unit_count: 2,
      is_multi_unit: true,
      building_class: 'multi_unit',
    },
    {
      id: 'duplicate-b',
      building_id: 'overture:building:duplicate',
      address_id: 'b346a269-5f4c-46b7-bab6-cb601c4f02b6',
      match_type: 'nearest_building_15m',
      confidence: 0.9,
      distance_meters: 3,
      unit_count: 2,
      is_multi_unit: true,
      building_class: 'multi_unit',
    },
  ],
  duplicateAddressBundle
);

assert.equal(duplicateDisplayLinks.length, 1, 'dedupes links by building plus display address');
assert.equal(
  duplicateDisplayLinks[0]?.address_id,
  '629f3b30-db06-4127-aa61-65e455c69b47',
  'rewrites duplicate display links to the canonical address id'
);
assert.equal(duplicateDisplayLinks[0]?.unit_count, 1, 'unit count follows display-distinct homes');
assert.equal(duplicateDisplayLinks[0]?.is_multi_unit, false, 'single visible duplicate group is not multi-unit');
assert.deepEqual(
  duplicateDisplayLinks[0]?.alias_address_ids,
  [
    '629f3b30-db06-4127-aa61-65e455c69b47',
    'b346a269-5f4c-46b7-bab6-cb601c4f02b6',
  ],
  'keeps link alias metadata additive'
);

const duplicateLinkedFeatures = applyLinksToFeatureCollections(
  {
    type: 'FeatureCollection',
    features: [
      {
        type: 'Feature',
        id: 'overture:building:duplicate',
        geometry: { type: 'Polygon', coordinates: [] },
        properties: {
          id: 'overture:building:duplicate',
          gers_id: 'overture:building:duplicate',
          units_count: 2,
        },
      },
    ],
  },
  duplicateAddressBundle.addresses,
  duplicateDisplayLinks
);

assert.deepEqual(
  duplicateLinkedFeatures.buildings.features[0]?.properties?.address_ids,
  ['629f3b30-db06-4127-aa61-65e455c69b47'],
  'building address_ids use canonical display links only'
);
assert.equal(
  duplicateLinkedFeatures.buildings.features[0]?.properties?.address_count,
  1,
  'building address_count uses display-distinct links'
);
assert.equal(
  duplicateLinkedFeatures.buildings.features[0]?.properties?.units_count,
  1,
  'building units_count is not inflated by raw duplicate aliases'
);

const duplicateParcelFeatures = canonicalizeCampaignMapBundleParcels(
  {
    type: 'FeatureCollection',
    features: [
      {
        type: 'Feature',
        id: 'campaign-parcel-1',
        geometry: { type: 'Polygon', coordinates: [] },
        properties: {
          id: 'campaign-parcel-1',
          parcel_id: 'parcel-1',
          address_id: 'b346a269-5f4c-46b7-bab6-cb601c4f02b6',
          address_ids: [
            'b346a269-5f4c-46b7-bab6-cb601c4f02b6',
            '629f3b30-db06-4127-aa61-65e455c69b47',
          ],
          parcel_confidence: 0.9,
          parcel_match_type: 'centroid_in_parcel',
        },
      },
    ],
  },
  duplicateAddressBundle
);

assert.deepEqual(
  duplicateParcelFeatures.features[0]?.properties?.address_ids,
  ['629f3b30-db06-4127-aa61-65e455c69b47'],
  'parcel address_ids collapse raw duplicate aliases to one canonical visible home'
);
assert.equal(
  duplicateParcelFeatures.features[0]?.properties?.address_id,
  '629f3b30-db06-4127-aa61-65e455c69b47',
  'parcel address_id is set to the primary canonical address so Mapbox feature-state can target the parcel'
);
assert.equal(
  duplicateParcelFeatures.features[0]?.properties?.parcel_address_count,
  1,
  'parcel address count follows display-distinct homes'
);

const duplicateParcelLinkedAddresses = applyParcelLinksToAddresses(
  duplicateAddressBundle.addresses,
  duplicateParcelFeatures
);

assert.equal(
  duplicateParcelLinkedAddresses.features[0]?.properties?.has_parcel_link,
  true,
  'canonical address features receive parcel-link metadata'
);
assert.equal(
  duplicateParcelLinkedAddresses.features[0]?.properties?.parcel_id,
  'parcel-1',
  'canonical address features expose the linked parcel id'
);

const townhomeLinks = canonicalizeCampaignMapBundleLinksForDisplay(
  [
    {
      id: 'unit-a-link',
      building_id: 'overture:building:townhome',
      address_id: 'unit-a',
      match_type: 'containment_verified',
      confidence: 1,
      distance_meters: 0,
      building_class: 'townhouse',
    },
    {
      id: 'unit-b-link',
      building_id: 'overture:building:townhome',
      address_id: 'unit-b',
      match_type: 'containment_verified',
      confidence: 1,
      distance_meters: 0,
      building_class: 'townhouse',
    },
  ],
  unitAddressBundle
);

assert.equal(townhomeLinks.length, 2, 'keeps true townhome units linked separately');
assert.deepEqual(
  townhomeLinks.map((link) => [link.address_id, link.unit_count, link.is_multi_unit, link.building_class]),
  [
    ['unit-a', 2, true, 'townhouse'],
    ['unit-b', 2, true, 'townhouse'],
  ],
  'preserves multi-unit metadata for distinct visible townhomes'
);

console.log('CampaignMapBundleService polished-cache freshness tests passed.');
