import assert from "node:assert/strict";
import { test } from "node:test";
import { geoJSONPolygonToMultiPolygonEWKT } from "./manual-building-geometry";

test("converts a GeoJSON Polygon to closed MultiPolygon EWKT", () => {
  const ewkt = geoJSONPolygonToMultiPolygonEWKT({
    type: "Polygon",
    coordinates: [[
      [-79.1, 43.1],
      [-79.2, 43.1],
      [-79.2, 43.2],
    ]],
  });

  assert.equal(
    ewkt,
    "SRID=4326;MULTIPOLYGON(((-79.1 43.1,-79.2 43.1,-79.2 43.2,-79.1 43.1)))"
  );
});

test("preserves MultiPolygon geometry and rejects malformed coordinates", () => {
  assert.equal(
    geoJSONPolygonToMultiPolygonEWKT({
      type: "MultiPolygon",
      coordinates: [[[[-79.1, 43.1], [-79.2, 43.1], [-79.2, 43.2], [-79.1, 43.1]]]],
    }),
    "SRID=4326;MULTIPOLYGON(((-79.1 43.1,-79.2 43.1,-79.2 43.2,-79.1 43.1)))"
  );

  assert.equal(
    geoJSONPolygonToMultiPolygonEWKT({
      type: "Polygon",
      coordinates: [[[-79.1, 43.1], ["bad", 43.1], [-79.2, 43.2]]],
    }),
    null
  );
});
