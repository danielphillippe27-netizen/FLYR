import assert from 'node:assert/strict';
import test from 'node:test';
import { companyIdentityKey, normalizeCompanyDomain } from '../identity';
import { applyTrustedResearchSeed, researchResponseFailure, sanitizeResearchResult } from '../openai';
import { CompanyResearchResultSchema, type CompanyResearchResult } from '../types';

const sourcedText = (value: string | null, sources: string[] = []) => ({ value, confidence: 'high' as const, sources });
const sourcedList = (values: string[] = [], sources: string[] = []) => ({ values, confidence: 'high' as const, sources });

function fixture(): CompanyResearchResult {
  const valid = 'https://example.com/about';
  return CompanyResearchResultSchema.parse({
    company: {
      resolvedName: sourcedText('Example Co', [valid]), summary: sourcedText('Summary', [valid]),
      website: sourcedText('https://example.com', [valid]), phone: sourcedText('+1 555 0100', [valid]),
      publicEmail: sourcedText('guessed@example.com', ['https://invented.invalid']), address: sourcedText('Toronto', [valid]),
      foundedYear: sourcedText('2015', [valid]), timeInBusiness: sourcedText('11 years', [valid]),
      employeeEstimate: sourcedText('10-20', [valid]), ownership: sourcedText('Privately owned', [valid]),
      services: sourcedList(['Consulting'], [valid]), serviceAreas: sourcedList(['Ontario'], [valid]),
      locations: sourcedList(['Toronto'], [valid]), hours: sourcedList([], []),
    },
    decisionMakers: [
      { name: 'Verified Owner', role: 'Owner', workEmail: 'owner@example.com', directPhone: null, linkedinUrl: null, otherProfiles: [], confidence: 'high', sources: [valid] },
      { name: 'Guessed Owner', role: 'Owner', workEmail: 'guess@example.com', directPhone: '555', linkedinUrl: null, otherProfiles: [], confidence: 'low', sources: ['https://invented.invalid'] },
    ],
    reputation: { ratingSummary: sourcedText(null), positiveThemes: sourcedList(), negativeThemes: sourcedList() },
    presence: {
      socialProfiles: sourcedList(['https://instagram.com/example', 'https://facebook.com/example'], [valid]),
      recentActivity: sourcedList(),
      websiteTechnology: sourcedList(),
    },
    signals: { recentNews: [], hiringAndGrowth: [], competitors: sourcedList() },
    callBrief: { opener: 'Hello', summary: 'Brief', conversationHooks: [], inferredOpportunities: [], caveats: [] },
    overallConfidence: 'high', unresolvedFields: [],
  });
}

test('company identity normalizes domains and location names', () => {
  assert.equal(normalizeCompanyDomain('https://www.Example.com/path'), 'example.com');
  assert.equal(
    companyIdentityKey({ name: 'Prima Aesthetic Studios', city: 'Whitby', region: 'Ontario' }),
    'prima aesthetic studios|whitby|ontario'
  );
});

test('research sanitizer keeps only sources observed by the web-search tool', () => {
  const sanitized = sanitizeResearchResult(fixture(), [{ url: 'https://example.com/about' }]);
  assert.equal(sanitized.company.publicEmail.value, null);
  assert.equal(sanitized.decisionMakers.length, 1);
  assert.equal(sanitized.decisionMakers[0]?.name, 'Verified Owner');
  assert.equal(sanitized.decisionMakers[0]?.workEmail, 'owner@example.com');
  assert.deepEqual(sanitized.presence.socialProfiles.values, ['https://instagram.com/example']);
});

test('trusted Google Places data supplies website and Google review summary', () => {
  const enriched = applyTrustedResearchSeed(fixture(), {
    id: 'company-1',
    workspace_id: 'workspace-1',
    name: 'Example Co',
    website: 'https://example.com',
    google_place_id: 'place-1',
    metadata: {
      googleMapsUrl: 'https://maps.google.com/?cid=123',
      googleRating: 4.8,
      googleReviewCount: 127,
    },
  });
  assert.equal(enriched.company.website.value, 'https://example.com');
  assert.equal(enriched.reputation.ratingSummary.value, '4.8 stars from 127 Google reviews');
  assert.deepEqual(enriched.reputation.ratingSummary.sources, ['https://maps.google.com/?cid=123']);
});

test('research response failure preserves the OpenAI incomplete reason', () => {
  const error = researchResponseFailure({
    status: 'incomplete',
    error: null,
    incomplete_details: { reason: 'max_output_tokens' },
    output: [],
  });
  assert.equal(error.code, 'openai_max_output_tokens');
  assert.match(error.message, /max_output_tokens/);
});
