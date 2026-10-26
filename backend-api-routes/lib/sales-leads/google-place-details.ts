import { getPlacesApiKey } from '@/lib/scraper/googlePlacesLeadSearch';
import { createAdminClient } from '@/lib/supabase/server';
import type { SalesLead } from '@/types/database';

type PlaceRefreshContext = {
  admin: ReturnType<typeof createAdminClient>;
  workspaceId: string;
  userId: string;
};

function clean(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

export async function refreshGooglePlaceDetails(context: PlaceRefreshContext, row: SalesLead): Promise<SalesLead> {
  const metadata = row.metadata && typeof row.metadata === 'object'
    ? row.metadata as Record<string, unknown>
    : {};
  const isGooglePlace = ['google_places', 'd2d_job_signals'].includes(row.source ?? '') ||
    clean(metadata.googlePlaceId) !== null;
  if (!isGooglePlace) return row;
  const placeId = clean(metadata.googlePlaceId) ?? clean(row.external_id);
  const apiKey = getPlacesApiKey();
  if (!placeId || !apiKey) return row;

  const checkedAt = clean(metadata.googleRatingCheckedAt);
  const checkedAtMs = checkedAt ? Date.parse(checkedAt) : NaN;
  if (Number.isFinite(checkedAtMs) && Date.now() - checkedAtMs < 24 * 60 * 60 * 1000) return row;
  if (typeof metadata.googleRating === 'number' &&
      typeof metadata.googleReviewCount === 'number' && clean(row.website)) return row;

  try {
    const response = await fetch(`https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`, {
      headers: {
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'rating,userRatingCount,websiteUri',
      },
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) {
      console.warn('[sales-leads] Google Place Details failed', response.status);
      return row;
    }
    const place = await response.json() as {
      rating?: number;
      userRatingCount?: number;
      websiteUri?: string;
    };
    const updatedMetadata = {
      ...metadata,
      googlePlaceId: placeId,
      ...(typeof place.rating === 'number' ? { googleRating: place.rating } : {}),
      ...(typeof place.userRatingCount === 'number' ? { googleReviewCount: place.userRatingCount } : {}),
      googleRatingCheckedAt: new Date().toISOString(),
    };
    const website = clean(row.website) ?? clean(place.websiteUri);
    const { data, error } = await context.admin
      .from('sales_leads')
      .update({ metadata: updatedMetadata, website })
      .eq('id', row.id)
      .eq('workspace_id', context.workspaceId)
      .eq('assigned_user_id', context.userId)
      .select('*')
      .single();
    if (error || !data) {
      console.warn('[sales-leads] Could not save Google rating', error);
      return row;
    }
    return data as SalesLead;
  } catch (error) {
    console.warn('[sales-leads] Could not refresh Google rating', error);
    return row;
  }
}
