import { createHash } from 'node:crypto';

export const TOWNHOUSE_SPLIT_VERSION = 'townhouse-split-v1';
const TOWNHOUSE_UNIT_NAMESPACE = '7d8f65c2-0e52-5b70-ae4f-1ba17fdb2c1f';

type Position = [number, number];
export type TownhouseAddressIdentityInput = {
  id: string;
  lon: number;
  lat: number;
  house_number?: string | null;
  street_name?: string | null;
  formatted?: string | null;
};

function uuidV5(name: string): string {
  const namespace = Buffer.from(TOWNHOUSE_UNIT_NAMESPACE.replaceAll('-', ''), 'hex');
  const digest = createHash('sha1').update(namespace).update(name, 'utf8').digest();
  const bytes = Buffer.from(digest.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join('-');
}

function comparePosition(left: Position, right: Position): number {
  return left[0] - right[0] || left[1] - right[1];
}

export function canonicalAddressIdentity(address: TownhouseAddressIdentityInput): string {
  const normalize = (value: string | null | undefined) =>
    (value ?? '').normalize('NFKD').replace(/\p{Diacritic}/gu, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  return [normalize(address.house_number), normalize(address.street_name), normalize(address.formatted), normalize(address.id)].join('|');
}

export function canonicalizePolygonRing(ring: number[][]): Position[] {
  const open = ring.map((point) => [Number(point[0]), Number(point[1])] as Position);
  if (open.length > 1 && open[0][0] === open.at(-1)?.[0] && open[0][1] === open.at(-1)?.[1]) open.pop();
  if (open.length < 3) return [...open, ...(open[0] ? [open[0]] : [])];
  const area = open.reduce((sum, point, index) => {
    const next = open[(index + 1) % open.length];
    return sum + point[0] * next[1] - next[0] * point[1];
  }, 0);
  const oriented = area < 0 ? [...open].reverse() : [...open];
  let start = 0;
  for (let index = 1; index < oriented.length; index += 1) {
    if (oriented[index][0] < oriented[start][0] || (oriented[index][0] === oriented[start][0] && oriented[index][1] < oriented[start][1])) start = index;
  }
  const rotated = [...oriented.slice(start), ...oriented.slice(0, start)];
  return [...rotated, rotated[0]];
}

export function deterministicTownhouseUnitId(input: {
  campaignId: string;
  parentBuildingId: string;
  unitIndex: number;
  splitVersion?: string;
}): string {
  return uuidV5([
    input.campaignId.toLowerCase(),
    input.parentBuildingId.toLowerCase(),
    input.splitVersion ?? TOWNHOUSE_SPLIT_VERSION,
    input.unitIndex,
  ].join(':'));
}

export function orderTownhouseAddressesAlongAxis<T extends TownhouseAddressIdentityInput>(
  addresses: T[],
  firstEndpoint: Position,
  secondEndpoint: Position
): T[] {
  const [start, end] = comparePosition(firstEndpoint, secondEndpoint) <= 0
    ? [firstEndpoint, secondEndpoint]
    : [secondEndpoint, firstEndpoint];
  const axisX = end[0] - start[0];
  const axisY = end[1] - start[1];
  const axisLength = Math.hypot(axisX, axisY);
  if (axisLength === 0) {
    return [...addresses].sort((left, right) =>
      canonicalAddressIdentity(left).localeCompare(canonicalAddressIdentity(right))
    );
  }
  const unitX = axisX / axisLength;
  const unitY = axisY / axisLength;
  return [...addresses].sort((left, right) => {
    const leftProjection = (left.lon - start[0]) * unitX + (left.lat - start[1]) * unitY;
    const rightProjection = (right.lon - start[0]) * unitX + (right.lat - start[1]) * unitY;
    return leftProjection - rightProjection ||
      canonicalAddressIdentity(left).localeCompare(canonicalAddressIdentity(right));
  });
}

export function townhouseUnitStableKey(input: {
  parentBuildingId: string;
  unitIndex: number;
  splitVersion?: string;
}): string {
  return [input.parentBuildingId.toLowerCase(), input.splitVersion ?? TOWNHOUSE_SPLIT_VERSION, input.unitIndex].join(':');
}

export function townhouseSplitSignature(input: {
  parentBuildingId: string;
  ring: number[][];
  orderedAddresses: TownhouseAddressIdentityInput[];
  splitMethod: string;
  splitVersion?: string;
}): string {
  return createHash('sha256').update([
    input.parentBuildingId.toLowerCase(),
    input.splitVersion ?? TOWNHOUSE_SPLIT_VERSION,
    input.splitMethod,
    canonicalizePolygonRing(input.ring).map(([lon, lat]) => `${lon.toFixed(8)},${lat.toFixed(8)}`).join(';'),
    input.orderedAddresses.map(canonicalAddressIdentity).join(';'),
  ].join('|')).digest('hex');
}
