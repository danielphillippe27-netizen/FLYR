type GeoJSONPolygonLike = {
  type?: unknown;
  coordinates?: unknown;
};

type Position = [number, number];

function pointFromCoordinate(value: unknown): Position | null {
  if (!Array.isArray(value) || value.length < 2) return null;
  const longitude = Number(value[0]);
  const latitude = Number(value[1]);
  if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) return null;
  return [longitude, latitude];
}

function samePoint(left: Position, right: Position): boolean {
  return left[0] === right[0] && left[1] === right[1];
}

function formatNumber(value: number): string {
  return Object.is(value, -0) ? "0" : String(value);
}

function formatPoint(point: Position): string {
  return `${formatNumber(point[0])} ${formatNumber(point[1])}`;
}

function ringToWKT(value: unknown): string | null {
  if (!Array.isArray(value)) return null;

  const points = value.map(pointFromCoordinate);
  if (points.some((point) => point === null)) return null;

  const closed = points as Position[];
  if (closed.length < 3) return null;

  const first = closed[0];
  const last = closed[closed.length - 1];
  if (!samePoint(first, last)) {
    closed.push(first);
  }

  return closed.length >= 4 ? `(${closed.map(formatPoint).join(",")})` : null;
}

function polygonToWKT(value: unknown): string | null {
  if (!Array.isArray(value) || value.length === 0) return null;

  const rings = value.map(ringToWKT);
  if (rings.some((ring) => ring === null)) return null;

  return `(${(rings as string[]).join(",")})`;
}

export function geoJSONPolygonToMultiPolygonEWKT(geometry: unknown): string | null {
  if (!geometry || typeof geometry !== "object") return null;

  const candidate = geometry as GeoJSONPolygonLike;
  if (candidate.type === "Polygon") {
    const polygon = polygonToWKT(candidate.coordinates);
    return polygon ? `SRID=4326;MULTIPOLYGON(${polygon})` : null;
  }

  if (candidate.type === "MultiPolygon") {
    if (!Array.isArray(candidate.coordinates) || candidate.coordinates.length === 0) {
      return null;
    }

    const polygons = candidate.coordinates.map(polygonToWKT);
    if (polygons.some((polygon) => polygon === null)) return null;

    return `SRID=4326;MULTIPOLYGON(${(polygons as string[]).join(",")})`;
  }

  return null;
}
