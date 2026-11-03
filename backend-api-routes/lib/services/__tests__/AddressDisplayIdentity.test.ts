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

test('matches reverse-geocoded street lines to existing nearby address rows', () => {
  assert.equal(
    normalizedAddressDisplayIdentity({
      formatted: '123 Main Street',
      house_number: '123',
      street_name: 'Main Street',
      postal_code: 'L5M 5B2',
    }),
    normalizedAddressDisplayIdentity({
      formatted: '123 MAIN ST, Mississauga ON L5M5B2',
      house_number: '123',
      street_name: 'MAIN ST',
      postal_code: 'L5M5B2',
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

test('does not use numeric-only street_name values as street identity', () => {
  assert.equal(
    normalizedAddressDisplayIdentity({
      formatted: '32',
      house_number: '32',
      street_name: '32',
      locality: 'Hamilton',
    }),
    'f:32|l:hamilton|p:'
  );

  assert.equal(
    normalizedAddressDisplayIdentity({
      formatted: '32 Joynt St, Hamilton QLD',
      house_number: '32',
      street_name: '32',
      locality: 'Hamilton',
    }),
    'h:32|s:joynt st|u:'
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


test('matches direction placement and expansion without losing address distinctions', () => {
  const identity = (street: string, house = '405', unit?: string) => normalizedAddressDisplayIdentity({ house_number: house, street_name: street, unit });
  const expected = identity('Belmar St E');
  for (const street of ['E Belmar St', 'East Belmar Street', 'Belmar East Street', 'BELMAR E. ST.']) {
    assert.equal(identity(street), expected, street);
    assert.equal(normalizedAddressDisplayIdentity({ formatted: `405 ${street}, Windsor ON` }), expected);
  }
  for (const street of ['Belmar St W', 'Belmar St']) assert.notEqual(identity(street), expected);
  for (const house of ['403', '405A', '405-407']) assert.notEqual(identity('Belmar St E', house), expected);
  assert.notEqual(identity('East Street'), identity('Street East'));
  assert.notEqual(identity('North Road'), identity('Road North'));
  assert.notEqual(identity('Belmar St E', '405', '2'), expected);
  assert.notEqual(identity('Belmar St E', '405', '2'), identity('Belmar St E', '405', '3'));
  assert.equal(identity('NE Main Ave'), identity('Main Avenue Northeast'));
  assert.equal(identity('North East Main Ave'), identity('Main Avenue North East'));
});


test('matches unit labels in both formatted and structured data', () => {
  const expected = normalizedAddressDisplayIdentity({ house_number: '405', street_name: 'Belmar St E', unit: '2' });
  for (const formatted of ['405 E Belmar St Unit 2', 'Unit 2 405 Belmar St E', '405 East Belmar Street #2', '405 Belmar St E, Suite 2, Windsor']) {
    assert.equal(normalizedAddressDisplayIdentity({ formatted }), expected, formatted);
  }
  assert.equal(normalizedAddressDisplayIdentity({ house_number: '405', street_name: 'E Belmar Street', unit: 'Unit 2' }), expected);
  assert.equal(normalizedAddressDisplayIdentity({ house_number: '405', street_name: 'E Belmar Street Unit 2' }), expected);
});
