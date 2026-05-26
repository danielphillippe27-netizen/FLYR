/**
 * StableLinkerService regression fixtures
 *
 * Run with: npx tsx lib/services/__tests__/StableLinkerService.test.ts
 */
/* eslint-disable @typescript-eslint/no-explicit-any */

import { DataIntegrityError, StableLinkerService } from '../StableLinkerService';
import { ParcelEnrichmentService } from '../ParcelEnrichmentService';

let testsPassed = 0;
let testsFailed = 0;

function test(name: string, fn: () => void) {
  try {
    fn();
    console.log(`✓ ${name}`);
    testsPassed++;
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`✗ ${name}`);
    console.error(`  ${message}`);
    testsFailed++;
  }
}

async function testAsync(name: string, fn: () => Promise<void>) {
  try {
    await fn();
    console.log(`✓ ${name}`);
    testsPassed++;
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`✗ ${name}`);
    console.error(`  ${message}`);
    testsFailed++;
  }
}

function assertEqual(actual: unknown, expected: unknown, message?: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(message || `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function assertTrue(condition: boolean, message?: string) {
  if (!condition) {
    throw new Error(message || 'Expected true, got false');
  }
}

function rectangle(minLon: number, minLat: number, maxLon: number, maxLat: number): number[][] {
  return [
    [minLon, minLat],
    [maxLon, minLat],
    [maxLon, maxLat],
    [minLon, maxLat],
    [minLon, minLat],
  ];
}

function makeBuilding(
  id: string,
  ring: number[][],
  options: {
    primaryStreet?: string | null;
    streetName?: string | null;
    name?: string | null;
    houseNumber?: string | null;
    addressText?: string | null;
  } = {}
) {
  return {
    type: 'Feature' as const,
    geometry: {
      type: 'Polygon' as const,
      coordinates: [ring],
    },
    properties: {
      gers_id: id,
      name: options.name ?? null,
      height: null,
      layer: 'building',
      primary_street: options.primaryStreet ?? null,
      street_name: options.streetName ?? null,
      house_number: options.houseNumber ?? null,
      address_text: options.addressText ?? null,
    },
  };
}

function makeParcel(externalId: string, ring: number[][]) {
  return {
    externalId,
    geometry: {
      type: 'MultiPolygon' as const,
      coordinates: [[ring]],
    },
  };
}

function makeAddress(id: string, lon: number, lat: number, streetName: string) {
  return {
    id,
    gers_id: null,
    formatted: `${streetName} ${id}`,
    house_number: id,
    street_name: streetName,
    geom: {
      type: 'Point' as const,
      coordinates: [lon, lat] as [number, number],
    },
  };
}

type MockState = {
  campaignAddresses?: Array<Record<string, unknown>>;
  addressOrphans?: Array<Record<string, unknown>>;
  buildingAddressLinks?: Array<Record<string, unknown>>;
};

class MockQueryBuilder implements PromiseLike<{ data: any; error: null }> {
  private operation: 'select' | 'update' | null = null;
  private filters = new Map<string, unknown>();
  private updateValues: Record<string, unknown> | null = null;
  private head = false;
  private fromIndex = 0;
  private toIndex: number | null = null;

  constructor(
    private readonly table: string,
    private readonly state: MockState
  ) {}

  select(_columns: string, options?: { head?: boolean }) {
    this.operation = 'select';
    this.head = !!options?.head;
    return this;
  }

  update(values: Record<string, unknown>) {
    this.operation = 'update';
    this.updateValues = values;
    return this;
  }

  insert(values: Record<string, unknown>) {
    if (this.table !== 'building_address_links') {
      return Promise.resolve({ data: null, error: null });
    }
    const rows = this.state.buildingAddressLinks ?? [];
    rows.push(values);
    this.state.buildingAddressLinks = rows;
    return Promise.resolve({ data: values, error: null });
  }

  eq(column: string, value: unknown) {
    this.filters.set(column, value);
    return this;
  }

  order(_column: string, _options?: { ascending?: boolean }) {
    return this;
  }

  range(from: number, to: number) {
    this.fromIndex = from;
    this.toIndex = to;
    return this.execute();
  }

  async single() {
    const result = await this.executeSelect();
    const row = (result.data as Array<Record<string, unknown>>)[0] ?? null;
    return { data: row, error: null };
  }

  then<TResult1 = { data: any; error: null }, TResult2 = never>(
    onfulfilled?: ((value: { data: any; error: null }) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: any) => TResult2 | PromiseLike<TResult2>) | null
  ): Promise<TResult1 | TResult2> {
    return this.execute().then(onfulfilled, onrejected);
  }

  private execute() {
    if (this.operation === 'update') {
      return this.executeUpdate();
    }
    return this.executeSelect();
  }

  private executeSelect() {
    const rows = this.getRows();
    const filtered = rows.filter((row) =>
      Array.from(this.filters.entries()).every(([column, value]) => row[column] === value)
    );
    const sliced = this.toIndex == null ? filtered : filtered.slice(this.fromIndex, this.toIndex + 1);
    if (this.head) {
      return Promise.resolve({ data: null, error: null, count: filtered.length } as any);
    }
    return Promise.resolve({ data: sliced, error: null });
  }

  private executeUpdate() {
    const rows = this.getRows();
    const filtered = rows.filter((row) =>
      Array.from(this.filters.entries()).every(([column, value]) => row[column] === value)
    );
    for (const row of filtered) {
      Object.assign(row, this.updateValues);
    }
    return Promise.resolve({ data: filtered, error: null });
  }

  private getRows(): Array<Record<string, unknown>> {
    switch (this.table) {
      case 'campaign_addresses':
        return this.state.campaignAddresses ?? [];
      case 'address_orphans':
        return this.state.addressOrphans ?? [];
      case 'building_address_links':
        return this.state.buildingAddressLinks ?? [];
      default:
        return [];
    }
  }
}

function createMockSupabase(state: MockState) {
  return {
    from(table: string) {
      return new MockQueryBuilder(table, state);
    },
  };
}

async function run() {
  console.log('Running StableLinkerService regression fixtures...\n');

  test('Gold exact: containment_verified wins for same-street address inside footprint', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'building-1',
      rectangle(-79.0002, 43.0000, -78.9998, 43.0003),
      { primaryStreet: 'Main Street' }
    );
    const address = makeAddress('100', -79.0000, 43.00015, 'Main Street');

    const match = (service as any).matchAddressToBuilding(address, [building], new Set(), []);
    assertEqual(match.matchType, 'containment_verified');
    assertEqual(match.buildingId, 'building-1');
  });

  test('Gold parcel bridge: address outside footprint still links via shared parcel', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'building-2',
      rectangle(-79.00020, 43.00000, -79.00005, 43.00018),
      { primaryStreet: 'Oak Avenue' }
    );
    const parcel = makeParcel('parcel-1', rectangle(-79.00030, 42.99995, -78.99990, 43.00028));
    const preparedParcels = (service as any).prepareParcelBridge([parcel], [building]);
    const address = makeAddress('200', -78.99998, 43.00016, 'Oak Avenue');

    const match = (service as any).matchAddressToBuilding(address, [building], new Set(), preparedParcels);
    assertEqual(match.matchType, 'parcel_verified');
    assertEqual(match.buildingId, 'building-2');
  });

  test('Silver parcel bridge: street_name-only buildings still participate in parcel matching', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'building-3',
      rectangle(-79.00120, 43.00100, -79.00105, 43.00118),
      { streetName: 'Pine Road' }
    );
    const parcel = makeParcel('parcel-2', rectangle(-79.00130, 43.00095, -79.00090, 43.00130));
    const preparedParcels = (service as any).prepareParcelBridge([parcel], [building]);
    const address = makeAddress('300', -79.00098, 43.00110, 'Pine Road');

    const match = (service as any).matchAddressToBuilding(address, [building], new Set(), preparedParcels);
    assertEqual(match.matchType, 'parcel_verified');
    assertEqual(match.buildingId, 'building-3');
  });

  test('Parcel bridge outranks point-on-surface for offset detached-home address points', () => {
    const service = new StableLinkerService({} as any);
    const parcelBuilding = makeBuilding(
      'parcel-main-home',
      rectangle(-79.00965, 43.01002, -79.00950, 43.01016),
      { primaryStreet: 'Cedar Court' }
    );
    const boundaryNeighbor = makeBuilding(
      'boundary-neighbor',
      rectangle(-79.01000, 43.01000, -79.00980, 43.01020),
      { primaryStreet: 'Cedar Court' }
    );
    const parcel = makeParcel(
      'parcel-main',
      rectangle(-79.00982, 43.00995, -79.00945, 43.01022)
    );
    const preparedParcels = (service as any).prepareParcelBridge([parcel], [parcelBuilding, boundaryNeighbor]);
    const address = makeAddress('302', -79.00980, 43.01010, 'Cedar Court');

    const match = (service as any).matchAddressToBuilding(
      address,
      [parcelBuilding, boundaryNeighbor],
      new Set(),
      preparedParcels
    );

    assertEqual(match.matchType, 'parcel_verified');
    assertEqual(match.buildingId, 'parcel-main-home');
  });

  test('Parcel bridge: building footprint vertex inside parcel is eligible even when centroid is outside', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'slightly-shifted-home',
      rectangle(-79.03080, 43.03000, -79.03055, 43.03018),
      { primaryStreet: 'Baylawn Drive' }
    );
    const parcel = makeParcel(
      'parcel-shifted',
      rectangle(-79.03062, 43.02995, -79.03035, 43.03025)
    );
    const preparedParcels = (service as any).prepareParcelBridge([parcel], [building]);
    const address = makeAddress('870', -79.03048, 43.03012, 'Baylawn Drive');

    const match = (service as any).matchAddressToBuilding(
      address,
      [building],
      new Set(),
      preparedParcels
    );

    assertEqual(match.matchType, 'parcel_verified');
    assertEqual(match.buildingId, 'slightly-shifted-home');
  });

  test('Strong linker: exact house number and street beats nearer neighboring footprint', () => {
    const service = new StableLinkerService({} as any);
    const exactHome = makeBuilding(
      'home-49',
      rectangle(-79.00480, 43.00400, -79.00465, 43.00415),
      { addressText: '49 Moyse Drive' }
    );
    const nearerNeighbor = makeBuilding(
      'home-51',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415),
      { addressText: '51 Moyse Drive' }
    );
    const address = makeAddress('49', -79.00412, 43.00408, 'Moyse Drive');

    const match = (service as any).matchAddressToBuilding(
      address,
      [nearerNeighbor, exactHome],
      new Set(),
      []
    );

    assertEqual(match.matchType, 'semantic_verified');
    assertEqual(match.buildingId, 'home-49');
  });

  test('Parcel source selection: locality-specific dataset beats region-wide fallback', () => {
    const service = new ParcelEnrichmentService({} as any);

    const resolution = (service as any).selectBestParcelDataset(
      ['burnaby'],
      [
        {
          sourceId: 'bc_parcels',
          key: 'gold-standard/canada/bc/bc_parcels/20260426/bc_parcels_gold.ndjson',
          datePart: '20260426',
          localityAliases: ['bc'],
          isRegionWide: true,
        },
        {
          sourceId: 'burnaby_parcels',
          key: 'gold-standard/canada/bc/burnaby_parcels/20260426/burnaby_parcels_gold.ndjson',
          datePart: '20260426',
          localityAliases: ['burnaby'],
          isRegionWide: false,
        },
      ]
    );

    assertEqual(resolution.dataset?.sourceId, 'burnaby_parcels');
    assertEqual(resolution.localityCounts, [{ source_id: 'burnaby_parcels', count: 1 }]);
    assertEqual(resolution.unsupportedLocalities, []);
  });

  test('Parcel source selection: region-wide dataset handles unsupported localities', () => {
    const service = new ParcelEnrichmentService({} as any);

    const resolution = (service as any).selectBestParcelDataset(
      ['vancouver'],
      [
        {
          sourceId: 'bc_parcels',
          key: 'gold-standard/canada/bc/bc_parcels/20260426/bc_parcels_gold.ndjson',
          datePart: '20260426',
          localityAliases: ['bc'],
          isRegionWide: true,
        },
        {
          sourceId: 'burnaby_parcels',
          key: 'gold-standard/canada/bc/burnaby_parcels/20260426/burnaby_parcels_gold.ndjson',
          datePart: '20260426',
          localityAliases: ['burnaby'],
          isRegionWide: false,
        },
      ]
    );

    assertEqual(resolution.dataset?.sourceId, 'bc_parcels');
    assertEqual(resolution.unsupportedLocalities, ['vancouver']);
  });

  test('Townhouse row: repeated building matches become multi-unit after post-processing', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'building-row',
      rectangle(-79.00220, 43.00200, -79.00180, 43.00230),
      { primaryStreet: 'Rowhouse Lane' }
    );

    const matches = [
      (service as any).matchAddressToBuilding(makeAddress('401', -79.00212, 43.00210, 'Rowhouse Lane'), [building], new Set(), []),
      (service as any).matchAddressToBuilding(makeAddress('403', -79.00200, 43.00215, 'Rowhouse Lane'), [building], new Set(), []),
      (service as any).matchAddressToBuilding(makeAddress('405', -79.00188, 43.00220, 'Rowhouse Lane'), [building], new Set(), []),
    ];

    (service as any).detectMultiUnitBuildings(matches);

    assertTrue(matches.every((match: any) => match.isMultiUnit), 'Expected all matches to be multi-unit');
    assertTrue(matches.every((match: any) => match.unitCount === 3), 'Expected unitCount=3 for townhouse row');
  });

  test('Detached fallback: weak proximity does not reuse an already matched building', () => {
    const service = new StableLinkerService({} as any);
    const alreadyMatched = makeBuilding(
      'detached-a',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415)
    );
    const unusedNeighbor = makeBuilding(
      'detached-b',
      rectangle(-79.00455, 43.00400, -79.00440, 43.00415)
    );
    const address = makeAddress('41', -79.00418, 43.00430, 'Moyse Drive');

    const match = (service as any).matchAddressToBuilding(
      address,
      [alreadyMatched, unusedNeighbor],
      new Set(['detached-a']),
      []
    );

    assertEqual(match.matchType, 'proximity_fallback');
    assertEqual(match.buildingId, 'detached-b');
  });

  test('Detached fallback: verified proximity does not reuse an already matched building', () => {
    const service = new StableLinkerService({} as any);
    const alreadyMatched = makeBuilding(
      'detached-a',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415),
      { primaryStreet: 'Highland Avenue' }
    );
    const unusedNeighbor = makeBuilding(
      'detached-b',
      rectangle(-79.00455, 43.00400, -79.00440, 43.00415),
      { primaryStreet: 'Highland Avenue' }
    );
    const address = makeAddress('324', -79.00418, 43.00430, 'Highland Avenue');

    const match = (service as any).matchAddressToBuilding(
      address,
      [alreadyMatched, unusedNeighbor],
      new Set(['detached-a']),
      []
    );

    assertEqual(match.matchType, 'proximity_fallback');
    assertEqual(match.buildingId, 'detached-b');
  });

  test('Nearby same-street address: relaxed proximity links up to 75m', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'nearby-home',
      rectangle(-79.01010, 43.01000, -79.00990, 43.01020),
      { primaryStreet: 'Maple Street' }
    );
    const address = makeAddress('600', -79.00920, 43.01010, 'Maple Street');

    const match = (service as any).matchAddressToBuilding(
      address,
      [building],
      new Set(),
      []
    );

    assertEqual(match.matchType, 'proximity_verified');
    assertEqual(match.buildingId, 'nearby-home');
  });

  test('Right-outside footprint address: footprint distance links even when centroid is far', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'wide-building',
      rectangle(-79.03400, 43.03000, -79.03000, 43.03100),
      { primaryStreet: 'Long Hall Road' }
    );
    const address = makeAddress('601', -79.02994, 43.03050, 'Long Hall Road');

    const match = (service as any).matchAddressToBuilding(
      address,
      [building],
      new Set(),
      []
    );

    assertEqual(match.matchType, 'proximity_verified');
    assertEqual(match.buildingId, 'wide-building');
    assertTrue(match.distanceMeters < 10, 'Expected footprint distance under 10m');
  });

  test('Right-outside footprint address: no street metadata still links by geometry', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'no-street-building',
      rectangle(-79.04020, 43.04000, -79.04000, 43.04020)
    );
    const address = makeAddress('601b', -79.03994, 43.04010, '');

    const match = (service as any).matchAddressToBuilding(
      address,
      [building],
      new Set(),
      []
    );

    assertEqual(match.matchType, 'proximity_verified');
    assertEqual(match.buildingId, 'no-street-building');
    assertTrue(match.distanceMeters < 10, 'Expected footprint distance under 10m');
    assertTrue(match.confidence >= 0.8, 'Expected high confidence from geometry alone');
  });

  test('Nearby fallback address: relaxed fallback links unused buildings up to 125m', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'fallback-home',
      rectangle(-79.02010, 43.02000, -79.01990, 43.02020)
    );
    const address = makeAddress('602', -79.01860, 43.02010, 'Fallback Road');

    const match = (service as any).matchAddressToBuilding(
      address,
      [building],
      new Set(),
      []
    );

    assertEqual(match.matchType, 'proximity_fallback');
    assertEqual(match.buildingId, 'fallback-home');
  });

  test('Detached fallback: weak proximity becomes orphan when every candidate is already matched', () => {
    const service = new StableLinkerService({} as any);
    const alreadyMatched = makeBuilding(
      'detached-only',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415)
    );
    const address = makeAddress('43', -79.00418, 43.00430, 'Moyse Drive');

    const match = (service as any).matchAddressToBuilding(
      address,
      [alreadyMatched],
      new Set(['detached-only']),
      []
    );

    assertEqual(match.matchType, 'orphan');
  });

  test('Address candidates: direct link to the current building is excluded from nearby candidates', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'municipal-buildings:39',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415),
      { primaryStreet: 'Moyse Drive' }
    );
    const selection = service.selectOfficialAddressCandidatesForBuilding({
      building: {
        rowId: 'building-39-row',
        publicId: 'municipal-buildings:39',
        geometry: building.geometry,
        streetName: 'Moyse Drive',
      },
      addressRows: [
        {
          id: '00000000-0000-0000-0000-000000000039',
          formatted: '39 Moyse Drive',
          house_number: '39',
          street_name: 'Moyse Drive',
          source: 'gold',
          building_id: null,
          building_gers_id: 'municipal-buildings:39',
          geom: {
            type: 'Point',
            coordinates: [-79.00403, 43.00408],
          },
        },
      ],
      linkRows: [],
      radiusMeters: 60,
      limit: 15,
    });

    assertEqual(selection.candidates.length, 0);
  });

  test('Address candidates: imported links to other nearby buildings remain eligible', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'municipal-buildings:39',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415),
      { primaryStreet: 'Moyse Drive' }
    );
    const selection = service.selectOfficialAddressCandidatesForBuilding({
      building: {
        rowId: 'building-39-row',
        publicId: 'municipal-buildings:39',
        geometry: building.geometry,
        streetName: 'Moyse Drive',
      },
      addressRows: [
        {
          id: '00000000-0000-0000-0000-000000000041',
          formatted: '41 Moyse Drive',
          house_number: '41',
          street_name: 'Moyse Drive',
          source: 'gold',
          building_id: null,
          building_gers_id: 'municipal-buildings:41',
          geom: {
            type: 'Point',
            coordinates: [-79.00403, 43.00408],
          },
        },
      ],
      linkRows: [],
      radiusMeters: 60,
      limit: 15,
    });

    assertEqual(selection.candidates.length, 1);
    assertEqual(selection.candidates[0].id, '00000000-0000-0000-0000-000000000041');
  });

  test('Address candidates: nearby unlinked address remains eligible without direct/link rows', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'building-41',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415),
      { primaryStreet: 'Moyse Drive' }
    );
    const selection = service.selectOfficialAddressCandidatesForBuilding({
      building: {
        rowId: 'building-41-row',
        publicId: 'building-41',
        geometry: building.geometry,
        streetName: 'Moyse Drive',
      },
      addressRows: [
        {
          id: '00000000-0000-0000-0000-000000000041',
          formatted: '41 Moyse Drive',
          house_number: '41',
          street_name: 'Moyse Drive',
          source: 'gold',
          building_id: null,
          building_gers_id: null,
          geom: {
            type: 'Point',
            coordinates: [-79.00403, 43.00408],
          },
        },
      ],
      linkRows: [],
      radiusMeters: 60,
      limit: 15,
    });

    assertEqual(selection.candidates.length, 1);
    assertEqual(selection.candidates[0].id, '00000000-0000-0000-0000-000000000041');
    assertEqual(selection.candidates[0].reason, 'Nearby, same street');
  });

  test('Address candidates: orphan link rows do not hide nearby addresses', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'building-43',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415),
      { primaryStreet: 'Moyse Drive' }
    );
    const selection = service.selectOfficialAddressCandidatesForBuilding({
      building: {
        rowId: 'building-43-row',
        publicId: 'building-43',
        geometry: building.geometry,
        streetName: 'Moyse Drive',
      },
      addressRows: [
        {
          id: '00000000-0000-0000-0000-000000000043',
          formatted: '43 Moyse Drive',
          house_number: '43',
          street_name: 'Moyse Drive',
          source: 'gold',
          building_id: null,
          building_gers_id: null,
          geom: {
            type: 'Point',
            coordinates: [-79.00403, 43.00408],
          },
        },
      ],
      linkRows: [
        {
          address_id: '00000000-0000-0000-0000-000000000043',
          building_id: null,
          confidence: 0,
          match_type: 'orphan',
        },
      ],
      radiusMeters: 60,
      limit: 15,
    });

    assertEqual(selection.candidates.length, 1);
    assertEqual(selection.candidates[0].id, '00000000-0000-0000-0000-000000000043');
  });

  test('Address candidates: pending orphan coordinate makes address eligible when campaign row geom is missing', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'building-44',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415),
      { primaryStreet: 'Moyse Drive' }
    );
    const selection = service.selectOfficialAddressCandidatesForBuilding({
      building: {
        rowId: 'building-44-row',
        publicId: 'building-44',
        geometry: building.geometry,
        streetName: 'Moyse Drive',
      },
      addressRows: [
        {
          id: '00000000-0000-0000-0000-000000000044',
          formatted: '44 Moyse Drive',
          house_number: '44',
          street_name: null,
          source: 'gold',
          building_id: null,
          building_gers_id: null,
          geom: null,
        },
      ],
      linkRows: [],
      orphanRows: [
        {
          address_id: '00000000-0000-0000-0000-000000000044',
          coordinate: {
            type: 'Point',
            coordinates: [-79.00403, 43.00408],
          },
          status: 'pending_review',
          suggested_street: 'Moyse Drive',
          address_street: null,
        },
      ],
      radiusMeters: 60,
      limit: 15,
    });

    assertEqual(selection.candidates.length, 1);
    assertEqual(selection.candidates[0].id, '00000000-0000-0000-0000-000000000044');
    assertEqual(selection.candidates[0].street_name, 'Moyse Drive');
  });

  test('Address candidates: assigned orphan coordinate is ignored', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'building-47',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415),
      { primaryStreet: 'Moyse Drive' }
    );
    const selection = service.selectOfficialAddressCandidatesForBuilding({
      building: {
        rowId: 'building-47-row',
        publicId: 'building-47',
        geometry: building.geometry,
        streetName: 'Moyse Drive',
      },
      addressRows: [
        {
          id: '00000000-0000-0000-0000-000000000047',
          formatted: '47 Moyse Drive',
          house_number: '47',
          street_name: null,
          source: 'gold',
          building_id: null,
          building_gers_id: null,
          geom: null,
        },
      ],
      linkRows: [],
      orphanRows: [
        {
          address_id: '00000000-0000-0000-0000-000000000047',
          coordinate: {
            type: 'Point',
            coordinates: [-79.00403, 43.00408],
          },
          status: 'assigned',
          suggested_street: 'Moyse Drive',
          address_street: null,
        },
      ],
      radiusMeters: 60,
      limit: 15,
    });

    assertEqual(selection.candidates.length, 0);
  });

  test('Address candidates: repair mode includes addresses linked to other buildings', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'building-45',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415),
      { primaryStreet: 'Moyse Drive' }
    );
    const addressRows = [
      {
        id: '00000000-0000-0000-0000-000000000045',
        formatted: '45 Moyse Drive',
        house_number: '45',
        street_name: 'Moyse Drive',
        source: 'gold',
        building_id: null,
        building_gers_id: null,
        geom: {
          type: 'Point',
          coordinates: [-79.00403, 43.00408],
        },
      },
    ];
    const linkRows = [
      {
        address_id: '00000000-0000-0000-0000-000000000045',
        building_id: 'other-building-row',
        confidence: 1,
        match_type: 'manual',
      },
    ];

    const normalSelection = service.selectOfficialAddressCandidatesForBuilding({
      building: {
        rowId: 'building-45-row',
        publicId: 'building-45',
        geometry: building.geometry,
        streetName: 'Moyse Drive',
      },
      addressRows,
      linkRows,
      radiusMeters: 60,
      limit: 15,
    });
    assertEqual(normalSelection.candidates.length, 0);

    const repairSelection = service.selectOfficialAddressCandidatesForBuilding({
      building: {
        rowId: 'building-45-row',
        publicId: 'building-45',
        geometry: building.geometry,
        streetName: 'Moyse Drive',
      },
      addressRows,
      linkRows,
      radiusMeters: 60,
      limit: 15,
      includeLinkedCandidates: true,
    });
    assertEqual(repairSelection.candidates.length, 1);
    assertEqual(repairSelection.candidates[0].id, '00000000-0000-0000-0000-000000000045');
  });

  test('Address candidates: repair mode still hides addresses linked to the current building', () => {
    const service = new StableLinkerService({} as any);
    const building = makeBuilding(
      'building-46',
      rectangle(-79.00420, 43.00400, -79.00405, 43.00415),
      { primaryStreet: 'Moyse Drive' }
    );
    const selection = service.selectOfficialAddressCandidatesForBuilding({
      building: {
        rowId: 'building-46-row',
        publicId: 'building-46',
        geometry: building.geometry,
        streetName: 'Moyse Drive',
      },
      addressRows: [
        {
          id: '00000000-0000-0000-0000-000000000046',
          formatted: '46 Moyse Drive',
          house_number: '46',
          street_name: 'Moyse Drive',
          source: 'gold',
          building_id: null,
          building_gers_id: null,
          geom: {
            type: 'Point',
            coordinates: [-79.00403, 43.00408],
          },
        },
      ],
      linkRows: [
        {
          address_id: '00000000-0000-0000-0000-000000000046',
          building_id: 'building-46-row',
          confidence: 1,
          match_type: 'manual',
        },
      ],
      radiusMeters: 60,
      limit: 15,
      includeLinkedCandidates: true,
    });

    assertEqual(selection.candidates.length, 0);
  });

  test('Dense ambiguity: equal-distance buildings raise DataIntegrityError instead of guessing', () => {
    const service = new StableLinkerService({} as any);
    const left = makeBuilding(
      'left',
      rectangle(-79.00312, 43.00300, -79.00292, 43.00312),
      { primaryStreet: 'Queen Street' }
    );
    const right = makeBuilding(
      'right',
      rectangle(-79.00308, 43.00298, -79.00288, 43.00310),
      { primaryStreet: 'Queen Street' }
    );
    const address = makeAddress('500', -79.00300, 43.00305, 'Queen Street');

    let thrown: unknown = null;
    try {
      (service as any).matchAddressToBuilding(address, [left, right], new Set(), []);
    } catch (error) {
      thrown = error;
    }

    assertTrue(thrown instanceof DataIntegrityError, 'Expected DataIntegrityError for ambiguous proximity tie');
  });

  await testAsync('Orphan/manual assignment: manual assign updates orphan state and inserts manual link', async () => {
    const state: MockState = {
      addressOrphans: [
        {
          id: 'orphan-1',
          campaign_id: 'campaign-1',
          address_id: 'address-1',
          status: 'pending_review',
        },
      ],
      buildingAddressLinks: [],
    };
    const supabase = createMockSupabase(state);
    const service = new StableLinkerService(supabase as any);

    const orphanMatch = (service as any).matchAddressToBuilding(
      makeAddress('address-1', -79.1000, 43.1000, 'No Match Road'),
      [],
      new Set(),
      []
    );
    assertEqual(orphanMatch.matchType, 'orphan');

    await service.assignOrphan('orphan-1', 'building-77', 'user-1');

    assertEqual(state.addressOrphans?.[0].status, 'assigned');
    assertEqual(state.addressOrphans?.[0].assigned_building_id, 'building-77');
    assertEqual(state.buildingAddressLinks?.length, 1);
    assertEqual(state.buildingAddressLinks?.[0].match_type, 'manual');
  });

  await testAsync('External persistence: static building IDs are saved on campaign address rows', async () => {
    const state: MockState = {
      campaignAddresses: [
        {
          id: 'address-1',
          campaign_id: 'campaign-1',
          building_id: null,
          building_gers_id: null,
          match_source: null,
          confidence: null,
        },
      ],
      buildingAddressLinks: [],
    };
    const service = new StableLinkerService(createMockSupabase(state) as any);

    await (service as any).saveMatches(
      'campaign-1',
      [
        {
          addressId: 'address-1',
          addressGersId: 'durham_addresses:1:202692',
          buildingId: 'durham_buildings:1:905734',
          matchType: 'containment_verified',
          confidence: 1,
          distanceMeters: 0,
          streetMatchScore: 0,
          buildingAreaSqm: 120,
          buildingClass: 'building',
          buildingHeight: null,
          isMultiUnit: false,
          unitCount: 1,
          unitArrangement: 'single',
        },
      ],
      'municipal-diamond-canada-on-durham',
      'external'
    );

    assertEqual(state.buildingAddressLinks?.length, 0);
    assertEqual(state.campaignAddresses?.[0].building_id, null);
    assertEqual(state.campaignAddresses?.[0].building_gers_id, 'durham_buildings:1:905734');
    assertEqual(state.campaignAddresses?.[0].match_source, 'gold_exact');
    assertEqual(state.campaignAddresses?.[0].confidence, 1);
  });

  await testAsync('External manual assignment: municipal building ids stay out of UUID orphan fields', async () => {
    const state: MockState = {
      campaignAddresses: [
        {
          id: 'address-1',
          campaign_id: 'campaign-1',
          building_id: null,
          building_gers_id: null,
          match_source: null,
          confidence: null,
        },
      ],
      addressOrphans: [
        {
          id: 'orphan-1',
          campaign_id: 'campaign-1',
          address_id: 'address-1',
          status: 'pending_review',
          assigned_building_id: null,
        },
      ],
      buildingAddressLinks: [],
    };
    const service = new StableLinkerService(createMockSupabase(state) as any);

    const result = await service.assignAddressToExternalBuilding({
      campaignId: 'campaign-1',
      addressId: 'address-1',
      buildingPublicId: 'durham_buildings:226859',
      assignedBy: 'user-1',
      coordinate: [-79.1, 43.1],
    });

    assertEqual(state.campaignAddresses?.[0].building_id, null);
    assertEqual(state.campaignAddresses?.[0].building_gers_id, 'durham_buildings:226859');
    assertEqual(state.campaignAddresses?.[0].match_source, 'manual');
    assertEqual(state.addressOrphans?.[0].status, 'assigned');
    assertEqual(state.addressOrphans?.[0].assigned_building_id, null);
    assertEqual(result.linkedAddressIds, ['address-1']);
  });

  console.log(`\n${'='.repeat(50)}`);
  console.log(`Tests passed: ${testsPassed}`);
  console.log(`Tests failed: ${testsFailed}`);
  console.log(`${'='.repeat(50)}`);
  if (testsFailed > 0) process.exit(1);
}

void run();
