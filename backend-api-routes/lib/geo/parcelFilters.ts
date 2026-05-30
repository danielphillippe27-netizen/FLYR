export const NON_RESIDENTIAL_PARCEL_TERMS = [
  'access way',
  'access ways',
  'accessway',
  'accessways',
  'alley',
  'alleyway',
  'bike path',
  'bike paths',
  'bikeway',
  'bikeways',
  'bridge',
  'cycle path',
  'cycle paths',
  'cycleway',
  'cycleways',
  'ditch',
  'drain',
  'drainage',
  'drainage corridor',
  'drainage reserve',
  'domain',
  'easement',
  'esplanade',
  'foot path',
  'foot paths',
  'footpath',
  'footpaths',
  'footway',
  'footways',
  'freeway',
  'freeways',
  'highway',
  'highways',
  'lane way',
  'laneway',
  'local purpose',
  'median',
  'motorway',
  'motorways',
  'multi use path',
  'multi use paths',
  'open space',
  'path',
  'paths',
  'pathway',
  'pathways',
  'park',
  'pedestrian',
  'pedestrian access',
  'pedestrian accessway',
  'pedestrian path',
  'pedestrian way',
  'pedestrian walkway',
  'public path',
  'public road',
  'public walkway',
  'rail',
  'rail corridor',
  'railway',
  'railroad',
  'recreation',
  'reserve',
  'right of way',
  'right of way road',
  'right-of-way',
  'right-of-way road',
  'right_of_way',
  'rightofway',
  'river',
  'road',
  'road allowance',
  'road corridor',
  'road parcel',
  'road reserve',
  'road right of way',
  'roadway',
  'roadways',
  'roads',
  'school',
  'service lane',
  'shared path',
  'shared paths',
  'shared use path',
  'shared use paths',
  'sidewalk',
  'sidewalk easement',
  'sidewalk parcel',
  'sidewalk reserve',
  'sidewalks',
  'storm sewer',
  'stormwater',
  'stream',
  'street',
  'streets',
  'substation',
  'transit',
  'transport',
  'transportation',
  'tunnel',
  'utility',
  'utility corridor',
  'verge',
  'walkway',
  'walkway easement',
  'walkway reserve',
  'walkways',
  'wastewater',
  'watercourse',
];

const PARCEL_CLASSIFICATION_PROPERTY_KEYS = [
  'agency',
  'appellation',
  'asset_type',
  'category',
  'class',
  'class_name',
  'description',
  'designation',
  'feature_class',
  'feature_type',
  'land_type',
  'land_use',
  'land_use_description',
  'landuse',
  'landuse_description',
  'legal_type',
  'lot_type',
  'maintainer',
  'municipal_use',
  'name',
  'owner',
  'owner_type',
  'ownership',
  'parcel_class',
  'parcel_intent',
  'parcel_purpose',
  'parcel_type',
  'property_class',
  'property_type',
  'property_use',
  'public_use',
  'purpose',
  'reserve_type',
  'site_type',
  'statutory_actions',
  'sub_type',
  'subtype',
  'title_type',
  'transport',
  'transportation',
  'type',
  'use',
  'use_code',
  'use_description',
  'use_type',
  'zone',
  'zoning',
  'zoning_code',
  'zoning_description',
];

const ROAD_INDICATOR_PROPERTY_KEYS = [
  'highway',
  'highway_type',
  'access_way',
  'accessway',
  'bikeway',
  'corridor',
  'cycleway',
  'easement',
  'footpath',
  'footway',
  'linear_feature',
  'path',
  'path_type',
  'pathway',
  'pedestrian',
  'railway',
  'railway_type',
  'right-of-way',
  'right_of_way',
  'rightofway',
  'road',
  'road_class',
  'road_classification',
  'road_type',
  'roads',
  'sidewalk',
  'sidewalks',
  'trail',
  'trail_type',
  'transportation_corridor',
  'utility_corridor',
  'walkway',
];

const FALSEY_TEXT_VALUES = new Set(['0', 'false', 'n', 'no', 'none', 'null', 'unknown']);
const EARTH_METERS_PER_DEGREE_LAT = 110_540;

function normalizeParcelText(value: unknown): string {
  if (typeof value === 'string') {
    return value
      .trim()
      .toLowerCase()
      .replace(/[_/\\-]+/g, ' ')
      .replace(/[^a-z0-9]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  return '';
}

function propertyValue(properties: Record<string, unknown>, key: string): unknown {
  if (Object.prototype.hasOwnProperty.call(properties, key)) return properties[key];
  const lowerKey = key.toLowerCase();
  const matchingKey = Object.keys(properties).find((candidate) => candidate.toLowerCase() === lowerKey);
  return matchingKey ? properties[matchingKey] : undefined;
}

function textValues(value: unknown): string[] {
  if (Array.isArray(value)) return value.flatMap(textValues);
  if (value && typeof value === 'object') return Object.values(value as Record<string, unknown>).flatMap(textValues);

  const text = normalizeParcelText(value);
  return text ? [text] : [];
}

function containsTerm(text: string, term: string): boolean {
  const normalizedTerm = normalizeParcelText(term);
  return normalizedTerm ? ` ${text} `.includes(` ${normalizedTerm} `) : false;
}

export function hasNonResidentialParcelTerm(value: unknown): boolean {
  return textValues(value).some((text) =>
    NON_RESIDENTIAL_PARCEL_TERMS.some((term) => containsTerm(text, term))
  );
}

function hasTruthyRoadIndicatorProperty(properties: Record<string, unknown>): boolean {
  return ROAD_INDICATOR_PROPERTY_KEYS.some((key) => {
    const value = propertyValue(properties, key);
    if (value === null || value === undefined) return false;
    const values = textValues(value);
    if (values.length === 0) return false;
    return values.some((text) => !FALSEY_TEXT_VALUES.has(text));
  });
}

export function isResidentialParcelFeature(feature: Pick<GeoJSON.Feature, 'properties'>): boolean {
  const properties = (feature.properties ?? {}) as Record<string, unknown>;
  const topologyType = normalizeParcelText(propertyValue(properties, 'topology_type'));
  if (topologyType && topologyType !== 'primary') return false;

  if (hasTruthyRoadIndicatorProperty(properties)) return false;

  if (
    PARCEL_CLASSIFICATION_PROPERTY_KEYS.some((key) =>
      hasNonResidentialParcelTerm(propertyValue(properties, key))
    )
  ) {
    return false;
  }

  const intent = normalizeParcelText(propertyValue(properties, 'parcel_intent'));
  if (!intent) return true;
  return intent === 'fee simple title' || intent === 'dcdb' || intent.includes('residential');
}

function flattenRings(geometry: GeoJSON.Geometry | null | undefined): number[][][] {
  if (geometry?.type === 'Polygon') return geometry.coordinates;
  if (geometry?.type === 'MultiPolygon') return geometry.coordinates.flat();
  return [];
}

function ringToMeters(ring: number[][], originLat: number): Array<[number, number]> {
  const lonScale = 111_320 * Math.max(Math.cos((originLat * Math.PI) / 180), 0.000001);
  return ring
    .map((position) => [Number(position?.[0]) * lonScale, Number(position?.[1]) * EARTH_METERS_PER_DEGREE_LAT] as [number, number])
    .filter((position) => Number.isFinite(position[0]) && Number.isFinite(position[1]));
}

function ringAreaSqm(ring: Array<[number, number]>): number {
  if (ring.length < 4) return 0;
  let sum = 0;
  for (let index = 0; index < ring.length; index += 1) {
    const current = ring[index];
    const next = ring[(index + 1) % ring.length];
    sum += current[0] * next[1] - next[0] * current[1];
  }
  return Math.abs(sum) / 2;
}

function ringPerimeterMeters(ring: Array<[number, number]>): number {
  if (ring.length < 2) return 0;
  let perimeter = 0;
  for (let index = 0; index < ring.length; index += 1) {
    const current = ring[index];
    const next = ring[(index + 1) % ring.length];
    perimeter += Math.hypot(next[0] - current[0], next[1] - current[1]);
  }
  return perimeter;
}

function geometryMetrics(geometry: GeoJSON.Geometry | null | undefined): {
  areaSqm: number;
  perimeterMeters: number;
  bboxAspectRatio: number;
} | null {
  const rings = flattenRings(geometry);
  const positions = rings.flat();
  if (positions.length === 0) return null;

  const validPositions = positions
    .map((position) => [Number(position?.[0]), Number(position?.[1])] as [number, number])
    .filter((position) => Number.isFinite(position[0]) && Number.isFinite(position[1]));
  if (validPositions.length === 0) return null;

  const originLat = validPositions.reduce((sum, position) => sum + position[1], 0) / validPositions.length;
  const lonScale = 111_320 * Math.max(Math.cos((originLat * Math.PI) / 180), 0.000001);
  const xs = validPositions.map((position) => position[0] * lonScale);
  const ys = validPositions.map((position) => position[1] * EARTH_METERS_PER_DEGREE_LAT);
  const bboxWidth = Math.max(...xs) - Math.min(...xs);
  const bboxHeight = Math.max(...ys) - Math.min(...ys);

  let areaSqm = 0;
  let perimeterMeters = 0;
  for (const ring of rings) {
    const projectedRing = ringToMeters(ring, originLat);
    if (projectedRing.length < 4) continue;
    areaSqm += ringAreaSqm(projectedRing);
    perimeterMeters += ringPerimeterMeters(projectedRing);
  }

  return {
    areaSqm,
    perimeterMeters,
    bboxAspectRatio: Math.max(bboxWidth, bboxHeight) / Math.max(Math.min(bboxWidth, bboxHeight), 0.1),
  };
}

export function isLikelyInfrastructureParcelFeature(
  feature: Pick<GeoJSON.Feature, 'properties'> & Partial<Pick<GeoJSON.Feature, 'geometry'>>
): boolean {
  const properties = (feature.properties ?? {}) as Record<string, unknown>;
  if (hasTruthyRoadIndicatorProperty(properties)) return true;
  if (
    PARCEL_CLASSIFICATION_PROPERTY_KEYS.some((key) =>
      hasNonResidentialParcelTerm(propertyValue(properties, key))
    )
  ) {
    return true;
  }

  const metrics = geometryMetrics(feature.geometry);
  if (!metrics || metrics.areaSqm <= 0) return false;

  const compactness = (metrics.perimeterMeters * metrics.perimeterMeters) / metrics.areaSqm;
  return (
    (metrics.areaSqm < 40 && compactness > 45) ||
    (metrics.areaSqm < 120 && compactness > 140) ||
    (metrics.bboxAspectRatio > 12 && compactness > 45) ||
    (metrics.areaSqm > 1_000 && compactness > 70)
  );
}
