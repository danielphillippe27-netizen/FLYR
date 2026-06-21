export type TelnyxJwtPayload = {
  aud?: string;
  exp?: number;
  iat?: number;
  iss?: string;
  jti?: string;
  nbf?: number;
  sub?: string;
  tel_token?: string;
  typ?: string;
};

export function decodeBase64Url(value: string): string {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
  return Buffer.from(padded, 'base64').toString('utf8');
}

export function decodeTelnyxJwt(token: string): TelnyxJwtPayload | null {
  const [, payload] = token.split('.');
  if (!payload) return null;

  try {
    return JSON.parse(decodeBase64Url(payload)) as TelnyxJwtPayload;
  } catch {
    return null;
  }
}

export function cleanTelnyxToken(body: string): string {
  const trimmed = body.trim();
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (typeof parsed === 'string') return parsed.trim();
    } catch {
      return trimmed.slice(1, -1).trim();
    }
  }
  return trimmed;
}

export function telnyxIdentifierMisconfiguration(value: string): string | null {
  const trimmed = value.trim();
  if (/^KEY/i.test(trimmed)) {
    return 'looks like a Telnyx secret API key. Set TELNYX_IOS_TELEPHONY_CREDENTIAL_ID to a Telnyx telephony credential ID, not TELNYX_API_KEY.';
  }
  if (/^SKe/i.test(trimmed)) {
    return 'looks like a Telnyx API key ID. Set TELNYX_IOS_TELEPHONY_CREDENTIAL_ID to a Telnyx telephony credential ID, not an API key ID.';
  }
  return null;
}

function claimDescription(value: string | undefined): string {
  if (!value) return 'missing';
  if (/^KEY/i.test(value)) return 'a Telnyx secret API key';
  if (/^SKe/i.test(value)) return `a Telnyx API key ID (${value.slice(0, 6)}...)`;
  return value;
}

export function validateTelnyxAccessTokenPayload(payload: TelnyxJwtPayload | null): string | null {
  if (!payload) return 'JWT payload could not be decoded';
  if (payload.iss !== 'telnyx_telephony') {
    const issuerMisconfiguration = payload.iss ? telnyxIdentifierMisconfiguration(payload.iss) : null;
    if (issuerMisconfiguration) {
      return `iss is ${claimDescription(payload.iss)}. The backend appears to be returning a locally signed JWT instead of the Telnyx access token response; ${issuerMisconfiguration}`;
    }
    return `iss is ${claimDescription(payload.iss)}, expected telnyx_telephony`;
  }
  if (payload.aud !== 'telnyx_telephony') return `aud is ${claimDescription(payload.aud)}, expected telnyx_telephony`;
  if (payload.typ !== 'access') return `typ is ${claimDescription(payload.typ)}, expected access`;
  if (!payload.tel_token) return 'tel_token is missing';
  if (typeof payload.exp !== 'number') return 'exp is missing';
  if (payload.exp * 1000 <= Date.now()) return 'token is expired';
  return null;
}
