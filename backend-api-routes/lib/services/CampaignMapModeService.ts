import type { SupabaseClient } from '@supabase/supabase-js';
import { fetchAllInPages } from '@/lib/supabase/fetchAllInPages';

export type CampaignMapMode = 'hybrid';

export interface CampaignMapModeAssessment {
  hasParcels: boolean;
  parcelCount: number;
  totalAddresses: number;
  linkedAddressCount: number;
  buildingLinkConfidence: number;
  mapMode: CampaignMapMode;
}

export interface CampaignMapModeComputationOptions {
  hasParcels?: boolean;
  parcelCount?: number;
  totalAddresses?: number;
  linkedAddressCount?: number;
}

export const ACCEPTABLE_LINK_CONFIDENCE_SCORE = 0.6;

function roundPercentage(value: number): number {
  return Math.round(value * 100) / 100;
}

export function resolveCampaignMapMode(input: {
  hasParcels: boolean;
  buildingLinkConfidence: number;
}): CampaignMapMode {
  void input;
  return 'hybrid';
}

export class CampaignMapModeService {
  constructor(private readonly supabase: SupabaseClient) {}

  async computeAssessment(
    campaignId: string,
    options: CampaignMapModeComputationOptions = {}
  ): Promise<CampaignMapModeAssessment> {
    const totalAddresses = options.totalAddresses ?? await this.fetchTotalAddresses(campaignId);
    const linkedAddressCount = options.linkedAddressCount ?? await this.fetchLinkedAddressCount(campaignId);
    const parcelCount = options.parcelCount ?? await this.fetchParcelCount(campaignId);
    const hasParcels = options.hasParcels ?? parcelCount > 0;
    const buildingLinkConfidence =
      totalAddresses > 0 ? roundPercentage((linkedAddressCount / totalAddresses) * 100) : 0;

    return {
      hasParcels,
      parcelCount,
      totalAddresses,
      linkedAddressCount,
      buildingLinkConfidence,
      mapMode: resolveCampaignMapMode({
        hasParcels,
        buildingLinkConfidence,
      }),
    };
  }

  async computeAndPersist(
    campaignId: string,
    options: CampaignMapModeComputationOptions = {}
  ): Promise<CampaignMapModeAssessment> {
    const assessment = await this.computeAssessment(campaignId, options);

    const { error } = await this.supabase
      .from('campaigns')
      .update({
        has_parcels: assessment.hasParcels,
        building_link_confidence: assessment.buildingLinkConfidence,
        map_mode: assessment.mapMode,
      })
      .eq('id', campaignId);

    if (error) {
      throw new Error(`Failed to persist campaign map mode: ${error.message}`);
    }

    return assessment;
  }

  private async fetchTotalAddresses(campaignId: string): Promise<number> {
    const { count, error } = await this.supabase
      .from('campaign_addresses')
      .select('id', { count: 'exact', head: true })
      .eq('campaign_id', campaignId);

    if (error) {
      throw new Error(`Failed to count campaign addresses: ${error.message}`);
    }

    return count ?? 0;
  }

  private async fetchLinkedAddressCount(campaignId: string): Promise<number> {
    const linkedAddressIds = new Set<string>();

    const directLinks = await fetchAllInPages<{
      id: string;
      building_id: string | null;
      building_gers_id: string | null;
      confidence: number | null;
    }>((from, to) =>
      this.supabase
        .from('campaign_addresses')
        .select('id, building_id, building_gers_id, confidence')
        .eq('campaign_id', campaignId)
        .range(from, to)
    );

    for (const row of directLinks) {
      const hasBuilding = typeof row.building_id === 'string' || typeof row.building_gers_id === 'string';
      const confidence = typeof row.confidence === 'number' ? row.confidence : 1;
      if (hasBuilding && confidence >= ACCEPTABLE_LINK_CONFIDENCE_SCORE) {
        linkedAddressIds.add(row.id);
      }
    }

    const confidenceColumns = ['confidence', 'confidence_score'];
    let lastError: { message?: string } | null = null;

    for (const column of confidenceColumns) {
      try {
        const rows = await fetchAllInPages<{ address_id: string }>((from, to) =>
          this.supabase
            .from('building_address_links')
            .select('address_id')
            .eq('campaign_id', campaignId)
            .gte(column, ACCEPTABLE_LINK_CONFIDENCE_SCORE)
            .range(from, to)
        );
        for (const row of rows) {
          if (typeof row.address_id === 'string') {
            linkedAddressIds.add(row.address_id);
          }
        }
        return linkedAddressIds.size;
      } catch (error) {
        lastError = error as { message?: string };
      }
    }

    throw new Error(`Failed to count linked addresses using confidence or confidence_score: ${lastError?.message ?? 'unknown error'}`);
  }

  private async fetchParcelCount(campaignId: string): Promise<number> {
    const { count, error } = await this.supabase
      .from('campaign_parcels')
      .select('id', { count: 'exact', head: true })
      .eq('campaign_id', campaignId);

    if (error) {
      throw new Error(`Failed to count campaign parcels: ${error.message}`);
    }

    return count ?? 0;
  }
}
