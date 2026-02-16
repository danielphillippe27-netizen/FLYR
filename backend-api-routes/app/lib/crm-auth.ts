import { createDecipheriv } from "crypto";
import type { SupabaseClient } from "@supabase/supabase-js";

const CRM_ENCRYPTION_KEY = process.env.CRM_ENCRYPTION_KEY!;

function getEncryptionKey(): Buffer {
  if (!CRM_ENCRYPTION_KEY || CRM_ENCRYPTION_KEY.length < 32) {
    throw new Error("CRM_ENCRYPTION_KEY must be at least 32 chars (hex or raw)");
  }
  const buf = Buffer.from(CRM_ENCRYPTION_KEY, "hex");
  if (buf.length === 32) return buf;
  return Buffer.from(CRM_ENCRYPTION_KEY.slice(0, 32), "utf8");
}

type Blob = { iv: string; tag: string; ciphertext: string };

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

export async function getFubApiKeyForUser(
  supabaseAdmin: SupabaseClient,
  userId: string
): Promise<string | null> {
  const { data: conn } = await supabaseAdmin
    .from("crm_connections")
    .select("id")
    .eq("user_id", userId)
    .eq("provider", "fub")
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
