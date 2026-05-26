import type { LambdaSnapshotResponse } from '@/lib/services/TileLambdaService';
import type { StandardCampaignAddress } from '@/lib/services/AddressAdapter';
import { BedrockNzService, type BedrockNzLinkGeometry } from '@/lib/services/BedrockNzService';
import { BedrockAustraliaService } from '@/lib/services/BedrockAustraliaService';
import { BedrockCanadaService } from '@/lib/services/BedrockCanadaService';
import { BedrockSouthAfricaService } from '@/lib/services/BedrockSouthAfricaService';
import { BedrockUsService } from '@/lib/services/BedrockUsService';
import { BedrockUkService } from '@/lib/services/BedrockUkService';

export type BedrockProviderSource =
  | 'bedrock_nz'
  | 'bedrock_au'
  | 'bedrock_ca'
  | 'bedrock_us'
  | 'bedrock_za'
  | 'bedrock_uk';

export type BedrockLinkGeometry = BedrockNzLinkGeometry;

type BedrockProvider = {
  source: BedrockProviderSource;
  label: string;
  supportsRegion: (regionCode: string | null | undefined) => boolean;
  provisionCampaign: (options: {
    campaignId: string;
    polygon: GeoJSON.Polygon;
    addressLimit?: number;
    regionCode?: string | null;
  }) => Promise<{
    addresses: StandardCampaignAddress[];
    snapshot: LambdaSnapshotResponse;
    metrics: Record<string, unknown>;
    linkGeometry?: BedrockLinkGeometry | null;
  }>;
};

const BEDROCK_PROVIDERS: BedrockProvider[] = [
  {
    source: 'bedrock_nz',
    label: 'New Zealand',
    supportsRegion: BedrockNzService.isNzRegion,
    provisionCampaign: BedrockNzService.provisionCampaign,
  },
  {
    source: 'bedrock_au',
    label: 'Australia',
    supportsRegion: BedrockAustraliaService.isAustraliaRegion,
    provisionCampaign: BedrockAustraliaService.provisionCampaign,
  },
  {
    source: 'bedrock_ca',
    label: 'Canada',
    supportsRegion: BedrockCanadaService.isCanadaRegion,
    provisionCampaign: BedrockCanadaService.provisionCampaign,
  },
  {
    source: 'bedrock_za',
    label: 'South Africa',
    supportsRegion: BedrockSouthAfricaService.isSouthAfricaRegion,
    provisionCampaign: BedrockSouthAfricaService.provisionCampaign,
  },
  {
    source: 'bedrock_uk',
    label: 'UK',
    supportsRegion: BedrockUkService.isUkRegion,
    provisionCampaign: BedrockUkService.provisionCampaign,
  },
  {
    source: 'bedrock_us',
    label: 'USA',
    supportsRegion: BedrockUsService.isUsRegion,
    provisionCampaign: BedrockUsService.provisionCampaign,
  },
];

export class BedrockProvisionService {
  static providerForRegion(regionCode: string | null | undefined): BedrockProvider | null {
    return BEDROCK_PROVIDERS.find((provider) => provider.supportsRegion(regionCode)) ?? null;
  }

  static isSupportedRegion(regionCode: string | null | undefined): boolean {
    return Boolean(this.providerForRegion(regionCode));
  }

  static async provisionCampaign(options: {
    campaignId: string;
    polygon: GeoJSON.Polygon;
    addressLimit?: number;
    regionCode: string;
  }): Promise<{
    providerSource: BedrockProviderSource;
    providerLabel: string;
    addresses: StandardCampaignAddress[];
    snapshot: LambdaSnapshotResponse;
    metrics: Record<string, unknown>;
    linkGeometry: BedrockLinkGeometry | null;
  }> {
    const provider = this.providerForRegion(options.regionCode);
    if (!provider) {
      throw new Error(`No Bedrock provider supports region "${options.regionCode}"`);
    }

    const result = await provider.provisionCampaign({
      campaignId: options.campaignId,
      polygon: options.polygon,
      addressLimit: options.addressLimit,
      regionCode: options.regionCode,
    });

    return {
      providerSource: provider.source,
      providerLabel: provider.label,
      addresses: result.addresses,
      snapshot: result.snapshot,
      metrics: result.metrics,
      linkGeometry: result.linkGeometry ?? null,
    };
  }
}
