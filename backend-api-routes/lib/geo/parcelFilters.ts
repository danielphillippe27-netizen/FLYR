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
  'drain',
  'drainage',
  'domain',
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
  'right-of-way',
  'right_of_way',
  'rightofway',
  'river',
  'road',
  'road parcel',
  'road reserve',
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
  'sidewalk parcel',
  'sidewalk reserve',
  'sidewalks',
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
  'verge',
  'walkway',
  'walkway reserve',
  'walkways',
  'wastewater',
  'watercourse',
];

const PARCEL_CLASSIFICATION_PROPERTY_KEYS = [
  'agency',
  'appellation',
  'category',
  'class',
  'description',
  'designation',
  'feature_type',
  'land_use',
  'land_use_description',
  'landuse',
  'landuse_description',
  'legal_type',
  'maintainer',
  'name',
  'owner',
  'owner_type',
  'parcel_class',
  'parcel_intent',
  'parcel_purpose',
  'parcel_type',
  'property_class',
  'property_type',
  'public_use',
  'purpose',
  'reserve_type',
  'statutory_actions',
  'title_type',
  'transport',
  'transportation',
  'type',
  'use',
  'use_description',
  'zone',
  'zoning',
  'zoning_description',
];

const ROAD_INDICATOR_PROPERTY_KEYS = [
  'highway',
  'highway_type',
  'access_way',
  'accessway',
  'bikeway',
  'cycleway',
  'footpath',
  'footway',
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
  'walkway',
];

const FALSEY_TEXT_VALUES = new Set(['0', 'false', 'n', 'no', 'none', 'null', 'unknown']);

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
