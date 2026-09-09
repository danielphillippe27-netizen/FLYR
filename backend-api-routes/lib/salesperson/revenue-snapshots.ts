import type { createAdminClient } from '@/lib/supabase/server';
import { isStripeSecretKeyConfigured } from '@/app/lib/billing/stripe-env';
import { stripe } from '@/lib/stripe';
import type Stripe from 'stripe';

type AdminClient = ReturnType<typeof createAdminClient>;

type SubscriptionReferralRow = {
  stripe_subscription_id?: string | null;
};

type RevenueSnapshotRow = {
  captured_at: string;
  paid_teams: number;
  mrr_by_currency: Record<string, number> | null;
};

export type SalespersonRevenue = {
  paidTeams: number;
  mrrByCurrency: Record<string, number>;
};

export type SalespersonRevenueSnapshot = SalespersonRevenue & {
  capturedAt: Date;
};

export function monthlyRecurringCents(item: Stripe.SubscriptionItem): number {
  const amount = (item.price.unit_amount ?? 0) * (item.quantity ?? 1);
  const recurring = item.price.recurring;
  if (!recurring || amount <= 0) return 0;

  const intervalCount = Math.max(1, recurring.interval_count);
  switch (recurring.interval) {
    case 'day':
      return Math.round((amount * 365) / (12 * intervalCount));
    case 'week':
      return Math.round((amount * 52) / (12 * intervalCount));
    case 'month':
      return Math.round(amount / intervalCount);
    case 'year':
      return Math.round(amount / (12 * intervalCount));
  }
}

async function requireRevenueOwner(admin: AdminClient, salespersonId: string, userId: string) {
  const { data, error } = await admin.from('salespeople').select('id')
    .eq('id', salespersonId).eq('user_id', userId).maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) throw new Error('Salesperson revenue owner not found.');
}

export async function loadSalespersonStripeRevenue(
  admin: AdminClient,
  salespersonId: string,
  userId: string
): Promise<SalespersonRevenue> {
  await requireRevenueOwner(admin, salespersonId, userId);
  const { data, error } = await admin
    .from('salesperson_referrals')
    .select('stripe_subscription_id')
    .eq('salesperson_id', salespersonId)
    .not('stripe_subscription_id', 'is', null);

  if (error) throw new Error(error.message);

  const subscriptionIds = [
    ...new Set(
      ((data ?? []) as SubscriptionReferralRow[])
        .map((row) => row.stripe_subscription_id?.trim())
        .filter((value): value is string => Boolean(value))
    ),
  ];

  if (subscriptionIds.length === 0) {
    return { paidTeams: 0, mrrByCurrency: {} };
  }

  if (!isStripeSecretKeyConfigured()) throw new Error('Revenue provider is not configured.');

  const results = await Promise.all(
    subscriptionIds.map((subscriptionId) =>
      stripe.subscriptions.retrieve(subscriptionId, {
        expand: ['items.data.price'],
      })
    )
  );

  let paidTeams = 0;
  const mrrByCurrency: Record<string, number> = {};
  for (const result of results) {
    if (result.status !== 'active') continue;
    paidTeams += 1;
    for (const item of result.items.data) {
      const currency = item.price.currency.toUpperCase();
      mrrByCurrency[currency] =
        (mrrByCurrency[currency] ?? 0) + monthlyRecurringCents(item);
    }
  }

  return { paidTeams, mrrByCurrency };
}

function capturedHour(value: Date): string {
  const hour = new Date(value);
  hour.setUTCMinutes(0, 0, 0);
  return hour.toISOString();
}

export async function saveRevenueSnapshot(
  admin: AdminClient,
  params: {
    salespersonId: string;
    userId: string;
    revenue: SalespersonRevenue;
    capturedAt?: Date;
  }
): Promise<void> {
  await requireRevenueOwner(admin, params.salespersonId, params.userId);
  const { error } = await admin.from('salesperson_revenue_snapshots').upsert(
    {
      salesperson_id: params.salespersonId,
      user_id: params.userId,
      captured_at: capturedHour(params.capturedAt ?? new Date()),
      paid_teams: params.revenue.paidTeams,
      mrr_by_currency: params.revenue.mrrByCurrency,
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'salesperson_id,captured_at' }
  );
  if (error) throw new Error(error.message);
}

export async function loadRevenueSnapshotNear(
  admin: AdminClient,
  salespersonId: string,
  target: Date,
  userId: string,
  toleranceMilliseconds = 90 * 60 * 1000
): Promise<SalespersonRevenueSnapshot | null> {
  const { data, error } = await admin
    .from('salesperson_revenue_snapshots')
    .select('captured_at,paid_teams,mrr_by_currency')
    .eq('salesperson_id', salespersonId)
    .eq('user_id', userId)
    .lte('captured_at', target.toISOString())
    .order('captured_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) throw new Error(error.message);
  const row = data as RevenueSnapshotRow | null;
  if (!row) return null;
  const capturedAt = new Date(row.captured_at);
  if (target.getTime() - capturedAt.getTime() > toleranceMilliseconds) return null;

  return {
    capturedAt,
    paidTeams: row.paid_teams,
    mrrByCurrency: row.mrr_by_currency ?? {},
  };
}
