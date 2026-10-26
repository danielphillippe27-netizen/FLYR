import assert from 'node:assert/strict';
import { validateResearchResult, resultSchema, parseResearchResponse, researchOutputSchema } from '../business-research';
const source = 'https://example.com/contact';
const base = { name: 'Business', area: 'Richmond Hill', notes: 'Owner unknown', website: null, email: null, phone: null, owner: null, address: null };
const found = { ...base, phone: { value: '905-555-0100', sourceUrl: source } };
assert.equal(validateResearchResult(found, new Set([source])).phone?.value, '905-555-0100');
assert.equal(validateResearchResult(found, new Set()).phone, null);
assert.equal(validateResearchResult({ ...base, email: { value: 'guessed email', sourceUrl: source } }, new Set([source])).email, null);
assert.equal(validateResearchResult({ ...base, website: { value: 'javascript:alert(1)', sourceUrl: source } }, new Set([source])).website, null);
assert.equal(resultSchema.safeParse({ ...base, owner: { value: 'Name', sourceUrl: 'javascript:alert(1)' } }).success, false);
assert.equal(validateResearchResult(base, new Set()).owner, null);
assert.throws(() => validateResearchResult({ name: 'Malformed' }, new Set()));
assert.equal(researchOutputSchema.additionalProperties, false);
const response = { status: 'completed', output: [
  { type: 'web_search_call', action: { type: 'search', sources: [{ url: source }] } },
  { type: 'message', content: [{ type: 'output_text', text: JSON.stringify(found) }] },
] };
assert.equal(parseResearchResponse(response).phone?.value, '905-555-0100');
assert.equal(parseResearchResponse({ status: 'completed', output: [{ type: 'message', action: null, content: [{ type: 'output_text', text: JSON.stringify(found), annotations: [{ type: 'url_citation', url: source }] }] }] }).phone?.value, '905-555-0100');
assert.equal(parseResearchResponse({ status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify(found) }] }] }).phone, null);
assert.throws(() => parseResearchResponse({ ...response, status: 'incomplete' }), /research_incomplete/);
assert.throws(() => parseResearchResponse({ status: 'completed', output: [{ type: 'message', content: [{ type: 'refusal' }] }] }), /research_refused/);
console.log('Business research source and validation checks passed.');
