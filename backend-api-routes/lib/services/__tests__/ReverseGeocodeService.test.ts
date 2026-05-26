/**
 * Reverse geocode service regression fixtures
 *
 * Run with: npx tsx lib/services/__tests__/ReverseGeocodeService.test.ts
 */

import { ReverseGeocodeService } from "../ReverseGeocodeService";

let testsPassed = 0;
let testsFailed = 0;

const originalFetch = globalThis.fetch;
const originalMapboxToken = process.env.MAPBOX_TOKEN;
const originalMapboxAccessToken = process.env.MAPBOX_ACCESS_TOKEN;
const originalNextPublicMapboxToken = process.env.NEXT_PUBLIC_MAPBOX_TOKEN;
const originalNextPublicMapboxAccessToken = process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN;

async function test(name: string, fn: () => void | Promise<void>) {
  try {
    await fn();
    console.log(`✓ ${name}`);
    testsPassed++;
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`✗ ${name}`);
    console.error(`  ${message}`);
    testsFailed++;
  }
}

function assertEqual(actual: unknown, expected: unknown, message?: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(message || `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function restoreEnv() {
  process.env.MAPBOX_TOKEN = originalMapboxToken;
  process.env.MAPBOX_ACCESS_TOKEN = originalMapboxAccessToken;
  process.env.NEXT_PUBLIC_MAPBOX_TOKEN = originalNextPublicMapboxToken;
  process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN = originalNextPublicMapboxAccessToken;
  globalThis.fetch = originalFetch;
}

async function main() {
  console.log("Running reverse geocode service fixtures...\n");

  await test("maps Mapbox address response into fallback address fields", async () => {
    process.env.MAPBOX_TOKEN = "pk.test-token";
    process.env.MAPBOX_ACCESS_TOKEN = "";
    process.env.NEXT_PUBLIC_MAPBOX_TOKEN = "";
    process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN = "";

    globalThis.fetch = (async (url: string | URL | Request) => {
      const requestUrl = String(url);
      if (!requestUrl.includes("types=address") || !requestUrl.includes("limit=1")) {
        throw new Error(`Unexpected Mapbox URL: ${requestUrl}`);
      }

      return {
        ok: true,
        json: async () => ({
          features: [
            {
              place_name: "84 Riverside, Drakenstein NU, Western Cape 7646, South Africa",
              address: "84",
              text: "Riverside",
              center: [19.01427, -33.734894],
              context: [
                { id: "place.123", text: "Drakenstein NU" },
                { id: "region.123", text: "Western Cape" },
                { id: "postcode.123", text: "7646" },
                { id: "country.123", text: "South Africa" },
              ],
            },
          ],
        }),
      } as Response;
    }) as typeof fetch;

    const result = await ReverseGeocodeService.mapboxReverseAddress({ lat: -33.7342, lng: 19.0145 });
    assertEqual(result, {
      formatted_address: "84 Riverside, Drakenstein NU, Western Cape 7646, South Africa",
      street_line: "84 Riverside",
      house_number: "84",
      street: "Riverside",
      locality: "Drakenstein NU",
      region: "Western Cape",
      postal_code: "7646",
      country: "South Africa",
      coordinate: {
        lng: 19.01427,
        lat: -33.734894,
      },
    });
  });

  await test("returns null when token is missing", async () => {
    process.env.MAPBOX_TOKEN = "";
    process.env.MAPBOX_ACCESS_TOKEN = "";
    process.env.NEXT_PUBLIC_MAPBOX_TOKEN = "";
    process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN = "";

    let fetchCalled = false;
    globalThis.fetch = (async () => {
      fetchCalled = true;
      throw new Error("fetch should not be called without a token");
    }) as typeof fetch;

    const result = await ReverseGeocodeService.mapboxReverseAddress({ lat: -33.7342, lng: 19.0145 });
    assertEqual(result, null);
    assertEqual(fetchCalled, false);
  });

  await test("uses NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN when backend token names are absent", async () => {
    process.env.MAPBOX_TOKEN = "";
    process.env.MAPBOX_ACCESS_TOKEN = "";
    process.env.NEXT_PUBLIC_MAPBOX_TOKEN = "";
    process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN = "pk.public-access-token";

    globalThis.fetch = (async (url: string | URL | Request) => {
      const requestUrl = String(url);
      if (!requestUrl.includes("access_token=pk.public-access-token")) {
        throw new Error(`Unexpected Mapbox token in URL: ${requestUrl}`);
      }

      return {
        ok: true,
        json: async () => ({
          features: [
            {
              place_name: "88 Main Street, Toronto, Ontario, Canada",
              address: "88",
              text: "Main Street",
              center: [-79.38, 43.65],
            },
          ],
        }),
      } as Response;
    }) as typeof fetch;

    const result = await ReverseGeocodeService.mapboxReverseAddress({ lat: 43.65, lng: -79.38 });
    assertEqual(result?.house_number, "88");
    assertEqual(result?.street_line, "88 Main Street");
  });

  await test("derives street line from formatted address when structured parts are incomplete", async () => {
    process.env.MAPBOX_TOKEN = "pk.test-token";
    process.env.MAPBOX_ACCESS_TOKEN = "";
    process.env.NEXT_PUBLIC_MAPBOX_TOKEN = "";
    process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN = "";

    globalThis.fetch = (async () => ({
      ok: true,
      json: async () => ({
        features: [
          {
            place_name: "5311 Green Velvet Court, Orlando, Florida 32808, United States",
            center: [-81.455, 28.602],
          },
        ],
      }),
    }) as Response) as typeof fetch;

    const result = await ReverseGeocodeService.mapboxReverseAddress({ lat: 28.602, lng: -81.455 });
    assertEqual(result?.street_line, "5311 Green Velvet Court");
  });

  await test("returns null on Mapbox API failure", async () => {
    process.env.MAPBOX_TOKEN = "pk.test-token";

    globalThis.fetch = (async () => ({
      ok: false,
      json: async () => ({ message: "Not Authorized - Invalid Token" }),
    }) as Response) as typeof fetch;

    const result = await ReverseGeocodeService.mapboxReverseAddress({ lat: -33.7342, lng: 19.0145 });
    assertEqual(result, null);
  });

  restoreEnv();

  if (testsFailed > 0) {
    console.error(`\n${testsFailed} test(s) failed, ${testsPassed} passed.`);
    process.exit(1);
  }

  console.log(`\nAll ${testsPassed} reverse geocode service tests passed.`);
}

main().catch((error: unknown) => {
  restoreEnv();
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});
