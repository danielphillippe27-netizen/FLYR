import { z } from 'zod';

export const ResearchConfidenceSchema = z.enum(['high', 'medium', 'low']);

export const SourcedTextSchema = z.object({
  value: z.string().nullable(),
  confidence: ResearchConfidenceSchema,
  sources: z.array(z.string()),
}).strict();

export const SourcedListSchema = z.object({
  values: z.array(z.string()),
  confidence: ResearchConfidenceSchema,
  sources: z.array(z.string()),
}).strict();

export const DecisionMakerSchema = z.object({
  name: z.string(),
  role: z.string().nullable(),
  workEmail: z.string().nullable(),
  directPhone: z.string().nullable(),
  linkedinUrl: z.string().nullable(),
  otherProfiles: z.array(z.string()),
  confidence: ResearchConfidenceSchema,
  sources: z.array(z.string()),
}).strict();

export const ResearchSignalSchema = z.object({
  title: z.string(),
  detail: z.string(),
  observedAt: z.string().nullable(),
  confidence: ResearchConfidenceSchema,
  sources: z.array(z.string()),
}).strict();

export const CompanyResearchResultSchema = z.object({
  company: z.object({
    resolvedName: SourcedTextSchema,
    summary: SourcedTextSchema,
    website: SourcedTextSchema,
    phone: SourcedTextSchema,
    publicEmail: SourcedTextSchema,
    address: SourcedTextSchema,
    foundedYear: SourcedTextSchema,
    timeInBusiness: SourcedTextSchema,
    employeeEstimate: SourcedTextSchema,
    ownership: SourcedTextSchema,
    services: SourcedListSchema,
    serviceAreas: SourcedListSchema,
    locations: SourcedListSchema,
    hours: SourcedListSchema,
  }).strict(),
  decisionMakers: z.array(DecisionMakerSchema),
  reputation: z.object({
    ratingSummary: SourcedTextSchema,
    positiveThemes: SourcedListSchema,
    negativeThemes: SourcedListSchema,
  }).strict(),
  presence: z.object({
    socialProfiles: SourcedListSchema,
    recentActivity: SourcedListSchema,
    websiteTechnology: SourcedListSchema,
  }).strict(),
  signals: z.object({
    recentNews: z.array(ResearchSignalSchema),
    hiringAndGrowth: z.array(ResearchSignalSchema),
    competitors: SourcedListSchema,
  }).strict(),
  callBrief: z.object({
    opener: z.string(),
    summary: z.string(),
    conversationHooks: z.array(z.string()),
    inferredOpportunities: z.array(z.string()),
    caveats: z.array(z.string()),
  }).strict(),
  overallConfidence: ResearchConfidenceSchema,
  unresolvedFields: z.array(z.string()),
}).strict();

export type ResearchConfidence = z.infer<typeof ResearchConfidenceSchema>;
export type CompanyResearchResult = z.infer<typeof CompanyResearchResultSchema>;

export type CompanyResearchStatus = 'queued' | 'researching' | 'completed' | 'partial' | 'failed';

export type CompanyResearchSource = {
  url: string;
  title?: string | null;
};

export type CompanyResearchRecord = {
  id: string;
  workspace_id: string;
  company_id: string;
  batch_id?: string | null;
  status: CompanyResearchStatus;
  identity_snapshot: Record<string, unknown>;
  result?: CompanyResearchResult | null;
  sources: CompanyResearchSource[];
  overall_confidence?: ResearchConfidence | null;
  model: string;
  web_search_calls: number;
  attempt_count: number;
  completed_at?: string | null;
  expires_at?: string | null;
  error_code?: string | null;
  error_message?: string | null;
  created_at: string;
  updated_at: string;
};

export type CompanyResearchBatch = {
  id: string;
  workspace_id: string;
  smart_list_id?: string | null;
  smart_list_name?: string | null;
  requested_count: number;
  skipped_count: number;
  status: CompanyResearchStatus;
  completed_at?: string | null;
  created_at: string;
  updated_at: string;
};

