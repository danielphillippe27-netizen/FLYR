import {
  BedrockCountryService,
  BEDROCK_US_CONFIG,
  isBedrockUsFullPmtilesRegion,
} from '@/lib/services/BedrockCountryService';

const service = new BedrockCountryService(BEDROCK_US_CONFIG);

export class BedrockUsService {
  static isUsRegion(regionCode: string | null | undefined) {
    return isBedrockUsFullPmtilesRegion(regionCode);
  }

  static provisionCampaign = service.provisionCampaign.bind(service);
}
