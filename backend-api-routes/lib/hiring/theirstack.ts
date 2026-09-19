import { createHmac, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { postingSchema, webURL, type HiringPosting } from './postings';

const optionalText = z.string().nullish();
const location = z.object({ country_code: optionalText, display_name: optionalText });
const person = z.object({ full_name: optionalText, first_name: optionalText, role: optionalText, linkedin_url: optionalText });
const jobSchema = z.object({
  id: z.number().int().positive(), job_title: z.string(), date_posted: z.string().date(),
  company: optionalText, company_domain: optionalText,
  company_object: z.object({ name: z.string(), domain: optionalText, industry: optionalText }).nullish(),
  url: optionalText, final_url: optionalText, source_url: optionalText,
  country_code: optionalText, country_codes: z.array(z.string().nullable()).nullish(),
  locations: z.array(location).nullish(), location: optionalText, long_location: optionalText,
  discovered_at: optionalText, closed_at: optionalText,
  min_annual_salary: z.number().nullish(), max_annual_salary: z.number().nullish(), salary_currency: optionalText,
  hiring_team: z.array(person).nullish(), has_blurred_data: z.boolean().optional(),
});

export const theirStackEventSchema = z.discriminatedUnion('type', [
  z.object({ id: z.number().int(), type: z.literal('job.new'), payload: jobSchema }),
  z.object({ id: z.number().int(), type: z.literal('job.closed'), payload: z.object({ id: z.number().int().positive(), closed_at: z.string() }) }),
]);

export function sourceDate(value: string | null | undefined): string | null {
  if (!value) return null;
  // Provider datetime values without an offset are documented as UTC.
  const input = /^\d{4}-\d{2}-\d{2}$/.test(value) ? `${value}T00:00:00Z`
    : /(?:Z|[+-]\d{2}:\d{2})$/i.test(value) ? value : `${value}Z`;
  const result = z.string().datetime({ offset: true }).safeParse(input);
  return result.success ? new Date(result.data).toISOString() : null;
}

function safeURL(value: string | null | undefined): string | null {
  const result = webURL.safeParse(value);
  return result.success ? result.data : null;
}

export function parseTheirStackJob(input: unknown): HiringPosting[] {
  const job = jobSchema.parse(input);
  if (job.has_blurred_data) throw new Error('Blurred provider data cannot become leads.');
  const locations = job.locations ?? [];
  const countries = new Set([
    ...locations.map(l => l.country_code), ...(job.country_codes ?? []), job.country_code,
  ].filter((c): c is 'CA' | 'US' => c === 'CA' || c === 'US'));
  const team = (job.hiring_team ?? []).slice(0, 50).map(p => ({
    name: p.full_name?.slice(0, 250) || p.first_name?.slice(0, 250) || null,
    role: p.role?.slice(0, 300) || null, profile_url: safeURL(p.linkedin_url),
  })).filter(p => p.name || p.profile_url);
  const domain = job.company_object?.domain ?? job.company_domain;
  const website = domain ? safeURL(domain.includes('://') ? domain : `https://${domain}`) : null;
  return [...countries].map(country => postingSchema.parse({
    provider: 'theirstack', external_id: String(job.id), country,
    company: job.company_object?.name || job.company,
    title: job.job_title,
    location: locations.filter(l => l.country_code === country).map(l => l.display_name).filter(Boolean).join('; ').slice(0, 400)
      || job.long_location || job.location || (country === 'CA' ? 'Canada' : 'United States'),
    category: job.company_object?.industry ?? null,
    url: safeURL(job.final_url) || safeURL(job.url) || safeURL(job.source_url),
    source_url: safeURL(job.source_url), source_discovered_at: sourceDate(job.discovered_at),
    posted_at: `${job.date_posted}T00:00:00Z`, closed_at: sourceDate(job.closed_at),
    salary_min: job.min_annual_salary ?? null, salary_max: job.max_annual_salary ?? null,
    currency: job.salary_currency ?? null, company_url: website,
    hiring_team: team, contact_name: null, contact_email: null, contact_phone: null,
  }));
}

export function validTheirStackSignature(raw: string | Buffer, header: string | null, secret: string | undefined): boolean {
  if (!secret || secret.length < 16 || !header || !/^sha256=[a-f0-9]{64}$/.test(header)) return false;
  const expected = createHmac('sha256', secret).update(raw).digest();
  return timingSafeEqual(expected, Buffer.from(header.slice(7), 'hex'));
}

export function theirStackConfigured(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.HIRING_THEIRSTACK_ENABLED === 'true' && (env.THEIRSTACK_WEBHOOK_SECRET?.length ?? 0) >= 16;
}
