import { BedrockCountryService, BEDROCK_NZ_CONFIG } from '@/lib/services/BedrockCountryService';

const service = new BedrockCountryService(BEDROCK_NZ_CONFIG);

export type BedrockNzLinkGeometry = NonNullable<
  Awaited<ReturnType<typeof service.provisionCampaign>>['linkGeometry']
>;

export class BedrockNzService {
  static isNzRegion(regionCode: string | null | undefined) {
    return regionCode?.trim().toUpperCase() === 'NZ';
  }

  static provisionCampaign = service.provisionCampaign.bind(service);
}
