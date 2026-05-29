import assert from 'node:assert/strict';
import test from 'node:test';

import { isLinkableBuildingFootprint } from '../buildingFootprintFilter';

test('drops explicit residential buildings below the generic area threshold', () => {
  assert.equal(
    isLinkableBuildingFootprint({
      properties: {
        building_type: 'residential',
        area_sqm: 24,
      },
    }),
    false
  );
});

test('keeps explicit accessory structures when they meet the generic area threshold', () => {
  assert.equal(
    isLinkableBuildingFootprint({
      properties: {
        building_type: 'garage',
        area_sqm: 80,
      },
    }),
    true
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
