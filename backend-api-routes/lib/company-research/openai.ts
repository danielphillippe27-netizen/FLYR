import OpenAI from 'openai';
import { zodTextFormat } from 'openai/helpers/zod';
import type { Responses } from 'openai/resources/responses/responses';
import { CompanyResearchResultSchema, type CompanyResearchResult, type CompanyResearchSource } from './types';
import type { ResearchCompany } from './identity';

const DEFAULT_MODEL = 'gpt-5.4-mini-2026-03-17';
const MAX_WEB_SEARCH_CALLS = 6;
const MAX_OUTPUT_TOKENS = 12_000;

function cleanString(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function finiteNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function isInstagramProfile(value: string): boolean {
  try {
    const url = new URL(value.includes('://') ? value : `https://${value}`);
    const hostname = url.hostname.toLowerCase().replace(/^www\./, '');
    return (hostname === 'instagram.com' || hostname.endsWith('.instagram.com')) && url.pathname !== '/';
  } catch {
    return false;
  }
}

function companyMetadata(company: ResearchCompany): Record<string, unknown> {
  return company.metadata && typeof company.metadata === 'object' ? company.metadata : {};
}

function googleMapsUrl(company: ResearchCompany): string | null {
  const metadata = companyMetadata(company);
  const savedUrl = cleanString(metadata.googleMapsUrl ?? metadata.google_maps_url);
  if (savedUrl) return savedUrl;
  return company.google_place_id
    ? `https://www.google.com/maps/search/?api=1&query_place_id=${encodeURIComponent(company.google_place_id)}`
    : null;
}

function trustedSeedSources(company: ResearchCompany): CompanyResearchSource[] {
  return [cleanString(company.website), googleMapsUrl(company)]
    .filter((url): url is string => Boolean(url))
    .map((url) => ({ url }));
}

function sourceKey(value: string): string {
  try {
    const url = new URL(value);
    url.hash = '';
    return url.toString().replace(/\/$/, '');
  } catch {
    return value.trim().replace(/\/$/, '');
  }
}

function webSources(output: Responses.ResponseOutputItem[]): CompanyResearchSource[] {
  const urls = new Set<string>();
  for (const item of output) {
    if (item.type !== 'web_search_call') continue;
    if (item.action.type === 'search') {
      for (const source of item.action.sources ?? []) if (source.url) urls.add(source.url);
    } else if ('url' in item.action && item.action.url) {
      urls.add(item.action.url);
    }
  }
  return [...urls].map((url) => ({ url }));
}

export function sanitizeResearchResult(result: CompanyResearchResult, actualSources: CompanyResearchSource[]): CompanyResearchResult {
  const allowed = new Map(actualSources.map((source) => [sourceKey(source.url), source.url]));
  const verifiedSources = (sources: string[]) => [...new Set(sources.map((source) => allowed.get(sourceKey(source))).filter((source): source is string => Boolean(source)))];
  const cleanText = <T extends { value?: string | null; sources: string[] }>(fact: T): T => ({
    ...fact,
    value: fact.value && verifiedSources(fact.sources).length > 0 ? fact.value : null,
    sources: verifiedSources(fact.sources),
  } as T);
  const cleanList = <T extends { values: string[]; sources: string[] }>(fact: T): T => ({
    ...fact,
    values: verifiedSources(fact.sources).length > 0 ? fact.values : [],
    sources: verifiedSources(fact.sources),
  });
  const company = Object.fromEntries(Object.entries(result.company).map(([key, value]) => [
    key,
    'values' in value ? cleanList(value) : cleanText(value),
  ])) as CompanyResearchResult['company'];
  return {
    ...result,
    company,
    decisionMakers: result.decisionMakers.map((person) => {
      const sources = verifiedSources(person.sources);
      return {
        ...person,
        workEmail: sources.length ? person.workEmail : null,
        directPhone: sources.length ? person.directPhone : null,
        linkedinUrl: sources.length ? person.linkedinUrl : null,
        otherProfiles: sources.length ? person.otherProfiles : [],
        sources,
      };
    }).filter((person) => person.sources.length > 0),
    reputation: {
      ratingSummary: cleanText(result.reputation.ratingSummary),
      positiveThemes: cleanList(result.reputation.positiveThemes),
      negativeThemes: cleanList(result.reputation.negativeThemes),
    },
    presence: {
      socialProfiles: {
        ...cleanList(result.presence.socialProfiles),
        values: cleanList(result.presence.socialProfiles).values.filter(isInstagramProfile),
      },
      recentActivity: cleanList(result.presence.recentActivity),
      websiteTechnology: cleanList(result.presence.websiteTechnology),
    },
    signals: {
      recentNews: result.signals.recentNews.map((signal) => ({ ...signal, sources: verifiedSources(signal.sources) })).filter((signal) => signal.sources.length > 0),
      hiringAndGrowth: result.signals.hiringAndGrowth.map((signal) => ({ ...signal, sources: verifiedSources(signal.sources) })).filter((signal) => signal.sources.length > 0),
      competitors: cleanList(result.signals.competitors),
    },
  };
}

export function applyTrustedResearchSeed(result: CompanyResearchResult, company: ResearchCompany): CompanyResearchResult {
  const metadata = companyMetadata(company);
  const website = cleanString(company.website);
  const mapsUrl = googleMapsUrl(company);
  const rating = finiteNumber(metadata.googleRating ?? metadata.google_rating);
  const reviewCount = finiteNumber(metadata.googleReviewCount ?? metadata.google_review_count ?? metadata.userRatingCount);
  const googleReviewSummary = rating !== null && reviewCount !== null
    ? `${rating.toFixed(1)} stars from ${Math.max(0, Math.round(reviewCount)).toLocaleString('en-US')} Google reviews`
    : rating !== null
      ? `${rating.toFixed(1)} stars on Google`
      : reviewCount !== null
        ? `${Math.max(0, Math.round(reviewCount)).toLocaleString('en-US')} Google reviews`
        : null;

  return {
    ...result,
    company: {
      ...result.company,
      website: website ? { value: website, confidence: 'high', sources: [website] } : result.company.website,
    },
    reputation: {
      ...result.reputation,
      ratingSummary: googleReviewSummary
        ? { value: googleReviewSummary, confidence: 'high', sources: mapsUrl ? [mapsUrl] : [] }
        : result.reputation.ratingSummary,
    },
    presence: {
      ...result.presence,
      socialProfiles: {
        ...result.presence.socialProfiles,
        values: result.presence.socialProfiles.values.filter(isInstagramProfile),
      },
    },
  };
}

export function researchResponseFailure(response: {
  status?: Responses.Response['status'];
  error: Responses.Response['error'];
  incomplete_details: Responses.Response['incomplete_details'];
  output: Responses.ResponseOutputItem[];
}): Error & { code: string } {
  const refusal = response.output
    .filter((item): item is Responses.ResponseOutputMessage => item.type === 'message')
    .flatMap((item) => item.content)
    .find((content): content is Responses.ResponseOutputRefusal => content.type === 'refusal');
  const incompleteReason = response.incomplete_details?.reason;
  const code = response.error?.code
    ?? (refusal ? 'openai_refusal' : incompleteReason ? `openai_${incompleteReason}` : 'openai_unparsed_response');
  const message = response.error?.message
    ?? (refusal
      ? `OpenAI refused company research: ${refusal.refusal}`
      : incompleteReason
        ? `OpenAI company research was incomplete: ${incompleteReason}.`
        : `OpenAI returned no structured company research (status: ${response.status}).`);
  return Object.assign(new Error(message), { code });
}

export async function researchCompanyWithOpenAI(company: ResearchCompany): Promise<{
  result: CompanyResearchResult;
  sources: CompanyResearchSource[];
  responseId: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  webSearchCalls: number;
}> {
  const apiKey = process.env.OPENAI_API_KEY?.trim();
  if (!apiKey) throw Object.assign(new Error('Company research is not configured. Add OPENAI_API_KEY to the backend environment.'), { code: 'openai_not_configured' });
  const model = process.env.OPENAI_COMPANY_RESEARCH_MODEL?.trim() || DEFAULT_MODEL;
  const client = new OpenAI({ apiKey });
  const identity = {
    name: company.name,
    website: company.website,
    websiteDomain: company.website_domain,
    phone: company.phone,
    publicEmail: company.email,
    address: company.address,
    city: company.city,
    region: company.region,
    countryCode: company.country_code,
    googlePlaceId: company.google_place_id,
    googleMapsUrl: googleMapsUrl(company),
    googleRating: finiteNumber(companyMetadata(company).googleRating ?? companyMetadata(company).google_rating),
    googleReviewCount: finiteNumber(companyMetadata(company).googleReviewCount ?? companyMetadata(company).google_review_count ?? companyMetadata(company).userRatingCount),
  };
  const response = await client.responses.parse({
    model,
    store: false,
    reasoning: { effort: 'low' },
    max_output_tokens: MAX_OUTPUT_TOKENS,
    max_tool_calls: MAX_WEB_SEARCH_CALLS,
    include: ['web_search_call.action.sources'],
    tools: [{
      type: 'web_search',
      search_context_size: 'medium',
      external_web_access: true,
      ...(company.country_code ? {
        user_location: {
          type: 'approximate' as const,
          country: company.country_code,
          city: company.city,
          region: company.region,
        },
      } : {}),
    }],
    text: {
      verbosity: 'low',
      format: zodTextFormat(CompanyResearchResultSchema, 'wolfgrid_company_research'),
    },
    instructions: [
      'You are WolfGrid company research. Resolve the exact company before reporting anything.',
      'Research only four items: the official website, the exact official Instagram profile when one exists, how long the company has been in business, and its Google rating plus Google review count.',
      'Use the Google Places values in the identity seed as authoritative for website, rating, and review count when supplied. Use live web search to verify or fill missing items.',
      'Every web-researched value must cite the exact public source URL used. Never guess a website, Instagram URL, founding date, or business age.',
      'Return only Instagram in presence.socialProfiles. Use null or an empty list when an item cannot be verified.',
      'Leave unrelated company fields null or empty, decisionMakers and signals empty, reputation themes empty, and callBrief strings/lists empty.',
      'Do not use paywalled, authenticated, leaked, or breached sources. The output is research-card data, not an instruction to modify CRM contacts.',
    ].join(' '),
    input: `Find the official website, official Instagram, time in business, and Google review summary for this company. Identity seed:\n${JSON.stringify(identity, null, 2)}`,
  });
  if (!response.output_parsed) throw researchResponseFailure(response);
  const sources = [...new Map(
    [...webSources(response.output), ...trustedSeedSources(company)].map((source) => [sourceKey(source.url), source])
  ).values()];
  const result = applyTrustedResearchSeed(sanitizeResearchResult(response.output_parsed, sources), company);
  return {
    result,
    sources,
    responseId: response.id,
    model,
    inputTokens: response.usage?.input_tokens ?? 0,
    outputTokens: response.usage?.output_tokens ?? 0,
    totalTokens: response.usage?.total_tokens ?? 0,
    webSearchCalls: response.output.filter((item) => item.type === 'web_search_call').length,
  };
}
