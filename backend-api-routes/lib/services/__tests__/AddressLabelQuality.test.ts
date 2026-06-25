import assert from 'node:assert/strict';
import { test } from 'node:test';
import { addressLabelQuality } from '../AddressLabelQuality';
import type { StandardCampaignAddress } from '../AddressAdapter';

function address(overrides: Partial<StandardCampaignAddress>): StandardCampaignAddress {
  return {
    campaign_id: 'campaign',
    formatted: 'Address',
    coordinate: { lat: 0, lon: 0 },
    lat: 0,
    lon: 0,
    geom: JSON.stringify({ type: 'Point', coordinates: [0, 0] }),
    source: 'diamond',
    gers_id: null,
    ...overrides,
  };
}

test('rejects street-only ordinal municipal labels even though they contain letters', () => {
  const quality = addressLabelQuality([
    address({ formatted: '95TH', street_name: '95TH' }),
    address({ formatted: '96TH', street_name: '96TH' }),
    address({ formatted: '97TH', street_name: '97TH' }),
  ]);

  assert.equal(quality.usable, 3);
  assert.equal(quality.houseNumberUsable, 0);
  assert.equal(quality.streetOnlyOrdinal, 3);
  assert.equal(quality.acceptable, false);
});

test('accepts Bedrock-style labels with house numbers and street names', () => {
  const quality = addressLabelQuality([
    address({ formatted: '11600 SW 96TH TER, MIAMI, FL 33176', house_number: '11600', street_name: 'SW 96TH TER' }),
    address({ formatted: '11605 SW 96TH TER, MIAMI, FL 33176', house_number: '11605', street_name: 'SW 96TH TER' }),
    address({ formatted: '11571 SW 97TH ST, MIAMI, FL 33176', house_number: '11571', street_name: 'SW 97TH ST' }),
  ]);

  assert.equal(quality.usable, 3);
  assert.equal(quality.houseNumberUsable, 3);
  assert.equal(quality.streetOnlyOrdinal, 0);
  assert.equal(quality.acceptable, true);
});

test('accepts real house numbers on ordinal street names', () => {
  const quality = addressLabelQuality([
    address({ formatted: '11089 51st St', house_number: '11089', street_name: '51st St' }),
    address({ formatted: '11091 51st St', house_number: '11091', street_name: '51st St' }),
    address({ formatted: '11093 SW 51st St', house_number: '11093', street_name: 'SW 51st St' }),
  ]);

  assert.equal(quality.usable, 3);
  assert.equal(quality.houseNumberUsable, 3);
  assert.equal(quality.streetOnlyOrdinal, 0);
  assert.equal(quality.acceptable, true);
});

test('rejects Brisbane-style number-only labels even when house_number is present', () => {
  const quality = addressLabelQuality([
    address({ formatted: '32', house_number: '32', street_name: '32', locality: 'Hamilton' }),
    address({ formatted: '32A', house_number: '32A', street_name: '32A', locality: 'Hamilton' }),
    address({ formatted: '34', house_number: '34', street_name: '34', locality: 'Hamilton' }),
  ]);

  assert.equal(quality.usable, 0);
  assert.equal(quality.houseNumberUsable, 3);
  assert.equal(quality.numericOnly, 2);
  assert.equal(quality.acceptable, false);
});
