import { BedrockCountryService, BEDROCK_AUSTRALIA_CONFIG } from '@/lib/services/BedrockCountryService';

const service = new BedrockCountryService(BEDROCK_AUSTRALIA_CONFIG);

export class BedrockAustraliaService {
  static isAustraliaRegion(regionCode: string | null | undefined) {
    return regionCode?.trim().toUpperCase() === 'AU';
  }

  static provisionCampaign = service.provisionCampaign.bind(service);
}
