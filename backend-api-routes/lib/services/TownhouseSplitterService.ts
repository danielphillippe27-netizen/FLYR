/**
 * TownhouseSplitterService - Gold Standard Townhouse Geometric Splitting
 * 
 * Production-grade townhouse detection and splitting using proper polygon clipping
 * with Web Mercator projection for accurate meter-based slicing.
 * 
 * Key Features:
 * - Proper polygon clipping with line intersection
 * - Web Mercator projection (meter-based, no distortion)
 * - Two-pass clipping for accurate slice boundaries
 * - Validation to prevent degenerate slices
 * - Apartment placeholder circles (7+ units)
 * - Comprehensive error logging
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { isUnitPersistenceEnabled } from '../config/features';
import {
  canonicalAddressIdentity,
  canonicalizePolygonRing,
  deterministicTownhouseUnitId,
  orderTownhouseAddressesAlongAxis,
  TOWNHOUSE_SPLIT_VERSION,
  townhouseSplitSignature,
  townhouseUnitStableKey,
} from './TownhouseUnitIdentity';

// Types
export interface BuildingFeature {
  type: 'Feature';
  geometry: {
    type: 'Polygon';
    coordinates: number[][][];
  };
  properties: {
    gers_id: string;
    name?: string | null;
    height?: number | null;
    [key: string]: any;
  };
}

export interface AddressFeature {
  id: string;
  lon: number;
  lat: number;
  house_number?: string | null;
  street_name?: string | null;
  formatted?: string | null;
}

export interface SplitUnit {
  address_id: string;
  unit_geometry: GeoJSON.Polygon;
  unit_number: string;
  unit_index: number;
  validation: 'passed' | 'warning' | 'failed';
  area_sqm: number;
}

export interface SplitResult {
  status: 'success' | 'error';
  building_id: string;
  units?: SplitUnit[];
  parent_type: 'townhouse' | 'apartment' | 'duplex' | 'triplex' | 'small_multifamily';
  split_method: 'obb_linear' | 'weighted' | 'apartment_placeholder';
  split_signature?: string;
  error_type?: string;
  error_message?: string;
}

export type SplitAxisMode = 'auto' | 'long' | 'short';

export interface BuildingSplitOverride {
  split_axis_mode?: SplitAxisMode | null;
  reverse_order?: boolean | null;
}

export interface RecalculateTownhouseUnitsInput {
  campaignId: string;
  parentBuildingId: string;
  buildingRowId?: string | null;
  linkedAddressIds?: string[];
  override?: BuildingSplitOverride;
  overtureRelease?: string;
}

export interface RecalculateTownhouseUnitsResult {
  parent_building_id: string;
  linked_address_ids: string[];
  units_created: number;
  recalculated: boolean;
  cleared: boolean;
  reason?: 'missing_geometry' | 'single_or_no_unit' | 'split_failed' | 'save_failed';
}

export interface BuildingAnalysis {
  building_id: string;
  building: BuildingFeature;
  unit_count: number;
  addresses: AddressFeature[];
  classification: 'townhouse' | 'apartment' | 'small_multifamily';
  aspect_ratio: number;
  area_sqm: number;
  is_l_shaped: boolean;
}

export interface SplitErrorRecord {
  campaign_id: string;
  building_id: string;
  building_geometry: any;
  error_type: 'validation_failed' | 'geometry_complex' | 'address_mismatch' | 
              'split_failed' | 'self_intersection' | 'insert_failed';
  error_message: string;
  address_count: number;
  address_ids: string[];
  address_positions: Array<{
    address_id: string;
    lon: number;
    lat: number;
    house_number?: string;
  }>;
  suggested_action: 'manual_split' | 'merge_units' | 'flag_apartment' | 
                    'create_placeholders' | 'skip_building';
}

export interface TownhouseSplitSummary {
  total_buildings: number;
  townhouses_detected: number;
  apartments_skipped: number;
  units_created: number;
  errors_logged: number;
  avg_units_per_townhouse: number;
  results: SplitterResult[];
}

export interface SplitterResult {
  building_id: string;
  is_townhouse: boolean;
  units_count: number;
}

// ============================================================================
// GEOMETRY UTILITIES - Web Mercator Projection
// ============================================================================

/**
 * Convert longitude/latitude to Web Mercator meters
 */
function lonLatToMeters(lon: number, lat: number): [number, number] {
  const x = lon * 20037508.34 / 180;
  const y = Math.log(Math.tan((90 + lat) * Math.PI / 360)) / (Math.PI / 180);
  const y_m = y * 20037508.34 / 180;
  return [x, y_m];
}

/**
 * Convert Web Mercator meters back to longitude/latitude
 */
function metersToLonLat(x: number, y: number): [number, number] {
  const lon = x * 180 / 20037508.34;
  const lat = 180 / Math.PI * (2 * Math.atan(Math.exp(y * Math.PI / 20037508.34)) - Math.PI / 2);
  return [lon, lat];
}

/**
 * Clip polygon ring against start/end distances along axis
 * Uses Sutherland-Hodgman algorithm adapted for axis-aligned clipping
 */
function clipRingByAxis(
  ring: [number, number][], 
  axis: [number, number],
  origin: [number, number],
  start: number, 
  end: number
): [number, number][] | null {
  
  // Project all points to meters and onto axis
  const projected = ring.map(([lon, lat]) => {
    const [x, y] = lonLatToMeters(lon, lat);
    // Distance from origin along axis
    const dist = (x - origin[0]) * axis[0] + (y - origin[1]) * axis[1];
    return { lon, lat, x, y, dist };
  });

  const result: [number, number][] = [];
  
  // Helper: interpolate between two points at target distance
  const interpolate = (
    p1: typeof projected[0], 
    p2: typeof projected[0], 
    targetDist: number
  ): [number, number] => {
    const t = (targetDist - p1.dist) / (p2.dist - p1.dist);
    const x = p1.x + t * (p2.x - p1.x);
    const y = p1.y + t * (p2.y - p1.y);
    return metersToLonLat(x, y);
  };

  // First pass: clip against start boundary (keep dist >= start)
  let current = projected[projected.length - 1];
  for (const next of projected) {
    const insideCurrent = current.dist >= start;
    const insideNext = next.dist >= start;
    
    if (insideCurrent && insideNext) {
      result.push([next.lon, next.lat]);
    } else if (insideCurrent && !insideNext) {
      result.push(interpolate(current, next, start));
    } else if (!insideCurrent && insideNext) {
      result.push(interpolate(current, next, start));
      result.push([next.lon, next.lat]);
    }
    current = next;
  }

  if (result.length < 3) return null;

  // Second pass: clip against end boundary (keep dist <= end)
  const projected2 = result.map(([lon, lat]) => {
    const [x, y] = lonLatToMeters(lon, lat);
    const dist = (x - origin[0]) * axis[0] + (y - origin[1]) * axis[1];
    return { lon, lat, x, y, dist };
  });

  const result2: [number, number][] = [];
  current = projected2[projected2.length - 1];
  
  for (const next of projected2) {
    const insideCurrent = current.dist <= end;
    const insideNext = next.dist <= end;
    
    if (insideCurrent && insideNext) {
      result2.push([next.lon, next.lat]);
    } else if (insideCurrent && !insideNext) {
      result2.push(interpolate(current, next, end));
    } else if (!insideCurrent && insideNext) {
      result2.push(interpolate(current, next, end));
      result2.push([next.lon, next.lat]);
    }
    current = next;
  }

  if (result2.length < 3) return null;
  
  // Close the ring
  if (result2[0][0] !== result2[result2.length - 1][0] || 
      result2[0][1] !== result2[result2.length - 1][1]) {
    result2.push(result2[0]);
  }

  return result2;
}

/**
 * Shrink polygon inward by inset distance to create visual gaps between units
 * Uses vertex normal method - moves each vertex along the angle bisector
 */
function shrinkPolygon(
  ring: [number, number][], 
  insetMeters: number
): [number, number][] {
  if (ring.length < 4) return ring; // Need at least triangle
  
  const insetM = insetMeters;
  const shrunk: [number, number][] = [];
  const n = ring.length - 1; // Exclude closing point for processing
  
  for (let i = 0; i < n; i++) {
    const prev = ring[(i - 1 + n) % n];
    const curr = ring[i];
    const next = ring[(i + 1) % n];
    
    // Convert to meters
    const [px, py] = lonLatToMeters(prev[0], prev[1]);
    const [cx, cy] = lonLatToMeters(curr[0], curr[1]);
    const [nx, ny] = lonLatToMeters(next[0], next[1]);
    
    // Vector from curr to prev (incoming edge)
    const v1x = px - cx;
    const v1y = py - cy;
    const v1len = Math.sqrt(v1x * v1x + v1y * v1y);
    
    // Vector from curr to next (outgoing edge)
    const v2x = nx - cx;
    const v2y = ny - cy;
    const v2len = Math.sqrt(v2x * v2x + v2y * v2y);
    
    if (v1len === 0 || v2len === 0) {
      shrunk.push([curr[0], curr[1]]); // Degenerate, keep original
      continue;
    }
    
    // Normalize edge vectors
    const u1x = v1x / v1len;
    const u1y = v1y / v1len;
    const u2x = v2x / v2len;
    const u2y = v2y / v2len;
    
    // Angle bisector (pointing inward for CCW polygon)
    const bisectX = u1x + u2x;
    const bisectY = u1y + u2y;
    const bisectLen = Math.sqrt(bisectX * bisectX + bisectY * bisectY);
    
    if (bisectLen === 0) {
      // 180 degree angle (straight line), move perpendicular
      const perpX = -u1y;
      const perpY = u1x;
      const newX = cx + perpX * insetM;
      const newY = cy + perpY * insetM;
      const [newLon, newLat] = metersToLonLat(newX, newY);
      shrunk.push([newLon, newLat]);
    } else {
      // Move along bisector
      const bisectUnitX = bisectX / bisectLen;
      const bisectUnitY = bisectY / bisectLen;
      
      // Calculate offset distance (need to divide by sin(half_angle) for correct inset)
      const cosHalfAngle = bisectLen / 2;
      const sinHalfAngle = Math.sqrt(1 - cosHalfAngle * cosHalfAngle);
      const offsetDist = sinHalfAngle > 0.01 ? insetM / sinHalfAngle : insetM;
      
      const newX = cx + bisectUnitX * offsetDist;
      const newY = cy + bisectUnitY * offsetDist;
      const [newLon, newLat] = metersToLonLat(newX, newY);
      shrunk.push([newLon, newLat]);
    }
  }
  
  // Close the ring
  if (shrunk.length > 0) {
    shrunk.push([...shrunk[0]]);
  }
  
  return shrunk;
}

/**
 * Create a unit polygon by slicing the building perpendicular to street edge
 */
function createUnitPolygon(
  buildingGeom: GeoJSON.Polygon,
  sortedAddresses: Array<{ lon: number; lat: number; house_number?: string | null; id: string }>,
  targetUnitIndex: number,
  streetEdgeP1: [number, number],
  streetEdgeP2: [number, number]
): GeoJSON.Polygon | null {

  // Calculate axis direction (street edge direction in meters)
  const [sx, sy] = lonLatToMeters(streetEdgeP1[0], streetEdgeP1[1]);
  const [ex, ey] = lonLatToMeters(streetEdgeP2[0], streetEdgeP2[1]);
  const dx = ex - sx;
  const dy = ey - sy;
  const len = Math.sqrt(dx * dx + dy * dy);
  
  if (len === 0) return null;
  
  const axis: [number, number] = [dx / len, dy / len];

  // Get outer ring
  const outerRing = buildingGeom.coordinates[0] as [number, number][];

  // Project all vertices to find min/max range for this building
  const projected = outerRing.map(([lon, lat]) => {
    const [x, y] = lonLatToMeters(lon, lat);
    const dist = (x - sx) * axis[0] + (y - sy) * axis[1];
    return dist;
  });
  
  const minDist = Math.min(...projected);
  const maxDist = Math.max(...projected);
  const totalRange = maxDist - minDist;

  // Calculate slice boundaries
  const unitCount = sortedAddresses.length;
  const sliceWidth = totalRange / unitCount;
  
  const start = minDist + (targetUnitIndex * sliceWidth);
  const end = start + sliceWidth;
  
  // Handle last unit (include any rounding errors)
  const actualEnd = targetUnitIndex === unitCount - 1 ? maxDist + 0.001 : end;

  // Clip the polygon
  const clippedRing = clipRingByAxis(outerRing, axis, [sx, sy], start, actualEnd);
  
  if (!clippedRing) {
    console.log(`[TownhouseSplitter] Slice ${targetUnitIndex} produced invalid geometry`);
    return null;
  }

  // Calculate area to check it's not degenerate (at least 10 m²)
  const area = calculatePolygonArea(clippedRing);
  if (area < 10) {
    console.log(`[TownhouseSplitter] Slice ${targetUnitIndex} too small: ${area.toFixed(1)}m²`);
    return null;
  }

  // SHRINK: Inset polygon by 0.3m to create visual gaps between units
  const shrunkRing = shrinkPolygon(clippedRing, 0.3);
  
  // Verify shrink didn't break the polygon
  const shrunkArea = calculatePolygonArea(shrunkRing);
  if (shrunkArea < 5) {
    console.log(`[TownhouseSplitter] Slice ${targetUnitIndex} too small after shrink, using original`);
    return {
      type: 'Polygon',
      coordinates: [clippedRing]
    };
  }

  return {
    type: 'Polygon',
    coordinates: [shrunkRing]
  };
}

function parseGeoJSONGeometry(value: unknown): GeoJSON.Geometry | null {
  if (!value) return null;
  if (typeof value === 'string') {
    try {
      return parseGeoJSONGeometry(JSON.parse(value));
    } catch {
      return null;
    }
  }
  if (typeof value !== 'object') return null;
  const geometry = value as GeoJSON.Geometry;
  return typeof geometry.type === 'string' && Array.isArray((geometry as any).coordinates)
    ? geometry
    : null;
}

function parsePolygonGeometry(value: unknown): GeoJSON.Polygon | null {
  const geometry = parseGeoJSONGeometry(value);
  if (!geometry) return null;
  if (geometry.type === 'Polygon') return geometry;
  if (geometry.type === 'MultiPolygon') {
    const coordinates = geometry.coordinates?.[0];
    return coordinates ? { type: 'Polygon', coordinates } : null;
  }
  return null;
}

function parsePointCoordinates(value: unknown): [number, number] | null {
  const geometry = parseGeoJSONGeometry(value);
  if (!geometry || geometry.type !== 'Point') return null;
  const coordinates = geometry.coordinates;
  const lon = coordinates?.[0];
  const lat = coordinates?.[1];
  return typeof lon === 'number' && Number.isFinite(lon) &&
    typeof lat === 'number' && Number.isFinite(lat)
    ? [lon, lat]
    : null;
}

function edgeLengthMeters(p1: number[], p2: number[]): number {
  const [x1, y1] = lonLatToMeters(p1[0], p1[1]);
  const [x2, y2] = lonLatToMeters(p2[0], p2[1]);
  return Math.hypot(x2 - x1, y2 - y1);
}

/**
 * Calculate polygon area using shoelace formula
 */
function calculatePolygonArea(coords: number[][]): number {
  let area = 0;
  const n = coords.length;
  
  for (let i = 0; i < n - 1; i++) {
    const [x1, y1] = lonLatToMeters(coords[i][0], coords[i][1]);
    const [x2, y2] = lonLatToMeters(coords[i + 1][0], coords[i + 1][1]);
    area += x1 * y2 - x2 * y1;
  }
  
  return Math.abs(area) / 2;
}

// ============================================================================
// MAIN SERVICE CLASS
// ============================================================================

export class TownhouseSplitterService {
  private supabase: SupabaseClient;

  constructor(supabase: SupabaseClient) {
    this.supabase = supabase;
  }

  /**
   * Rebuild the persisted unit polygons for one parent building after manual
   * address edits or split-direction changes.
   */
  async recalculateBuildingUnits(
    input: RecalculateTownhouseUnitsInput
  ): Promise<RecalculateTownhouseUnitsResult> {
    const parentBuildingId = input.buildingRowId || input.parentBuildingId;
    const parentIdentifiers = Array.from(
      new Set(
        [input.parentBuildingId, input.buildingRowId, parentBuildingId]
          .filter((value): value is string => Boolean(value))
      )
    );

    const [building, linkedAddresses, persistedOverride] = await Promise.all([
      this.loadParentBuildingFeature(input.campaignId, input.parentBuildingId, input.buildingRowId ?? null),
      this.loadLinkedAddresses(input.campaignId, input.parentBuildingId, input.buildingRowId ?? null, input.linkedAddressIds ?? []),
      this.loadSplitOverride(input.campaignId, input.parentBuildingId),
    ]);

    if (!building) {
      await this.clearUnits(input.campaignId, parentIdentifiers);
      return {
        parent_building_id: parentBuildingId,
        linked_address_ids: linkedAddresses.map((address) => address.id),
        units_created: 0,
        recalculated: false,
        cleared: true,
        reason: 'missing_geometry',
      };
    }

    if (linkedAddresses.length < 2) {
      await this.clearUnits(input.campaignId, parentIdentifiers);
      await this.updateBuildingLinkClassification(input.campaignId, input.buildingRowId ?? null, linkedAddresses.length);
      return {
        parent_building_id: parentBuildingId,
        linked_address_ids: linkedAddresses.map((address) => address.id),
        units_created: 0,
        recalculated: false,
        cleared: true,
        reason: 'single_or_no_unit',
      };
    }

    const override = {
      ...persistedOverride,
      ...input.override,
    };
    const analysis = this.analyzeBuildingFromAddresses(parentBuildingId, building, linkedAddresses);
    const result = this.splitBuilding(analysis, override);

    if (result.status !== 'success' || !result.units?.length) {
      await this.clearUnits(input.campaignId, parentIdentifiers);
      await this.logSplitError(input.campaignId, analysis, result);
      return {
        parent_building_id: parentBuildingId,
        linked_address_ids: linkedAddresses.map((address) => address.id),
        units_created: 0,
        recalculated: false,
        cleared: true,
        reason: 'split_failed',
      };
    }

    const saved = await this.saveUnits(input.campaignId, result, input.overtureRelease ?? 'manual');
    await this.updateBuildingLinkClassification(input.campaignId, input.buildingRowId ?? null, result.units.length);

    return {
      parent_building_id: parentBuildingId,
      linked_address_ids: linkedAddresses.map((address) => address.id),
      units_created: saved ? result.units.length : 0,
      recalculated: saved,
      cleared: true,
      reason: saved ? undefined : 'save_failed',
    };
  }

  /**
   * Main entry point: Process all multi-unit buildings in a campaign
   */
  async processCampaignTownhouses(
    campaignId: string,
    buildingsGeoJSON: { features: BuildingFeature[] },
    overtureRelease: string = '2026-01-21.0'
  ): Promise<TownhouseSplitSummary> {
    console.log(`[TownhouseSplitter] Processing campaign ${campaignId}`);

    try {
      // 1. Fetch addresses linked to buildings
      const { data: links, error: linksError } = await this.supabase
        .from('building_address_links')
        .select(`
          building_id,
          address_id,
          match_type,
          confidence,
          building_area_sqm,
          is_multi_unit,
          unit_count,
          campaign_addresses:campaign_addresses!inner (
            id,
            formatted,
            house_number,
            street_name,
            geom
          )
        `)
        .eq('campaign_id', campaignId)
        .eq('is_multi_unit', true);

      if (linksError) {
        throw new Error(`Failed to fetch links: ${linksError.message}`);
      }

      if (!links || links.length === 0) {
        console.log('[TownhouseSplitter] No multi-unit buildings found');
        return {
          total_buildings: 0,
          townhouses_detected: 0,
          apartments_skipped: 0,
          units_created: 0,
          errors_logged: 0,
          avg_units_per_townhouse: 0,
          results: [],
        };
      }

      // 2. Group by building
      const buildingGroups = this.groupLinksByBuilding(links);
      console.log(`[TownhouseSplitter] Found ${buildingGroups.size} multi-unit buildings`);

      // 3. Analyze each building
      const analyses: BuildingAnalysis[] = [];
      for (const [buildingId, buildingLinks] of buildingGroups) {
        const building = buildingsGeoJSON.features.find(
          b => b.properties.gers_id === buildingId
        );
        
        if (!building) {
          console.warn(`[TownhouseSplitter] Building ${buildingId} not found in GeoJSON`);
          continue;
        }

        const analysis = this.analyzeBuilding(building, buildingLinks);
        analyses.push(analysis);
      }

      // 4. Process each building
      const summary: TownhouseSplitSummary = {
        total_buildings: analyses.length,
        townhouses_detected: 0,
        apartments_skipped: 0,
        units_created: 0,
        errors_logged: 0,
        avg_units_per_townhouse: 0,
        results: [],
      };

      let totalTownhouseUnits = 0;

      console.log(`[TownhouseSplitter] Processing ${analyses.length} building analyses`);

      for (const analysis of analyses) {
        console.log(`[TownhouseSplitter] Building ${analysis.building_id}: classification=${analysis.classification}, units=${analysis.unit_count}`);
        summary.results.push({
          building_id: analysis.building_id,
          is_townhouse: analysis.classification === 'townhouse',
          units_count: analysis.unit_count,
        });

        if (analysis.classification === 'apartment') {
          // Analysis logged but persistence gated by feature flag
          if (!isUnitPersistenceEnabled()) {
            console.log(`[TownhouseSplitter] Skipping apartment placeholder creation for ${analysis.building_id} (flag off), ${analysis.unit_count} units`);
            summary.apartments_skipped++;
            continue;
          }
          
          const result = await this.createApartmentPlaceholders(campaignId, analysis, overtureRelease);
          if (result.status === 'success') {
            summary.apartments_skipped++;
            summary.units_created += result.units?.length || 0;
          }
        } else {
          // Split townhouse or small_multifamily
          const result = this.splitBuilding(analysis);
          
          if (result.status === 'success' && result.units) {
            // Gate persistence behind feature flag
            if (!isUnitPersistenceEnabled()) {
              console.log(`[TownhouseSplitter] Skipping unit persistence for ${analysis.building_id} (flag off), classification=${analysis.classification}, units=${result.units.length}`);
              summary.townhouses_detected++;
              totalTownhouseUnits += result.units.length;
              continue;
            }
            
            const saveSuccess = await this.saveUnits(campaignId, result, overtureRelease);
            if (saveSuccess) {
              summary.townhouses_detected++;
              summary.units_created += result.units.length;
              totalTownhouseUnits += result.units.length;
            }
          } else {
            await this.logSplitError(campaignId, analysis, result);
            summary.errors_logged++;
          }
        }
      }

      if (summary.townhouses_detected > 0) {
        summary.avg_units_per_townhouse = totalTownhouseUnits / summary.townhouses_detected;
      }

      return summary;

    } catch (error) {
      console.error('[TownhouseSplitter] Fatal error:', error);
      return {
        total_buildings: 0,
        townhouses_detected: 0,
        apartments_skipped: 0,
        units_created: 0,
        errors_logged: 1,
        avg_units_per_townhouse: 0,
        results: [],
      };
    }
  }

  private async loadParentBuildingFeature(
    campaignId: string,
    parentBuildingId: string,
    buildingRowId: string | null
  ): Promise<BuildingFeature | null> {
    if (buildingRowId) {
      const { data, error } = await this.supabase
        .from('buildings')
        .select('id, gers_id, geom, height_m, height')
        .eq('campaign_id', campaignId)
        .eq('id', buildingRowId)
        .maybeSingle();

      if (!error && data) {
        const row = data as { id: string; gers_id: string | null; geom: unknown; height_m?: number | null; height?: number | null };
        const geometry = parsePolygonGeometry(row.geom);
        if (geometry) {
          return {
            type: 'Feature',
            geometry,
            properties: {
              gers_id: row.id,
              height: row.height_m ?? row.height ?? null,
              public_building_id: row.gers_id ?? row.id,
            },
          };
        }
      }
    }

    const { data: cache } = await this.supabase
      .from('campaign_polished_building_features')
      .select('feature_collection')
      .eq('campaign_id', campaignId)
      .maybeSingle();

    const features = ((cache as { feature_collection?: { features?: unknown[] } } | null)
      ?.feature_collection?.features ?? []) as Array<{
        type?: string;
        id?: unknown;
        geometry?: unknown;
        properties?: Record<string, unknown>;
      }>;
    const targetIds = new Set([parentBuildingId, buildingRowId].filter(Boolean).map((value) => String(value).toLowerCase()));

    for (const feature of features) {
      const props = feature.properties ?? {};
      const identifiers = [
        feature.id,
        props.id,
        props.gers_id,
        props.public_building_id,
        props.canonical_building_id,
        props.building_id,
      ]
        .filter((value): value is string => typeof value === 'string' && value.trim().length > 0)
        .map((value) => value.toLowerCase());
      if (!identifiers.some((identifier) => targetIds.has(identifier))) continue;
      const geometry = parsePolygonGeometry(feature.geometry);
      if (!geometry) continue;
      return {
        type: 'Feature',
        geometry,
        properties: {
          ...props,
          gers_id: buildingRowId ?? parentBuildingId,
          height: typeof props.height_m === 'number' ? props.height_m : typeof props.height === 'number' ? props.height : null,
        },
      };
    }

    return null;
  }

  private async loadLinkedAddresses(
    campaignId: string,
    parentBuildingId: string,
    buildingRowId: string | null,
    seedAddressIds: string[]
  ): Promise<AddressFeature[]> {
    const addressIds = new Set(seedAddressIds.map((id) => id.toLowerCase()));

    if (buildingRowId) {
      const { data: links, error } = await this.supabase
        .from('building_address_links')
        .select('address_id')
        .eq('campaign_id', campaignId)
        .eq('building_id', buildingRowId);
      if (!error) {
        for (const row of (links ?? []) as Array<{ address_id: string }>) {
          if (row.address_id) addressIds.add(row.address_id.toLowerCase());
        }
      }
    }

    const addressRows: Array<{
      id: string;
      formatted: string | null;
      house_number: string | null;
      street_name: string | null;
      geom: unknown;
    }> = [];

    if (addressIds.size > 0) {
      const { data, error } = await this.supabase
        .from('campaign_addresses')
        .select('id, formatted, house_number, street_name, geom')
        .eq('campaign_id', campaignId)
        .in('id', Array.from(addressIds));
      if (error) throw new Error(`Failed to load linked townhouse addresses: ${error.message}`);
      addressRows.push(...((data ?? []) as typeof addressRows));
    }

    const identifiers = Array.from(
      new Set([parentBuildingId, buildingRowId].filter((value): value is string => Boolean(value)))
    );
    for (const identifier of identifiers) {
      const column = identifier === buildingRowId ? 'building_id' : 'building_gers_id';
      const { data, error } = await this.supabase
        .from('campaign_addresses')
        .select('id, formatted, house_number, street_name, geom')
        .eq('campaign_id', campaignId)
        .eq(column, identifier);
      if (error) continue;
      addressRows.push(...((data ?? []) as typeof addressRows));
    }

    const seen = new Set<string>();
    const addresses: AddressFeature[] = [];
    for (const row of addressRows) {
      const key = row.id.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      const coordinate = parsePointCoordinates(row.geom);
      if (!coordinate) continue;
      addresses.push({
        id: row.id,
        lon: coordinate[0],
        lat: coordinate[1],
        house_number: row.house_number,
        street_name: row.street_name,
        formatted: row.formatted,
      });
    }

    return addresses;
  }

  private async loadSplitOverride(
    campaignId: string,
    parentBuildingId: string
  ): Promise<BuildingSplitOverride> {
    const { data, error } = await this.supabase
      .from('building_split_overrides')
      .select('split_axis_mode, reverse_order')
      .eq('campaign_id', campaignId)
      .eq('parent_building_id', parentBuildingId)
      .maybeSingle();

    if (error || !data) return {};
    const row = data as { split_axis_mode: string | null; reverse_order: boolean | null };
    return {
      split_axis_mode: row.split_axis_mode === 'long' || row.split_axis_mode === 'short' ? row.split_axis_mode : 'auto',
      reverse_order: row.reverse_order === true,
    };
  }

  private async clearUnits(campaignId: string, parentBuildingIds: string[]): Promise<void> {
    const ids = Array.from(new Set(parentBuildingIds.filter(Boolean)));
    for (const parentBuildingId of ids) {
      const { error } = await this.supabase
        .from('building_units')
        .update({
          lifecycle_state: 'superseded',
          superseded_at: new Date().toISOString(),
        })
        .eq('campaign_id', campaignId)
        .eq('parent_building_id', parentBuildingId)
        .eq('lifecycle_state', 'active');
      if (error) {
        console.warn('[TownhouseSplitter] Error clearing existing units:', error.message);
      }
    }
  }

  private async updateBuildingLinkClassification(
    campaignId: string,
    buildingRowId: string | null,
    unitCount: number
  ): Promise<void> {
    if (!buildingRowId) return;
    const normalizedUnitCount = Math.max(unitCount, 1);
    const { error } = await this.supabase
      .from('building_address_links')
      .update({
        is_multi_unit: normalizedUnitCount > 1,
        unit_count: normalizedUnitCount,
        unit_arrangement: normalizedUnitCount > 1 ? 'horizontal' : 'single',
        building_class: normalizedUnitCount > 1 ? 'townhouse' : null,
      })
      .eq('campaign_id', campaignId)
      .eq('building_id', buildingRowId);
    if (error) {
      console.warn('[TownhouseSplitter] Error updating building link classification:', error.message);
    }
  }

  private analyzeBuildingFromAddresses(
    buildingId: string,
    building: BuildingFeature,
    addresses: AddressFeature[]
  ): BuildingAnalysis {
    const fauxLinks = addresses.map((address) => ({
      address_id: address.id,
      campaign_addresses: {
        id: address.id,
        formatted: address.formatted,
        house_number: address.house_number,
        street_name: address.street_name,
        geom: { coordinates: [address.lon, address.lat] },
      },
    }));
    return {
      ...this.analyzeBuilding(building, fauxLinks),
      building_id: buildingId,
      addresses,
    };
  }

  /**
   * Split building into units using proper polygon clipping
   */
  private splitBuilding(analysis: BuildingAnalysis, override: BuildingSplitOverride = {}): SplitResult {
    const { building, addresses, building_id } = analysis;
    const nUnits = addresses.length;

    console.log(`[TownhouseSplitter] Splitting ${building_id} into ${nUnits} units`);

    try {
      const coords = canonicalizePolygonRing(building.geometry.coordinates[0]);
      const canonicalGeometry: GeoJSON.Polygon = { type: 'Polygon', coordinates: [coords] };
      
      const bestEdgeIndex = this.selectSplitAxisEdge(coords, addresses, override.split_axis_mode ?? 'auto');

      let streetEdgeP1 = coords[bestEdgeIndex] as [number, number];
      let streetEdgeP2 = coords[bestEdgeIndex + 1] as [number, number];
      if (
        streetEdgeP1[0] > streetEdgeP2[0] ||
        (streetEdgeP1[0] === streetEdgeP2[0] && streetEdgeP1[1] > streetEdgeP2[1])
      ) {
        [streetEdgeP1, streetEdgeP2] = [streetEdgeP2, streetEdgeP1];
      }

      // Order addresses along the street edge
      let orderedAddrs = orderTownhouseAddressesAlongAxis(
        addresses,
        streetEdgeP1,
        streetEdgeP2
      );
      if (override.reverse_order === true) {
        orderedAddrs = orderedAddrs.reverse();
      }

      // Create units using proper polygon clipping
      const units: SplitUnit[] = [];
      
      for (let i = 0; i < nUnits; i++) {
        const unitGeometry = createUnitPolygon(
          canonicalGeometry,
          orderedAddrs,
          i,
          streetEdgeP1,
          streetEdgeP2
        );

        if (!unitGeometry) {
          console.warn(`[TownhouseSplitter] Failed to create geometry for unit ${i}`);
          continue;
        }

        const addr = orderedAddrs[i];
        const area = calculatePolygonArea(unitGeometry.coordinates[0]);

        // Validate address is in unit (with buffer)
        const addrPoint: [number, number] = [addr.lon, addr.lat];
        const unitRing = unitGeometry.coordinates[0];
        let validation: SplitUnit['validation'] = 'passed';
        
        if (!this.isPointInPolygon(addrPoint, unitRing)) {
          if (!this.isPointNearPolygon(addrPoint, unitRing, 15)) {
            validation = 'failed';
          } else {
            validation = 'warning';
          }
        }

        units.push({
          address_id: addr.id,
          unit_geometry: unitGeometry,
          unit_number: addr.house_number || String(i + 1),
          unit_index: i,
          validation,
          area_sqm: area,
        });
      }

      if (units.length === 0) {
        return {
          status: 'error',
          building_id,
          error_type: 'split_failed',
          error_message: 'No valid unit geometries created',
          parent_type: 'townhouse',
          split_method: 'obb_linear',
        };
      }

      return {
        status: 'success',
        building_id,
        units,
        parent_type: analysis.classification === 'townhouse' ? 'townhouse' : 'small_multifamily',
        split_method: 'obb_linear',
        split_signature: townhouseSplitSignature({
          parentBuildingId: building_id,
          ring: coords,
          orderedAddresses: orderedAddrs,
          splitMethod: `obb_linear:${override.split_axis_mode ?? 'auto'}:${override.reverse_order === true}`,
        }),
      };

    } catch (error) {
      console.error('[TownhouseSplitter] Error splitting building:', error);
      return {
        status: 'error',
        building_id,
        error_type: 'split_failed',
        error_message: error instanceof Error ? error.message : 'Unknown error',
        parent_type: 'townhouse',
        split_method: 'obb_linear',
      };
    }
  }

  private selectSplitAxisEdge(
    coords: number[][],
    addresses: AddressFeature[],
    mode: SplitAxisMode
  ): number {
    if (coords.length < 2) return 0;

    if (mode === 'long' || mode === 'short') {
      let selectedIndex = 0;
      let selectedLength = mode === 'long' ? -Infinity : Infinity;

      for (let i = 0; i < coords.length - 1; i++) {
        const length = edgeLengthMeters(coords[i], coords[i + 1]);
        if ((mode === 'long' && length > selectedLength) || (mode === 'short' && length < selectedLength)) {
          selectedLength = length;
          selectedIndex = i;
        }
      }

      return selectedIndex;
    }

    let bestEdgeIndex = 0;
    let bestEdgeScore = -Infinity;

    for (let i = 0; i < coords.length - 1; i++) {
      const p1 = coords[i];
      const p2 = coords[i + 1];

      let score = 0;
      for (const addr of addresses) {
        const dist = this.pointToLineDistance([addr.lon, addr.lat], p1, p2);
        if (dist < 20) {
          score += 1 / (dist + 1);
        }
      }

      if (score > bestEdgeScore) {
        bestEdgeScore = score;
        bestEdgeIndex = i;
      }
    }

    return bestEdgeIndex;
  }

  /**
   * Create apartment placeholder circles (7+ units)
   */
  private async createApartmentPlaceholders(
    campaignId: string,
    analysis: BuildingAnalysis,
    overtureRelease: string
  ): Promise<SplitResult> {
    const { building, addresses, building_id } = analysis;
    
    console.log(`[TownhouseSplitter] Creating apartment placeholders for ${building_id}`);

    const centroid = this.calculateCentroid(building.geometry.coordinates[0]);
    
    const orderedAddresses = [...addresses].sort((a, b) =>
      canonicalAddressIdentity(a).localeCompare(canonicalAddressIdentity(b))
    );
    const units: SplitUnit[] = orderedAddresses.map((addr, i) => {
      const circle = this.createCirclePolygon([addr.lon, addr.lat], 2);
      
      return {
        address_id: addr.id,
        unit_geometry: circle,
        unit_number: addr.house_number || `Unit ${i + 1}`,
        unit_index: i,
        validation: 'passed',
        area_sqm: Math.PI * 2 * 2,
      };
    });

    const result: SplitResult = {
      status: 'success',
      building_id,
      units,
      parent_type: 'apartment',
      split_method: 'apartment_placeholder',
      split_signature: townhouseSplitSignature({
        parentBuildingId: building_id,
        ring: canonicalizePolygonRing(building.geometry.coordinates[0]),
        orderedAddresses,
        splitMethod: 'apartment_placeholder',
      }),
    };

    await this.saveUnits(campaignId, result, overtureRelease);
    return result;
  }

  /**
   * Analyze building characteristics
   */
  private analyzeBuilding(building: BuildingFeature, links: any[]): BuildingAnalysis {
    const coords = building.geometry.coordinates[0];
    const n = coords.length - 1;
    
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const [x, y] of coords) {
      minX = Math.min(minX, x);
      maxX = Math.max(maxX, x);
      minY = Math.min(minY, y);
      maxY = Math.max(maxY, y);
    }
    
    const [mx1, my1] = lonLatToMeters(minX, minY);
    const [mx2, my2] = lonLatToMeters(maxX, maxY);
    const widthM = Math.abs(mx2 - mx1);
    const heightM = Math.abs(my2 - my1);
    const aspectRatio = Math.max(widthM, heightM) / Math.min(widthM, heightM);

    const addresses: AddressFeature[] = links.map(l => ({
      id: l.address_id,
      lon: l.campaign_addresses.geom.coordinates[0],
      lat: l.campaign_addresses.geom.coordinates[1],
      house_number: l.campaign_addresses.house_number,
      street_name: l.campaign_addresses.street_name,
      formatted: l.campaign_addresses.formatted,
    }));

    const unitCount = addresses.length;
    let classification: BuildingAnalysis['classification'];
    
    if (unitCount > 6) {
      classification = 'apartment';
    } else if (unitCount >= 2 && unitCount <= 6 && aspectRatio > 1.2) {
      classification = 'townhouse';
    } else {
      classification = 'small_multifamily';
    }

    return {
      building_id: building.properties.gers_id,
      building,
      unit_count: unitCount,
      addresses,
      classification,
      aspect_ratio: aspectRatio,
      area_sqm: calculatePolygonArea(coords),
      is_l_shaped: coords.length > 7,
    };
  }

  /**
   * Save units to database
   */
  private async saveUnits(
    campaignId: string,
    result: SplitResult,
    _overtureRelease: string
  ): Promise<boolean> {
    if (!result.units || result.units.length === 0) return false;

    const records = result.units.map((u) => ({
      id: deterministicTownhouseUnitId({
        campaignId,
        parentBuildingId: result.building_id,
        unitIndex: u.unit_index,
      }),
      campaign_id: campaignId,
      parent_building_id: result.building_id,
      address_id: u.address_id,
      unit_number: u.unit_number,
      unit_index: u.unit_index,
      stable_key: townhouseUnitStableKey({
        parentBuildingId: result.building_id,
        unitIndex: u.unit_index,
      }),
      split_version: TOWNHOUSE_SPLIT_VERSION,
      split_signature: result.split_signature,
      lifecycle_state: 'active',
      superseded_at: null,
      unit_geometry: u.unit_geometry,
      parent_building_area: u.area_sqm,
      split_method: result.split_method,
      parent_type: result.parent_type,
      validation_status: u.validation,
    }));

    const { error } = await this.supabase.rpc('upsert_building_units_deterministic', {
      p_campaign_id: campaignId,
      p_parent_building_id: result.building_id,
      p_units: records,
    });

    if (error) {
      console.error('[TownhouseSplitter] Error saving units:', error.message);
      return false;
    }

    console.log(`[TownhouseSplitter] Saved ${records.length} units`);
    return true;
  }

  /**
   * Log split errors for manual review
   */
  private async logSplitError(
    campaignId: string,
    analysis: BuildingAnalysis,
    result: SplitResult
  ): Promise<void> {
    const record: SplitErrorRecord = {
      campaign_id: campaignId,
      building_id: analysis.building_id,
      building_geometry: analysis.building.geometry,
      error_type: (result.error_type as any) || 'split_failed',
      error_message: result.error_message || 'Unknown error',
      address_count: analysis.unit_count,
      address_ids: analysis.addresses.map(a => a.id),
      address_positions: analysis.addresses.map(a => ({
        address_id: a.id,
        lon: a.lon,
        lat: a.lat,
        house_number: a.house_number || undefined,
      })),
      suggested_action: 'manual_split',
    };

    await this.supabase.from('building_split_errors').insert(record);
  }

  // Helper methods
  private groupLinksByBuilding(links: any[]): Map<string, any[]> {
    const groups = new Map<string, any[]>();
    for (const link of links) {
      const existing = groups.get(link.building_id) || [];
      existing.push(link);
      groups.set(link.building_id, existing);
    }
    return groups;
  }

  private pointToLineDistance(point: [number, number], lineStart: number[], lineEnd: number[]): number {
    const [px, py] = point;
    const [x1, y1] = lineStart;
    const [x2, y2] = lineEnd;
    
    const dx = x2 - x1;
    const dy = y2 - y1;
    const len = Math.sqrt(dx * dx + dy * dy);
    
    if (len === 0) return Math.sqrt((px - x1) ** 2 + (py - y1) ** 2);
    
    const t = Math.max(0, Math.min(1, ((px - x1) * dx + (py - y1) * dy) / (len * len)));
    const projX = x1 + t * dx;
    const projY = y1 + t * dy;
    
    return Math.sqrt((px - projX) ** 2 + (py - projY) ** 2);
  }

  private isPointInPolygon(point: [number, number], polygon: number[][]): boolean {
    const [x, y] = point;
    let inside = false;
    
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      const [xi, yi] = polygon[i];
      const [xj, yj] = polygon[j];
      
      const intersect = ((yi > y) !== (yj > y)) &&
        (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
      
      if (intersect) inside = !inside;
    }
    
    return inside;
  }

  private isPointNearPolygon(point: [number, number], polygon: number[][], bufferMeters: number): boolean {
    const bufferDeg = bufferMeters / 111320;
    
    for (let i = 0; i < polygon.length - 1; i++) {
      const dist = this.pointToLineDistance(point, polygon[i], polygon[i + 1]);
      if (dist < bufferDeg) return true;
    }
    
    return false;
  }

  private calculateCentroid(polygon: number[][]): [number, number] {
    let cx = 0, cy = 0;
    for (const [x, y] of polygon) {
      cx += x;
      cy += y;
    }
    return [cx / polygon.length, cy / polygon.length];
  }

  private createCirclePolygon(center: [number, number], radiusMeters: number): GeoJSON.Polygon {
    const points: number[][] = [];
    const radiusDeg = radiusMeters / 111320;
    
    for (let i = 0; i <= 32; i++) {
      const angle = (i / 32) * 2 * Math.PI;
      const x = center[0] + radiusDeg * Math.cos(angle);
      const y = center[1] + radiusDeg * Math.sin(angle);
      points.push([x, y]);
    }
    
    return { type: 'Polygon', coordinates: [points] };
  }
}
