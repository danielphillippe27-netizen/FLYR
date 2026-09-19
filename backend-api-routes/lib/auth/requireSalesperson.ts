import { redirect } from 'next/navigation';
import { getSupabaseServerClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/server';
import { resolveDashboardAccessLevel } from '@/app/api/_utils/workspace';
import { resolveSalespersonForUser } from '@/lib/dialer/salesperson-settings';
import type { User } from '@supabase/supabase-js';

/**
 * Server-only guard: ensures the current user is an active salesperson.
 * Use at the top of salesperson-only pages (/dialer, /scraper, /inbox, /scripts, etc.)
 *
 * - No user               → redirect to the Sales login
 * - Active salesperson row → allow access, regardless of workspace role
 * - Not in salespeople table → redirect to the Sales login
 *
 * @returns { user } for use in the page
 */
export async function requireSalesperson(): Promise<{ user: User }> {
  if (process.env.NODE_ENV === 'development' && process.env.DEV_SALES_PREVIEW === '1') {
    return { user: { id: 'local-sales-preview' } as User };
  }
  const supabase = await getSupabaseServerClient();
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    redirect('/login');
  }

  const admin = createAdminClient();
  const access = await resolveDashboardAccessLevel(admin, user.id);

  const salesperson = await resolveSalespersonForUser(admin, {
    userId: user.id,
    email: user.email?.trim().toLowerCase() ?? null,
    workspaceId: access.workspaceId,
  });

  if (!salesperson) {
    redirect('/login?error=not_salesperson');
  }

  return { user };
}
