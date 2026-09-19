import { countPersonalDirectMessages } from '@/lib/salesperson/social-metrics';
import { loadPersonalDemoMetrics } from '@/lib/salesperson/demo-metrics';
import { loadPersonalOutreach } from '@/lib/salesperson/outreach-metrics';
import { NextResponse, type NextRequest } from 'next/server';
import { resolveAccessContext } from '../../access/_utils';
import { createAdminClient } from '@/lib/supabase/server';
import { resolveSalespersonForUser } from '@/lib/dialer/salesperson-settings';
import {
  metricComparison,
  rangesForPeriod,
  type ComparisonRange,
  type PerformancePeriod,
} from '@/lib/salesperson/performance-comparison';
import {
  loadRevenueSnapshotNear,
  loadSalespersonStripeRevenue,
  saveRevenueSnapshot,
  type SalespersonRevenue,
} from '@/lib/salesperson/revenue-snapshots';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type AdminClient = ReturnType<typeof createAdminClient>;

type ProfileRow = {
  full_name?: string | null;
  email?: string | null;
};

type ActivityMetrics = {
  calls: number;
  answers: number;
  outboundMessages: number;
  inboundMessages: number;
  emails: number;
  demosSent: number;
  directMessages: number;
  posts: number;
  meetingsBooked: number;
  meetingsHeld: number;
  signups: number;
};

type CountResult = {
  count: number | null;
  error: { message?: string } | null;
};

function cleanText(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function periodFromRequest(request: NextRequest): PerformancePeriod {
  const raw = request.nextUrl.searchParams.get('period')?.toLowerCase();
  if (raw === 'weekly' || raw === 'monthly' || raw === 'yearly') return raw;
  return 'daily';
}

async function profileForUser(
  admin: AdminClient,
  userId: string
): Promise<ProfileRow | null> {
  const { data, error } = await admin
    .from('profiles')
    .select('full_name,email')
    .eq('id', userId)
    .maybeSingle();

  if (error) {
    console.warn('[salesperson/performance] profile lookup failed', {
      userId,
      message: error.message,
    });
    return null;
  }
  return (data as ProfileRow | null) ?? null;
}

function countOrZero(label: string, result: CountResult): number {
  if (result.error) {
    console.warn(`[salesperson/performance] ${label} lookup failed`, result.error);
    return 0;
  }
  return result.count ?? 0;
}

async function loadActivityMetrics(
  admin: AdminClient,
  params: {
    userId: string;
    workspaceId: string;
    salespersonId: string | null;
    referralCode: string | null;
    range: ComparisonRange;
  }
): Promise<ActivityMetrics> {
  const start = params.range.start.toISOString();
  const end = params.range.end.toISOString();

  const callsQuery = admin
    .from('dialer_calls')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', params.userId)
    .eq('workspace_id', params.workspaceId)
    .eq('direction', 'outbound')
    .gte('created_at', start)
    .lt('created_at', end);
  const answersQuery = admin
    .from('dialer_calls')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', params.userId)
    .eq('workspace_id', params.workspaceId)
    .eq('direction', 'outbound')
    .not('answered_at', 'is', null)
    .gte('created_at', start)
    .lt('created_at', end);
  const outreachQuery = loadPersonalOutreach(admin, {
    userId: params.userId, workspaceId: params.workspaceId, start, end,
  });
  const directMessagesQuery = countPersonalDirectMessages(admin, params.userId, start, end);
  const postsQuery = admin
    .from('social_posts')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', params.userId)
    .eq('status', 'published')
    .gte('published_at', start)
    .lt('published_at', end);
  const meetingsBookedQuery = admin
    .from('calendar_events')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', params.userId)
    .is('deleted_at', null)
    .in('event_type', ['appointment', 'meeting'])
    .gte('start_at', start)
    .lt('start_at', end);
  const meetingsHeldQuery = params.salespersonId
    ? admin
        .from('salesperson_meeting_conferences')
        .select('id', { count: 'exact', head: true })
        .eq('salesperson_id', params.salespersonId)
        .not('end_time', 'is', null)
        .gte('prospect_participant_count', 1)
        .gte('duration_seconds', 300)
        .gte('end_time', start)
        .lt('end_time', end)
    : Promise.resolve({ count: 0, error: null });
  const signupsQuery = params.referralCode
    ? admin
        .from('workspaces')
        .select('id', { count: 'exact', head: true })
        .ilike('referral_code_used', params.referralCode)
        .gte('created_at', start)
        .lt('created_at', end)
    : Promise.resolve({ count: 0, error: null });

  const [
    calls,
    answers,
    outreach,
    directMessages,
    posts,
    meetingsBooked,
    meetingsHeld,
    signups,
  ] = (await Promise.all([
    callsQuery,
    answersQuery,
    outreachQuery,
    directMessagesQuery,
    postsQuery,
    meetingsBookedQuery,
    meetingsHeldQuery,
    signupsQuery,
  ]));

  return {
    calls: countOrZero('calls', calls),
    answers: countOrZero('answers', answers),
    ...outreach,
    directMessages: countOrZero('direct messages', directMessages),
    posts: countOrZero('posts', posts),
    meetingsBooked: countOrZero('meetings booked', meetingsBooked),
    meetingsHeld: countOrZero('meetings held', meetingsHeld),
    signups: countOrZero('sign ups', signups),
  };
}

function mrrWithPreviousCurrencies(
  current: SalespersonRevenue,
  previous: Record<string, number> | null
): Record<string, number> {
  const currencies = new Set([
    ...Object.keys(current.mrrByCurrency),
    ...Object.keys(previous ?? {}),
  ]);
  return Object.fromEntries(
    [...currencies].sort().map((currency) => [currency, current.mrrByCurrency[currency] ?? 0])
  );
}

export async function GET(request: NextRequest) {
  try {
    const requestedWorkspaceId = cleanText(request.nextUrl.searchParams.get('workspaceId'));
    const context = await resolveAccessContext(request, {
      workspaceId: requestedWorkspaceId,
    });
    if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    if (!context.workspace?.id || !context.hasAccess) {
      return NextResponse.json(
        { error: 'Salesperson workspace is not available.' },
        { status: 403 }
      );
    }
    if (requestedWorkspaceId && requestedWorkspaceId !== context.workspace.id) {
      return NextResponse.json(
        { error: 'Salesperson workspace is not available.' },
        { status: 403 }
      );
    }

    const period = periodFromRequest(request);
    const ranges = rangesForPeriod(
      period,
      request.nextUrl.searchParams.get('timezone')
    );
    const admin = createAdminClient();
    const profile = await profileForUser(admin, context.user.id);
    const email = cleanText(profile?.email) ?? context.user.email ?? '';
    const fullName =
      cleanText(profile?.full_name) ??
      cleanText(context.user.email?.split('@')[0]) ??
      'Salesperson';
    const salesperson = await resolveSalespersonForUser(admin, {
      userId: context.user.id,
      email,
      workspaceId: context.workspace.id,
    });

    const activityParams = {
      userId: context.user.id,
      workspaceId: context.workspace.id,
      salespersonId: salesperson?.id ?? null,
      referralCode: cleanText(salesperson?.referral_code),
    };
    const [currentMetrics, previousMetrics] = await Promise.all([
      loadActivityMetrics(admin, { ...activityParams, range: ranges.current }),
      loadActivityMetrics(admin, { ...activityParams, range: ranges.previous }),
    ]);

    const [currentDemo, previousDemo] = await Promise.all([
      loadPersonalDemoMetrics(admin, activityParams.salespersonId, ranges.current.start.toISOString(), ranges.current.end.toISOString()),
      loadPersonalDemoMetrics(admin, activityParams.salespersonId, ranges.previous.start.toISOString(), ranges.previous.end.toISOString()),
    ]);

    let revenue: SalespersonRevenue = { paidTeams: 0, mrrByCurrency: {} };
    let previousRevenue: Awaited<ReturnType<typeof loadRevenueSnapshotNear>> = null;
    if (salesperson?.id) {
      // An unavailable revenue query must not persist a false zero-MRR snapshot.
      revenue = await loadSalespersonStripeRevenue(admin, salesperson.id, context.user.id);
      try {
        previousRevenue = await loadRevenueSnapshotNear(
          admin,
          salesperson.id,
          ranges.previous.end,
          context.user.id
        );
      } catch (snapshotError) {
        console.warn('[salesperson/performance] previous revenue snapshot failed', snapshotError);
      }
      try {
        await saveRevenueSnapshot(admin, {
          salespersonId: salesperson.id,
          userId: context.user.id,
          revenue,
        });
      } catch (snapshotError) {
        console.warn('[salesperson/performance] revenue snapshot save failed', snapshotError);
      }
    }

    const currentMrr = mrrWithPreviousCurrencies(
      revenue,
      previousRevenue?.mrrByCurrency ?? null
    );
    const mrrComparisons = Object.fromEntries(
      Object.keys(currentMrr).map((currency) => [
        currency,
        metricComparison(
          currentMrr[currency],
          previousRevenue ? previousRevenue.mrrByCurrency[currency] ?? 0 : null
        ),
      ])
    );

    return NextResponse.json({
      period,
      timezone: ranges.timezone,
      range: {
        start: ranges.current.start.toISOString(),
        end: ranges.current.end.toISOString(),
      },
      comparisonRange: {
        start: ranges.previous.start.toISOString(),
        end: ranges.previous.end.toISOString(),
      },
      salesperson: {
        id: salesperson?.id ?? context.user.id,
        fullName,
        email,
        referralCode: salesperson?.referral_code ?? null,
        workspaceId: context.workspace.id,
        trackedLink: null,
      },
      outreach: {
        calls: currentMetrics.calls,
        answers: currentMetrics.answers,
        messages: currentMetrics.outboundMessages,
        outboundMessages: currentMetrics.outboundMessages,
        inboundMessages: currentMetrics.inboundMessages,
        emails: currentMetrics.emails,
        demosSent: currentMetrics.demosSent,
        directMessages: currentMetrics.directMessages,
        posts: currentMetrics.posts,
        meetingsBooked: currentMetrics.meetingsBooked,
        meetingsHeld: currentMetrics.meetingsHeld,
      },
      links: {
        opens: currentDemo.opens,
        signups: currentMetrics.signups,
      },
      revenue: {
        payingUsers: revenue.paidTeams,
        paidTeams: revenue.paidTeams,
        mrrByCurrency: currentMrr,
      },
      comparisons: {
        outreach: {
          calls: metricComparison(currentMetrics.calls, previousMetrics.calls),
          answers: metricComparison(currentMetrics.answers, previousMetrics.answers),
          messages: metricComparison(
            currentMetrics.outboundMessages,
            previousMetrics.outboundMessages
          ),
          emails: metricComparison(currentMetrics.emails, previousMetrics.emails),
          demosSent: metricComparison(currentMetrics.demosSent, previousMetrics.demosSent),
          directMessages: metricComparison(
            currentMetrics.directMessages,
            previousMetrics.directMessages
          ),
          posts: metricComparison(currentMetrics.posts, previousMetrics.posts),
          meetingsBooked: metricComparison(
            currentMetrics.meetingsBooked,
            previousMetrics.meetingsBooked
          ),
          meetingsHeld: metricComparison(
            currentMetrics.meetingsHeld,
            previousMetrics.meetingsHeld
          ),
        },
        links: {
          opens: metricComparison(currentDemo.opens, previousDemo.opens),
          signups: metricComparison(currentMetrics.signups, previousMetrics.signups),
        },
        revenue: {
          paidTeams: metricComparison(
            revenue.paidTeams,
            previousRevenue?.paidTeams ?? null
          ),
          mrrByCurrency: mrrComparisons,
          snapshotCapturedAt: previousRevenue?.capturedAt.toISOString() ?? null,
        },
      },
      demoVideo: currentDemo.demoVideo,
    });
  } catch (error) {
    console.error('[salesperson/performance]', error);
    return NextResponse.json(
      { error: 'Failed to load salesperson performance.' },
      { status: 500 }
    );
  }
}
