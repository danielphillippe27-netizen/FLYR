import type { SocialPlatform } from './platforms';

export type SocialAssetInput = {
  mime_type?: string | null;
  byte_size?: number | null;
  duration_seconds?: number | null;
};

export type SocialTargetInput = {
  platform: SocialPlatform;
  format?: string | null;
  caption?: string | null;
  title?: string | null;
  settings?: Record<string, unknown> | null;
};

function isImage(asset: SocialAssetInput) {
  return asset.mime_type?.startsWith('image/') === true;
}

function isVideo(asset: SocialAssetInput) {
  return asset.mime_type?.startsWith('video/') === true;
}

export function validateSocialTarget(
  target: SocialTargetInput,
  assets: SocialAssetInput[],
  mode: 'draft' | 'schedule' | 'publish',
): string | null {
  const images = assets.filter(isImage);
  const videos = assets.filter(isVideo);
  const hasUnsupportedAsset = assets.some((asset) => !isImage(asset) && !isVideo(asset));

  if (hasUnsupportedAsset) return 'Only image and video media can be published';

  if (target.platform === 'facebook') {
    if (target.format === 'story') return 'Facebook Stories are not supported by the WolfSocial Page publishing connection';
    if (images.length && videos.length) return 'Facebook posts cannot mix images and videos in one WolfSocial post';
    if (videos.length > 1) return 'Facebook currently supports one video per WolfSocial post';
    if (images.length > 10) return 'Facebook supports at most ten images in one WolfSocial post';
    return null;
  }

  if (target.platform === 'instagram') {
    if (!assets.length) return 'Instagram requires an image or video';
    if (target.format === 'carousel') {
      if (assets.length < 2) return 'Instagram carousels require at least two media items';
      if (assets.length > 10) return 'Instagram carousels support at most ten media items';
    } else if (assets.length !== 1) {
      return 'Instagram feed, Reel, and Story posts require exactly one media item';
    }
    if ((target.caption?.length || 0) > 2200) return 'Instagram captions must be 2,200 characters or less';
    return null;
  }

  if (target.platform === 'youtube') {
    if (assets.length !== 1 || videos.length !== 1) return 'YouTube Shorts requires exactly one video';
    if (!target.title?.trim()) return 'YouTube requires a title';
    if (target.title.length > 100) return 'YouTube titles must be 100 characters or less';
    if ((target.caption?.length || 0) > 5000) return 'YouTube descriptions must be 5,000 characters or less';
    if (mode !== 'draft' && typeof target.settings?.madeForKids !== 'boolean') {
      return 'Choose whether the YouTube video is made for kids';
    }
    return null;
  }

  if (target.platform === 'linkedin') {
    if (images.length && videos.length) return 'LinkedIn posts cannot mix images and video';
    if (videos.length > 1) return 'LinkedIn supports one video per post';
    if (images.length > 20) return 'LinkedIn supports at most twenty images in one WolfSocial post';
    if ((target.caption?.length || 0) > 3000) return 'LinkedIn posts must be 3,000 characters or less';
    return null;
  }

  if (!assets.length) return 'TikTok requires a video or one or more photos';
  if (images.length && videos.length) return 'TikTok posts cannot mix photos and video';
  if (videos.length > 1) return 'TikTok supports one video per post';
  if ((target.caption?.length || 0) > 2200) return 'TikTok captions must be 2,200 characters or less';

  if (mode !== 'draft') {
    const settings = target.settings || {};
    if (typeof settings.privacyLevel !== 'string' || !settings.privacyLevel) return 'Choose TikTok privacy before publishing';
    if (settings.musicUsageConfirmed !== true) return 'Confirm TikTok music rights before publishing';
    if (settings.explicitConsent !== true) return 'Explicit TikTok post approval is required';
    if (settings.commercialContent === true && settings.yourBrand !== true && settings.brandContent !== true) {
      return 'Choose whether TikTok commercial content promotes your brand, another brand, or both';
    }
    if (settings.commercialContent !== true && (settings.yourBrand === true || settings.brandContent === true)) {
      return 'Turn on TikTok commercial content disclosure before selecting a brand type';
    }
    if (settings.brandContent === true && !['PUBLIC_TO_EVERYONE', 'MUTUAL_FOLLOW_FRIENDS'].includes(String(settings.privacyLevel))) {
      return 'TikTok branded content visibility cannot be private';
    }
  }

  return null;
}

export function validateSocialTargets(
  targets: SocialTargetInput[],
  assets: SocialAssetInput[],
  mode: 'draft' | 'schedule' | 'publish',
) {
  for (const target of targets) {
    const error = validateSocialTarget(target, assets, mode);
    if (error) return error;
  }
  return null;
}
