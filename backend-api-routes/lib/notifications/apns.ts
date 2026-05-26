import { createSign } from 'crypto';

type PushEnvironment = 'sandbox' | 'production';

type ApnsPayload = {
  aps: {
    alert: {
      title: string;
      body?: string;
    };
    sound?: string;
    'thread-id'?: string;
  };
  [key: string]: unknown;
};

type SendApnsNotificationInput = {
  token: string;
  environment: PushEnvironment;
  payload: ApnsPayload;
};

type ApnsConfig = {
  keyId: string;
  teamId: string;
  bundleId: string;
  privateKey: string;
};

let cachedJwt: { token: string; issuedAtSeconds: number } | null = null;

function apnsConfig(): ApnsConfig | null {
  const keyId = process.env.APNS_KEY_ID?.trim();
  const teamId = process.env.APNS_TEAM_ID?.trim();
  const bundleId = process.env.APNS_BUNDLE_ID?.trim();
  const privateKey = process.env.APNS_PRIVATE_KEY?.replace(/\\n/g, '\n').trim();

  if (!keyId || !teamId || !bundleId || !privateKey) {
    return null;
  }

  return { keyId, teamId, bundleId, privateKey };
}

function base64Url(value: Buffer | string): string {
  return Buffer.from(value)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function apnsJwt(config: ApnsConfig): string {
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (cachedJwt && nowSeconds - cachedJwt.issuedAtSeconds < 50 * 60) {
    return cachedJwt.token;
  }

  const header = base64Url(JSON.stringify({ alg: 'ES256', kid: config.keyId }));
  const claims = base64Url(JSON.stringify({ iss: config.teamId, iat: nowSeconds }));
  const signingInput = `${header}.${claims}`;
  const signer = createSign('SHA256');
  signer.update(signingInput);
  signer.end();
  const signature = signer.sign({
    key: config.privateKey,
    dsaEncoding: 'ieee-p1363',
  });
  const token = `${signingInput}.${base64Url(signature)}`;
  cachedJwt = { token, issuedAtSeconds: nowSeconds };
  return token;
}

function apnsHost(environment: PushEnvironment): string {
  return environment === 'production'
    ? 'https://api.push.apple.com'
    : 'https://api.sandbox.push.apple.com';
}

export async function sendApnsNotification(input: SendApnsNotificationInput) {
  const config = apnsConfig();
  if (!config) {
    throw new Error('APNs environment variables are not configured');
  }

  const response = await fetch(`${apnsHost(input.environment)}/3/device/${input.token}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${apnsJwt(config)}`,
      'apns-topic': config.bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    },
    body: JSON.stringify(input.payload),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`APNs send failed (${response.status}): ${body || response.statusText}`);
  }
}
