import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  canonicalBedrockAddressExternalId,
  normalizedAddressDisplayIdentity,
} from '../AddressDisplayIdentity';

test('collapses display-equivalent street suffix variants', () => {
  assert.equal(
    normalizedAddressDisplayIdentity({
      formatted: '2703 Addison Avenue, Addison, TX',
      house_number: '2703',
      street_name: 'Addison Avenue',
      locality: 'Addison',
    }),
    normalizedAddressDisplayIdentity({
      formatted: '2703 ADDISON AVE',
      house_number: '2703',
      street_name: 'ADDISON AVE',
      locality: 'Addison',
    })
  );
});

test('keeps real units distinct', () => {
  assert.notEqual(
    normalizedAddressDisplayIdentity({
      formatted: '2703 ADDISON AVE UNIT A',
      house_number: '2703',
      street_name: 'ADDISON AVE',
    }),
    normalizedAddressDisplayIdentity({
      formatted: '2703 ADDISON AVE UNIT B',
      house_number: '2703',
      street_name: 'ADDISON AVE',
    })
  );
});

test('does not treat street-only ordinals as house numbers', () => {
  assert.equal(
    normalizedAddressDisplayIdentity({
      formatted: '51ST',
      house_number: '51ST',
      street_name: '51ST',
    }),
    'f:51st|l:|p:'
  );

  assert.equal(
    normalizedAddressDisplayIdentity({
      formatted: '51st St',
    }),
    'f:51st st|l:|p:'
  );
});

test('allows ordinal street names when a real house number is present', () => {
  assert.equal(
    normalizedAddressDisplayIdentity({
      formatted: '11089 51st St',
      house_number: '11089',
      street_name: '51st St',
    }),
    'h:11089|s:51st st|u:'
  );
});

test('canonicalizes Bedrock US master address aliases', () => {
  assert.equal(
    canonicalBedrockAddressExternalId('bedrock_us:master:us:4915144231067573182'),
    'bedrock_us:4915144231067573182'
  );
  assert.equal(
    canonicalBedrockAddressExternalId('master:us:4915144231067573182'),
    '4915144231067573182'
  );
});
