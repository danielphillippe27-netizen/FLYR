import {
  canonicalizePolygonRing,
  deterministicTownhouseUnitId,
  orderTownhouseAddressesAlongAxis,
} from '../TownhouseUnitIdentity';

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const campaignId = '11111111-1111-4111-8111-111111111111';
const parentBuildingId = 'building-1799';
assert(
  deterministicTownhouseUnitId({ campaignId, parentBuildingId, unitIndex: 0 }) ===
    '63192119-95f3-5563-b77a-dccd0eead1e3',
  'mirrored splitter must satisfy the shared UUIDv5 fixture'
);

const addresses = [
  { id: 'a-2', lon: -78.8999, lat: 43.9, house_number: '1797' },
  { id: 'a-1', lon: -78.89998, lat: 43.9, house_number: '1795' },
];
assert(
  orderTownhouseAddressesAlongAxis(
    addresses,
    [-78.8998, 43.9],
    [-78.9, 43.9]
  ).map((address) => address.id).join(',') === 'a-1,a-2',
  'input and endpoint order must not change unit indexes'
);

assert(
  JSON.stringify(canonicalizePolygonRing([
    [-78.9, 43.9],
    [-78.8998, 43.9],
    [-78.8998, 43.9002],
    [-78.9, 43.9002],
    [-78.9, 43.9],
  ])) === JSON.stringify(canonicalizePolygonRing([
    [-78.8998, 43.9002],
    [-78.8998, 43.9],
    [-78.9, 43.9],
    [-78.9, 43.9002],
    [-78.8998, 43.9002],
  ])),
  'equivalent rings must canonicalize identically'
);

console.log('✓ mirrored deterministic townhouse identity contract passed');
