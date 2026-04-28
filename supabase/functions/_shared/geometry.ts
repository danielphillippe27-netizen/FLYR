// supabase/functions/_shared/geometry.ts
// Shared geometry utilities for Edge Functions

/**
 * Creates a rectangle polygon around a point in WGS84 coordinates
 * @param lat Latitude in degrees (WGS84)
 * @param lng Longitude in degrees (WGS84)
 * @param widthMeters Width of rectangle in meters (east-west span)
 * @param heightMeters Height of rectangle in meters (north-south span)
 * @returns GeoJSON Polygon with a single linear ring
 */
export function createRectangleAroundPoint(
  lat: number,
  lng: number,
  widthMeters: number = 12,
  heightMeters: number = 10
): GeoJSON.Polygon {
  // Constants for meter-to-degree conversion
  const METERS_PER_DEGREE_LAT = 111320; // Approximately constant for latitude
  const METERS_PER_DEGREE_LON_BASE = 111320; // Base for longitude at equator

  // Convert meters to degrees
  // Latitude: constant conversion
  const halfHeightDeg = (heightMeters / 2) / METERS_PER_DEGREE_LAT;
  
  // Longitude: varies by latitude
  const metersPerDegreeLon = METERS_PER_DEGREE_LON_BASE * Math.cos((lat * Math.PI) / 180);
  const halfWidthDeg = (widthMeters / 2) / metersPerDegreeLon;

  // Create 5-point closed ring in [lng, lat] order (GeoJSON format)
  const coordinates: number[][] = [
    [lng - halfWidthDeg, lat + halfHeightDeg], // top-left
    [lng + halfWidthDeg, lat + halfHeightDeg], // top-right
    [lng + halfWidthDeg, lat - halfHeightDeg], // bottom-right
    [lng - halfWidthDeg, lat - halfHeightDeg], // bottom-left
    [lng - halfWidthDeg, lat + halfHeightDeg], // back to top-left (close ring)
  ];

  return {
    type: "Polygon",
    coordinates: [coordinates], // Single linear ring
  };
}









