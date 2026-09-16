import { createHash } from 'node:crypto';
import { z } from 'zod';

export const countrySchema = z.enum(['CA', 'US']);
export const reviewSchema = z.enum(['new', 'saved', 'contacted', 'dismissed']);
export const feedQuerySchema = z.object({
  country: z.enum(['all', 'CA', 'US']).default('all'),
  status: z.enum(['all', 'new', 'saved', 'contacted', 'dismissed']).default('all'),
  q: z.string().trim().max(120).default(''),
  days: z.coerce.number().int().refine(n => [1, 7, 30, 90].includes(n)).default(7),
  offset: z.coerce.number().int().min(0).max(100000).default(0),
});

export const webURL = z.string().url().refine(value => {
  const url = new URL(value);
  return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password;
});
export const postingSchema = z.object({
  provider: z.string().min(1).max(80),
  external_id: z.string().min(1).max(250),
  country: countrySchema,
  company: z.string().trim().min(1).max(300),
  title: z.string().trim().min(1).max(400),
  location: z.string().trim().min(1).max(400),
  category: z.string().max(200).nullable(),
  url: webURL,
  posted_at: z.string().datetime({ offset: true }),
  salary_min: z.number().nonnegative().finite().nullable(),
  salary_max: z.number().nonnegative().finite().nullable(),
  // Provider values only; do not infer a currency from a remote role's location.
  currency: z.string().max(10).nullable(),
  company_url: webURL.nullable(),
  contact_name: z.string().max(250).nullable(),
  contact_email: z.string().email().nullable(),
  contact_phone: z.string().max(80).nullable(),
  source_url: webURL.nullable().optional(),
  source_discovered_at: z.string().datetime({ offset: true }).nullable().optional(),
  closed_at: z.string().datetime({ offset: true }).nullable().optional(),
  hiring_team: z.array(z.object({
    name: z.string().max(250).nullable(), role: z.string().max(300).nullable(),
    profile_url: webURL.nullable(),
  })).max(50).optional(),
});
export type HiringPosting = z.infer<typeof postingSchema>;

function normalize(value: string) {
  return value.normalize('NFKC').toLowerCase().replace(/\s+/g, ' ').trim();
}

export function postingFingerprint(posting: HiringPosting): string {
  // Exact normalized company/title/location groups represent a hiring signal,
  // not a claimed headcount. Preserve every original source record separately.
  return createHash('sha256').update(JSON.stringify([
    posting.country, normalize(posting.company), normalize(posting.title), normalize(posting.location),
  ])).digest('hex');
}

const adzunaRow = z.object({
  id: z.union([z.string(), z.number()]), title: z.string(), created: z.string(),
  redirect_url: z.string(), company: z.object({ display_name: z.string() }),
  location: z.object({ display_name: z.string() }),
  category: z.object({ label: z.string() }).optional(),
  salary_min: z.number().optional(), salary_max: z.number().optional(),
});

export function parseAdzunaPage(payload: unknown, country: 'CA' | 'US') {
  const envelope = z.object({ count: z.number().nonnegative(), results: z.array(z.unknown()) }).parse(payload);
  const postings: HiringPosting[] = [];
  let rejected = 0;
  for (const value of envelope.results) {
    const result = adzunaRow.safeParse(value);
    if (!result.success) { rejected++; continue; }
    const row = result.data;
    const parsed = postingSchema.safeParse({
      provider: 'adzuna', external_id: String(row.id), country,
      company: row.company.display_name, title: row.title, location: row.location.display_name,
      category: row.category?.label ?? null, url: row.redirect_url, posted_at: row.created,
      salary_min: row.salary_min ?? null, salary_max: row.salary_max ?? null,
      currency: null, company_url: null, contact_name: null, contact_email: null, contact_phone: null,
    });
    if (parsed.success) postings.push(parsed.data); else rejected++;
  }
  return { postings, rejected, count: envelope.count, received: envelope.results.length };
}

export function hiringSourceConfigured(env: NodeJS.ProcessEnv = process.env) {
  return env.HIRING_ADZUNA_ENABLED === 'true' && Boolean(env.ADZUNA_APP_ID && env.ADZUNA_APP_KEY);
}

export function adzunaSearchURL(country: 'CA' | 'US', page: number, env: NodeJS.ProcessEnv = process.env) {
  if (!hiringSourceConfigured(env)) throw new Error('Hiring source is not configured.');
  const url = new URL(`https://api.adzuna.com/v1/api/jobs/${country.toLowerCase()}/search/${page}`);
  url.searchParams.set('app_id', env.ADZUNA_APP_ID!);
  url.searchParams.set('app_key', env.ADZUNA_APP_KEY!);
  url.searchParams.set('results_per_page', '50');
  url.searchParams.set('sort_by', 'date');
  // Overlap daily runs to catch late delivery without making old leads new again.
  url.searchParams.set('max_days_old', '3');
  return url;
}
