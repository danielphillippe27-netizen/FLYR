import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'crypto';
import { ImapFlow } from 'imapflow';
import nodemailer from 'nodemailer';
import type { SupabaseClient } from '@supabase/supabase-js';

export type ICloudEmailConnection = {
  id: string;
  workspace_id: string;
  user_id: string;
  email_address: string;
  authentication_email_address?: string | null;
  app_password_encrypted: string;
  is_active: boolean;
  last_uid: number | null;
  last_synced_at: string | null;
};

function encryptionKey(): Buffer {
  const secret = process.env.EMAIL_ENCRYPTION_KEY || process.env.CRM_ENCRYPTION_KEY;
  if (!secret) throw new Error('EMAIL_ENCRYPTION_KEY or CRM_ENCRYPTION_KEY is not configured.');
  return createHash('sha256').update(secret).digest();
}

export function encryptICloudPassword(value: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return ['v1', iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), ciphertext.toString('base64url')].join('.');
}

export function decryptICloudPassword(value: string): string {
  const [version, iv, tag, ciphertext] = value.split('.');
  if (version !== 'v1' || !iv || !tag || !ciphertext) throw new Error('Saved iCloud credential is invalid.');
  const decipher = createDecipheriv('aes-256-gcm', encryptionKey(), Buffer.from(iv, 'base64url'));
  decipher.setAuthTag(Buffer.from(tag, 'base64url'));
  return Buffer.concat([decipher.update(Buffer.from(ciphertext, 'base64url')), decipher.final()]).toString('utf8');
}

export async function iCloudConnection(admin: SupabaseClient, workspaceId: string, userId: string) {
  const { data, error } = await admin.from('email_connections').select('*')
    .eq('workspace_id', workspaceId).eq('user_id', userId).eq('provider', 'icloud').maybeSingle();
  if (error) throw error;
  return data as ICloudEmailConnection | null;
}

export function iCloudAuthenticationEmailAddress(connection: ICloudEmailConnection) {
  const savedAddress = connection.authentication_email_address?.trim().toLowerCase();
  if (savedAddress) return savedAddress;
  if (connection.email_address.trim().toLowerCase() === 'daniel@wolfgrid.app') {
    return 'daniel_phillippe@icloud.com';
  }
  return connection.email_address.trim().toLowerCase();
}

export function iCloudImap(connection: ICloudEmailConnection) {
  const authenticationEmailAddress = iCloudAuthenticationEmailAddress(connection);
  const authenticationUser = authenticationEmailAddress.split('@')[0] || authenticationEmailAddress;
  return new ImapFlow({
    host: 'imap.mail.me.com', port: 993, secure: true,
    auth: { user: authenticationUser, pass: decryptICloudPassword(connection.app_password_encrypted) },
    logger: false,
  });
}

export function iCloudSMTP(connection: ICloudEmailConnection) {
  return nodemailer.createTransport({
    host: 'smtp.mail.me.com', port: 587, secure: false, requireTLS: true,
    auth: { user: iCloudAuthenticationEmailAddress(connection), pass: decryptICloudPassword(connection.app_password_encrypted) },
  });
}

export async function verifyICloudCredentials(
  emailAddress: string,
  authenticationEmailAddress: string,
  appSpecificPassword: string,
) {
  const connection = {
    email_address: emailAddress,
    authentication_email_address: authenticationEmailAddress,
    app_password_encrypted: encryptICloudPassword(appSpecificPassword),
  } as ICloudEmailConnection;
  const imap = iCloudImap(connection);
  try {
    await imap.connect();
    await imap.mailboxOpen('INBOX', { readOnly: true });
  } finally {
    if (imap.usable) await imap.logout().catch(() => undefined);
  }
  await iCloudSMTP(connection).verify();
}

export async function sendICloudEmail(connection: ICloudEmailConnection, params: {
  to: string; subject: string; body: string; html?: string; inReplyTo?: string | null;
}) {
  return iCloudSMTP(connection).sendMail({
    from: connection.email_address,
    to: params.to,
    subject: params.subject,
    text: params.body,
    ...(params.html ? { html: params.html } : {}),
    ...(params.inReplyTo ? { inReplyTo: params.inReplyTo, references: [params.inReplyTo] } : {}),
  });
}
