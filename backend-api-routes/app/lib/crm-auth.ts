import { createCipheriv, createDecipheriv, randomBytes } from "crypto";
const CRM_ENCRYPTION_KEY = process.env.CRM_ENCRYPTION_KEY!;
const CRM_ENCRYPTION_KEY_VERSION = parseInt(process.env.CRM_ENCRYPTION_KEY_VERSION ?? "1", 10);

function getEncryptionKey(): Buffer {
  if (!CRM_ENCRYPTION_KEY || CRM_ENCRYPTION_KEY.length < 32) {
    throw new Error("CRM_ENCRYPTION_KEY must be at least 32 chars (hex or raw)");
  }
  const buf = Buffer.from(CRM_ENCRYPTION_KEY, "hex");
  if (buf.length === 32) return buf;
  return Buffer.from(CRM_ENCRYPTION_KEY.slice(0, 32), "utf8");
}

type Blob = { iv: string; tag: string; ciphertext: string };

export function encryptCRMSecret(plaintext: string): string {
  const key = getEncryptionKey();
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv, { authTagLength: 16 });
  const enc = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  const blob = {
    v: 1,
    key_version: CRM_ENCRYPTION_KEY_VERSION,
    iv: iv.toString("base64"),
    tag: tag.toString("base64"),
    ciphertext: enc.toString("base64"),
  };
  return Buffer.from(JSON.stringify(blob)).toString("base64");
}

export function decrypt(encryptedBase64: string): string {
  const key = getEncryptionKey();
  const json = Buffer.from(encryptedBase64, "base64").toString("utf8");
  const blob = JSON.parse(json) as Blob;
  const iv = Buffer.from(blob.iv, "base64");
  const tag = Buffer.from(blob.tag, "base64");
  const ciphertext = Buffer.from(blob.ciphertext, "base64");
  const decipher = createDecipheriv("aes-256-gcm", key, iv, { authTagLength: 16 });
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString("utf8");
}

export async function getCRMSecretForUser(
  supabaseAdmin: any,
  userId: string,
  provider: string
): Promise<string | null> {
  const { data: conn } = await supabaseAdmin
    .from("crm_connections")
    .select("id")
    .eq("user_id", userId)
    .eq("provider", provider)
    .maybeSingle();
  if (!conn?.id) return null;

  const { data: secret } = await supabaseAdmin
    .from("crm_connection_secrets")
    .select("encrypted_api_key")
    .eq("connection_id", conn.id)
    .maybeSingle();
  if (!secret?.encrypted_api_key) return null;

  return decrypt(secret.encrypted_api_key);
}

export async function getFubApiKeyForUser(
  supabaseAdmin: any,
  userId: string
): Promise<string | null> {
  return getCRMSecretForUser(supabaseAdmin, userId, "fub");
}

export async function getBoldTrailTokenForUser(
  supabaseAdmin: any,
  userId: string
): Promise<string | null> {
  return getCRMSecretForUser(supabaseAdmin, userId, "boldtrail");
}
