import assert from 'node:assert/strict';
import test from 'node:test';
import { searchGooglePlacesLeads } from '../googlePlacesLeadSearch';

test('fetches every Places page and only removes duplicate Place IDs', async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{ body: Record<string, unknown>; fieldMask: string }> = [];

  globalThis.fetch = (async (_input: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body ?? '{}')) as Record<string, unknown>;
    const fieldMask = new Headers(init?.headers).get('X-Goog-FieldMask') ?? '';
    requests.push({ body, fieldMask });

    const textQuery = String(body.textQuery ?? 'query');
    const pageToken = String(body.pageToken ?? '');
    const page = pageToken.endsWith(':2') ? 2 : pageToken.endsWith(':3') ? 3 : 1;
    const queryKey = textQuery.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    const payload = {
      places: [
        {
          id: 'shared-place-id',
          displayName: { text: 'Shared Roofing Company' },
          nationalPhoneNumber: '+1 416 555 0100',
          formattedAddress: '1 Shared Street, Toronto, ON',
          businessStatus: 'OPERATIONAL',
        },
        {
          id: `${queryKey}-page-${page}`,
          displayName: { text: `Roofing Branch ${queryKey} ${page}` },
          // Separate branches may legitimately share a call-centre number.
          nationalPhoneNumber: '+1 416 555 0200',
          formattedAddress: `${page} Branch Street, Toronto, ON`,
          businessStatus: 'OPERATIONAL',
        },
      ],
      ...(page < 3 ? { nextPageToken: `${textQuery}:${page + 1}` } : {}),
    };

    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }) as typeof fetch;

  try {
    const result = await searchGooglePlacesLeads({
      apiKey: 'test-key',
      city: 'Toronto',
      region: 'Ontario',
      countryCode: 'CA',
      industry: 'Widgets',
      pageSize: 20,
    });

    // Generic industries produce four query variants. Each query returns three
    // pages with two rows: one repeated place plus one distinct branch.
    assert.equal(result.queryCount, 4);
    assert.equal(requests.length, 12);
    assert.equal(result.rawResultCount, 24);
    assert.equal(result.uniqueResultCount, 13);
    assert.equal(result.prospects.filter((lead) => lead.placeId === 'shared-place-id').length, 1);
    assert.equal(result.prospects.filter((lead) => lead.phone === '+1 416 555 0200').length, 12);

    assert.ok(requests.every(({ body }) => body.includePureServiceAreaBusinesses === true));
    assert.ok(requests.every(({ fieldMask }) => fieldMask.includes('nextPageToken')));
    assert.equal(requests.filter(({ body }) => typeof body.pageToken === 'string').length, 8);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

const barrieOptions = { apiKey: 'test-key', city: 'Barrie', region: 'Ontario', countryCode: 'CA', industry: 'Roofing', pageSize: 20 };

function jsonResponse(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
}

test('Barrie roofing search requires contractors, excludes suppliers and closed listings, and keeps service-area roofers', async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{ body: Record<string, unknown>; mask: string }> = [];
  const roofer = { primaryType: 'roofing_contractor', businessStatus: 'OPERATIONAL', nationalPhoneNumber: '+1 705 555 0100' };
  globalThis.fetch = (async (_input, init) => {
    const body = JSON.parse(String(init?.body ?? '{}'));
    requests.push({ body, mask: new Headers(init?.headers).get('X-Goog-FieldMask') ?? '' });
    return jsonResponse({ places: [
      { ...roofer, id: 'jn', displayName: { text: 'JN Roofing and Contracting' } },
      { ...roofer, id: 'dc', displayName: { text: 'D.C United Roofing' }, userRatingCount: 0 },
      { ...roofer, id: 'exteriors', displayName: { text: 'Airen Group Roofing and Exteriors' }, primaryType: 'general_contractor', types: ['general_contractor', 'roofing_contractor'] },
      { ...roofer, id: 'supplier', displayName: { text: 'Barrie Roofing Supplies' } },
      { ...roofer, id: 'distributor', displayName: { text: 'Roofing Distribution Centre' } },
      { ...roofer, id: 'store', displayName: { text: 'Roofmart' }, primaryType: 'building_materials_store', types: ['roofing_contractor'] },
      { ...roofer, id: 'label-supplier', displayName: { text: 'ABC Roofing' }, primaryTypeDisplayName: { text: 'Roofing supply store' } },
      { ...roofer, id: 'closed', displayName: { text: 'Closed Roofing' }, businessStatus: 'CLOSED_PERMANENTLY' },
      { ...roofer, id: 'temporary', displayName: { text: 'Paused Roofing' }, businessStatus: 'CLOSED_TEMPORARILY' },
      { id: 'uncategorized', displayName: { text: 'Roofing Results' }, businessStatus: 'OPERATIONAL' },
    ], ...(body.pageToken ? {} : { nextPageToken: 'page-2' }) });
  }) as typeof fetch;
  try {
    const result = await searchGooglePlacesLeads(barrieOptions);
    assert.deepEqual(result.prospects.map((lead) => lead.placeId).sort(), ['dc', 'exteriors', 'jn']);
    assert.equal(result.queryPreview[0].textQuery, 'roofers Barrie Ontario');
    assert.ok(requests.every(({ body }) => body.includedType === 'roofing_contractor' && body.strictTypeFiltering === true));
    assert.ok(requests.every(({ body }) => body.includePureServiceAreaBusinesses === true));
    assert.ok(requests.every(({ mask }) => mask.includes('places.types')));
    assert.ok(requests.some(({ body }) => body.pageToken === 'page-2'));
    assert.ok(!result.queryPreview.some((query) => query.industry === 'metal roofing'));
    assert.ok(result.prospects.every((lead) => lead.formattedAddress === ''));
  } finally { globalThis.fetch = originalFetch; }
});

test('legacy fallback filters contractor categories before fetching details and never uses search text as category evidence', async () => {
  const originalFetch = globalThis.fetch;
  const detailIds: string[] = [];
  const legacyQueries: URL[] = [];
  globalThis.fetch = (async (input) => {
    const url = new URL(String(input));
    if (url.hostname === 'places.googleapis.com') {
      return jsonResponse({ error: { message: 'API_KEY_SERVICE_BLOCKED', details: [{ reason: 'API_KEY_SERVICE_BLOCKED' }] } }, 403);
    }
    if (url.pathname.includes('/textsearch/')) {
      legacyQueries.push(url);
      return jsonResponse({ status: 'OK', results: [
        { place_id: 'contractor', name: 'Barrie Roof Repairs', types: ['general_contractor', 'roofing_contractor'], business_status: 'OPERATIONAL' },
        { place_id: 'supplier', name: 'Barrie Roofing Supplies', types: ['roofing_contractor'], business_status: 'OPERATIONAL' },
        { place_id: 'closed', name: 'Old Roofing', types: ['roofing_contractor'], business_status: 'CLOSED_PERMANENTLY' },
        { place_id: 'unknown', name: 'Uncategorized', business_status: 'OPERATIONAL' },
      ] });
    }
    const id = url.searchParams.get('place_id')!;
    detailIds.push(id);
    return jsonResponse({ status: 'OK', result: { place_id: id, formatted_phone_number: '+1 705 555 0101' } });
  }) as typeof fetch;
  try {
    const result = await searchGooglePlacesLeads(barrieOptions);
    assert.deepEqual(result.prospects.map((lead) => lead.placeId), ['contractor']);
    assert.ok(detailIds.length > 0);
    assert.ok(detailIds.every((id) => id === 'contractor'));
    assert.ok(legacyQueries.every((url) => url.searchParams.get('type') === 'roofing_contractor'));
  } finally { globalThis.fetch = originalFetch; }
});

test('explicit supplier searches and unrelated industries retain their requested search behavior', async () => {
  const originalFetch = globalThis.fetch;
  const requests: Record<string, unknown>[] = [];
  globalThis.fetch = (async (_input, init) => {
    requests.push(JSON.parse(String(init?.body ?? '{}')));
    return jsonResponse({ places: [{ id: 'supplier', displayName: { text: 'Roofing Supplies' }, primaryType: 'building_materials_store' }] });
  }) as typeof fetch;
  try {
    for (const industry of ['Roofing suppliers', 'Widgets']) {
      const result = await searchGooglePlacesLeads({ ...barrieOptions, industry });
      assert.equal(result.prospects.length, 1);
    }
    assert.ok(requests.every((body) => body.strictTypeFiltering === undefined && body.includedType === undefined));
  } finally { globalThis.fetch = originalFetch; }
});

test('roofing searches return all 60 unique contractors across three 20-result pages', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async (_input, init) => {
    const body = JSON.parse(String(init?.body ?? '{}'));
    const page = Number(body.pageToken || '1');
    return jsonResponse({
      places: Array.from({ length: 20 }, (_, index) => ({
        id: `roofer-${(page - 1) * 20 + index}`,
        displayName: { text: `Barrie Roofer ${(page - 1) * 20 + index}` },
        primaryType: 'roofing_contractor', businessStatus: 'OPERATIONAL',
      })),
      ...(page < 3 ? { nextPageToken: String(page + 1) } : {}),
    });
  }) as typeof fetch;
  try {
    const result = await searchGooglePlacesLeads(barrieOptions);
    assert.equal(result.uniqueResultCount, 60);
    assert.equal(result.prospects.length, 60);
  } finally { globalThis.fetch = originalFetch; }
});
