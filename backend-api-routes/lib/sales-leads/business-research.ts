import { z } from 'zod';

export const httpUrl = z.string().url().max(2000).refine(value => /^https?:\/\//i.test(value));
export const fields = ['website', 'email', 'phone', 'owner', 'address'] as const;
const fact = z.object({ value: z.string().max(500), sourceUrl: httpUrl }).strict();
export const resultSchema = z.object({
  name: z.string().trim().min(1).max(180), area: z.string().trim().min(1).max(100),
  website: fact.nullable(), email: fact.nullable(), phone: fact.nullable(), owner: fact.nullable(), address: fact.nullable(),
  notes: z.string().max(2000),
}).strict();

// Keep generation constrained to the same shape that we validate before saving.
const outputFact = z.object({ value: z.string().max(500), sourceUrl: z.string().max(2000) }).strict().nullable();
export const researchOutputSchema = z.toJSONSchema(z.object({
  name: resultSchema.shape.name, area: resultSchema.shape.area, notes: resultSchema.shape.notes,
  website: outputFact, email: outputFact, phone: outputFact, owner: outputFact, address: outputFact,
}).strict());

export function parseResearchResponse(payload: unknown) {
  const response = z.object({
    status: z.string(),
    output: z.array(z.object({
      type: z.string(),
      action: z.object({ sources: z.array(z.object({ url: z.string() })).nullish() }).nullish(),
      content: z.array(z.object({
        type: z.string(), text: z.string().optional(),
        annotations: z.array(z.object({ type: z.string(), url: z.string().optional() })).optional(),
      })).nullish(),
    })),
  }).parse(payload);
  if (response.status !== 'completed') throw new Error('research_incomplete');
  const content = response.output.flatMap(item => item.content ?? []);
  if (content.some(item => item.type === 'refusal')) throw new Error('research_refused');
  const sources = new Set([
    ...response.output.flatMap(item => item.action?.sources?.map(source => source.url) ?? []),
    ...content.flatMap(item => item.annotations?.filter(a => a.type === 'url_citation' && a.url).map(a => a.url!) ?? []),
  ]);
  const text = content.filter(item => item.type === 'output_text').map(item => item.text ?? '').join('').trim();
  return validateResearchResult(JSON.parse(text.replace(/^```(?:json)?\s*|\s*```$/g, '')), sources);
}

export function validateResearchResult(value: unknown, sources: Set<string>) {
  const result = resultSchema.parse(value);
  for (const field of fields) if (result[field] && !sources.has(result[field]!.sourceUrl)) result[field] = null;
  if (result.website && !httpUrl.safeParse(result.website.value).success) result.website = null;
  if (result.email && !z.string().email().safeParse(result.email.value).success) result.email = null;
  return result;
}
