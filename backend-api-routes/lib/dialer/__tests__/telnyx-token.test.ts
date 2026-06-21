import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  cleanTelnyxToken,
  telnyxIdentifierMisconfiguration,
  validateTelnyxAccessTokenPayload,
} from '../telnyx-token';

describe('Telnyx token helpers', () => {
  it('cleans quoted text/plain JWT responses', () => {
    assert.equal(cleanTelnyxToken('  "abc.def.ghi"  '), 'abc.def.ghi');
  });

  it('accepts Telnyx Voice SDK access token payloads', () => {
    assert.equal(
      validateTelnyxAccessTokenPayload({
        iss: 'telnyx_telephony',
        aud: 'telnyx_telephony',
        typ: 'access',
        tel_token: 'embedded-token',
        exp: Math.floor(Date.now() / 1000) + 60,
      }),
      null
    );
  });

  it('explains locally signed API-key issuer JWTs', () => {
    const error = validateTelnyxAccessTokenPayload({
      iss: 'SKe_not_a_real_api_key_id',
      aud: 'telnyx_telephony',
      typ: 'access',
      tel_token: 'embedded-token',
      exp: Math.floor(Date.now() / 1000) + 60,
    });

    assert.match(error ?? '', /API key ID/);
    assert.match(error ?? '', /locally signed JWT/);
  });

  it('blocks API-key-shaped values as telephony credential IDs', () => {
    assert.match(telnyxIdentifierMisconfiguration('KEY_not_a_real_secret') ?? '', /secret API key/);
    assert.match(telnyxIdentifierMisconfiguration('SKe_not_a_real_api_key_id') ?? '', /API key ID/);
    assert.equal(telnyxIdentifierMisconfiguration('5c7ac7d0-db65-4f11-98e1-eec0d1d5c6ae'), null);
  });
});
