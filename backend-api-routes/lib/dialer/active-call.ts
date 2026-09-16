import { z } from 'zod';

export const ACTIVE_CALL_LEASE_MS = 90_000;
export const activeCallSchema = z.object({
  id: z.string().min(1).max(128),
  name: z.string().trim().min(1).max(300),
  phone: z.string().max(80).nullable(),
  phase: z.enum(['connecting', 'connected']),
  startedAt: z.string().datetime(),
  connectedAt: z.string().datetime().nullable(),
});

export const activeCallSyncSchema = z.object({
  workspaceId: z.string().uuid(),
  deviceId: z.string().uuid(),
  platform: z.enum(['ios', 'web']),
  call: activeCallSchema.nullable(),
});

export type SharedActiveCall = z.infer<typeof activeCallSchema> & {
  deviceId: string;
  platform: 'ios' | 'web';
  expiresAt: string;
};
