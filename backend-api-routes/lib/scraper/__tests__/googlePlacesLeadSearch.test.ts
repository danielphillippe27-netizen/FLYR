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
