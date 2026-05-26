import assert from 'node:assert/strict';
import test from 'node:test';

import { isLinkableBuildingFootprint } from '../buildingFootprintFilter';

test('keeps explicit residential buildings below the generic area threshold', () => {
  assert.equal(
    isLinkableBuildingFootprint({
      properties: {
        building_type: 'residential',
        area_sqm: 24,
      },
    }),
    true
  );
});

test('still drops explicit accessory structures even when they are large enough', () => {
  assert.equal(
    isLinkableBuildingFootprint({
      properties: {
        building_type: 'garage',
        area_sqm: 80,
      },
    }),
    false
  );
});

test('still drops untyped tiny footprints as likely noise or sheds', () => {
  assert.equal(
    isLinkableBuildingFootprint({
      properties: {
        area_sqm: 24,
      },
    }),
    false
  );
});
