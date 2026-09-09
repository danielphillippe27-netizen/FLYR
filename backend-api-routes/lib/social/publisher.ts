import type { createAdminClient } from '@/lib/supabase/server';
import { decryptSocialToken, encryptSocialToken } from '@/lib/social/crypto';
import { createSocialMediaUrl } from '@/lib/social/media-url';
import { isExpiredProviderAuthorization } from '@/lib/social/meta';
import { isLinkedInPagePostingRole, linkedinOrganizationScopesEnabled, LINKEDIN_PAGE_POSTING_ROLES, metaApiVersion, platformCredentials, type SocialPlatform } from '@/lib/social/platforms';

type AdminClient = ReturnType<typeof createAdminClient>;
type Asset = { id: string; mime_type: string; byte_size: number; duration_seconds?: number | null; position: number };
type Connection = { id: string; platform: SocialPlatform; external_account_id: string; access_token_encrypted: string; refresh_token_encrypted?: string | null; token_expires_at?: string | null; scopes?: string[] | null; metadata?: Record<string, unknown> };
type Target = { id: string; platform: SocialPlatform; connection_id: string; format?: string | null; caption?: string | null; title?: string | null; settings?: Record<string, unknown>; connection: Connection };
type Post = { id: string; caption: string; title?: string | null; content_type: string; settings?: Record<string, unknown>; assets: Asset[]; targets: Target[] };

function appOrigin(): string {
  return (process.env.NEXT_PUBLIC_SOCIAL_APP_URL || process.env.NEXT_PUBLIC_SALES_APP_URL || 'https://social.wolfgrid.app').replace(/\/$/, '');
}

function delay(milliseconds: number) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function markConnectionExpired(connectionId: string, admin: AdminClient) {
  await admin.from('social_connections').update({
    status: 'expired',
    last_error: 'Authorization expired. Reconnect this account to continue.',
    updated_at: new Date().toISOString(),
  }).eq('id', connectionId);
}

export async function socialAccessToken(connection: Connection, admin: AdminClient): Promise<string> {
  const current = decryptSocialToken(connection.access_token_encrypted);
  const expiresAt = connection.token_expires_at ? new Date(connection.token_expires_at).getTime() : Number.POSITIVE_INFINITY;
  if (expiresAt > Date.now() + 5 * 60_000) return current;
  const credentials = platformCredentials(connection.platform);
  const refresh = connection.refresh_token_encrypted ? decryptSocialToken(connection.refresh_token_encrypted) : null;
  let endpoint = ''; const body = new URLSearchParams();
  if (connection.platform === 'instagram') {
    const url = new URL('https://graph.instagram.com/refresh_access_token'); url.searchParams.set('grant_type', 'ig_refresh_token'); url.searchParams.set('access_token', current);
    const response = await fetch(url); const payload = await response.json();
    if (!response.ok || !payload.access_token) {
      if (isExpiredProviderAuthorization(payload) || !response.ok) await markConnectionExpired(connection.id, admin);
      throw new Error(payload.error?.message || 'Instagram authorization expired');
    }
    await admin.from('social_connections').update({ access_token_encrypted: encryptSocialToken(payload.access_token), token_expires_at: new Date(Date.now() + payload.expires_in * 1000).toISOString(), updated_at: new Date().toISOString() }).eq('id', connection.id);
    return payload.access_token;
  }
  if (!refresh || !credentials.clientId || !credentials.clientSecret) {
    await markConnectionExpired(connection.id, admin);
    throw new Error(`${connection.platform} authorization expired; reconnect it`);
  }
  if (connection.platform === 'tiktok') {
    endpoint = 'https://open.tiktokapis.com/v2/oauth/token/'; body.set('client_key', credentials.clientId); body.set('client_secret', credentials.clientSecret); body.set('grant_type', 'refresh_token'); body.set('refresh_token', refresh);
  } else if (connection.platform === 'linkedin') {
    endpoint = 'https://www.linkedin.com/oauth/v2/accessToken'; body.set('client_id', credentials.clientId); body.set('client_secret', credentials.clientSecret); body.set('grant_type', 'refresh_token'); body.set('refresh_token', refresh);
  } else {
    endpoint = 'https://oauth2.googleapis.com/token'; body.set('client_id', credentials.clientId); body.set('client_secret', credentials.clientSecret); body.set('grant_type', 'refresh_token'); body.set('refresh_token', refresh);
  }
  const response = await fetch(endpoint, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body }); const payload = await response.json();
  if (!response.ok || !payload.access_token) {
    if (isExpiredProviderAuthorization(payload) || /invalid_grant/i.test(String(payload.error || ''))) await markConnectionExpired(connection.id, admin);
    throw new Error(payload.error_description || `${connection.platform} token refresh failed`);
  }
  await admin.from('social_connections').update({ access_token_encrypted: encryptSocialToken(payload.access_token), refresh_token_encrypted: payload.refresh_token ? encryptSocialToken(payload.refresh_token) : connection.refresh_token_encrypted, token_expires_at: new Date(Date.now() + payload.expires_in * 1000).toISOString(), updated_at: new Date().toISOString() }).eq('id', connection.id);
  return payload.access_token;
}

async function instagramRequest(path: string, token: string, values: Record<string, string>) {
  const body = new URLSearchParams({ access_token: token, ...values });
  const response = await fetch(`https://graph.instagram.com/${metaApiVersion()}/${path}`, { method: 'POST', body });
  const payload = await response.json();
  if (!response.ok || payload.error) throw new Error(payload.error?.message || 'Instagram publishing failed');
  return payload;
}

async function waitForInstagramContainer(containerId: string, token: string) {
  for (let attempt = 0; attempt < 24; attempt += 1) {
    const url = new URL(`https://graph.instagram.com/${metaApiVersion()}/${containerId}`);
    url.searchParams.set('fields', 'status_code,status');
    url.searchParams.set('access_token', token);
    const response = await fetch(url, { cache: 'no-store' });
    const payload = await response.json();
    if (!response.ok || payload.error) throw new Error(payload.error?.message || 'Instagram media processing status is unavailable');
    const status = String(payload.status_code || '').toUpperCase();
    if (status === 'FINISHED' || status === 'PUBLISHED') return;
    if (status === 'ERROR' || status === 'EXPIRED') throw new Error(payload.status || `Instagram media processing ${status.toLowerCase()}`);
    await delay(5_000);
  }
  throw new Error('Instagram media is still processing. Try publishing again in a few minutes.');
}

async function publishInstagram(post: Post, connection: Connection, token: string) {
  const urls = post.assets.map((asset) => createSocialMediaUrl(asset.id, appOrigin(), 86_400));
  const accountId = connection.external_account_id;
  let creationId: string;
  if (post.content_type === 'carousel' && urls.length > 1) {
    const children: string[] = [];
    for (let index = 0; index < urls.length; index += 1) {
      const asset = post.assets[index];
      const result = await instagramRequest(`${accountId}/media`, token, asset.mime_type.startsWith('video/') ? { media_type: 'VIDEO', video_url: urls[index], is_carousel_item: 'true' } : { image_url: urls[index], is_carousel_item: 'true' });
      await waitForInstagramContainer(result.id, token);
      children.push(result.id);
    }
    const parent = await instagramRequest(`${accountId}/media`, token, { media_type: 'CAROUSEL', children: children.join(','), caption: post.caption });
    creationId = parent.id;
    await waitForInstagramContainer(creationId, token);
  } else {
    const asset = post.assets[0]; const isVideo = asset.mime_type.startsWith('video/');
    const values: Record<string, string> = { caption: post.caption };
    if (post.content_type === 'story') values.media_type = 'STORIES';
    else if (post.content_type === 'reel' || isVideo) values.media_type = 'REELS';
    values[isVideo ? 'video_url' : 'image_url'] = urls[0];
    const container = await instagramRequest(`${accountId}/media`, token, values); creationId = container.id;
    await waitForInstagramContainer(creationId, token);
  }
  const result = await instagramRequest(`${accountId}/media_publish`, token, { creation_id: creationId });
  return { externalPostId: result.id as string, externalUrl: `https://www.instagram.com/` };
}

async function publishFacebook(post: Post, connection: Connection, token: string) {
  const urls = post.assets.map((asset) => createSocialMediaUrl(asset.id, appOrigin(), 86_400));
  const asset = post.assets[0];
  if (!asset) {
    const body = new URLSearchParams({ message: post.caption, access_token: token });
    const response = await fetch(`https://graph.facebook.com/${metaApiVersion()}/${connection.external_account_id}/feed`, { method: 'POST', body });
    const payload = await response.json();
    if (!response.ok || !payload.id) throw new Error(payload.error?.message || 'Facebook publishing failed');
    return { externalPostId: payload.id as string, externalUrl: `https://www.facebook.com/${payload.id}` };
  }
  const isVideo = asset.mime_type.startsWith('video/');
  if (isVideo && post.content_type === 'reel') {
    const initialize = await fetch(`https://graph.facebook.com/${metaApiVersion()}/${connection.external_account_id}/video_reels`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ upload_phase: 'start', access_token: token }),
    });
    const initialized = await initialize.json();
    if (!initialize.ok || !initialized.video_id || !initialized.upload_url) throw new Error(initialized.error?.message || 'Facebook Reel upload could not start');
    const upload = await fetch(initialized.upload_url, { method: 'POST', headers: { Authorization: `OAuth ${token}`, file_url: urls[0] } });
    const uploaded = await upload.json();
    if (!upload.ok || uploaded.success !== true) throw new Error(uploaded.error?.message || 'Facebook Reel upload failed');
    const finishBody = new URLSearchParams({ access_token: token, video_id: String(initialized.video_id), upload_phase: 'finish', video_state: 'PUBLISHED', description: post.caption });
    const finish = await fetch(`https://graph.facebook.com/${metaApiVersion()}/${connection.external_account_id}/video_reels`, { method: 'POST', body: finishBody });
    const finished = await finish.json();
    if (!finish.ok || finished.success !== true) throw new Error(finished.error?.message || 'Facebook Reel could not be published');
    return { externalPostId: String(initialized.video_id), externalUrl: `https://www.facebook.com/reel/${initialized.video_id}`, processing: true };
  }
  if (!isVideo && post.assets.length > 1) {
    const photoIds: string[] = [];
    for (const url of urls) {
      const uploadBody = new URLSearchParams({ access_token: token, url, published: 'false' });
      const upload = await fetch(`https://graph.facebook.com/${metaApiVersion()}/${connection.external_account_id}/photos`, { method: 'POST', body: uploadBody });
      const uploaded = await upload.json();
      if (!upload.ok || !uploaded.id) throw new Error(uploaded.error?.message || 'Facebook photo upload failed');
      photoIds.push(String(uploaded.id));
    }
    const feedBody = new URLSearchParams({ access_token: token, message: post.caption });
    photoIds.forEach((id, index) => feedBody.set(`attached_media[${index}]`, JSON.stringify({ media_fbid: id })));
    const feed = await fetch(`https://graph.facebook.com/${metaApiVersion()}/${connection.external_account_id}/feed`, { method: 'POST', body: feedBody });
    const published = await feed.json();
    if (!feed.ok || !published.id) throw new Error(published.error?.message || 'Facebook multi-photo post failed');
    return { externalPostId: String(published.id), externalUrl: `https://www.facebook.com/${published.id}` };
  }
  const body = new URLSearchParams({ access_token: token });
  body.set(isVideo ? 'file_url' : 'url', urls[0]);
  body.set(isVideo ? 'description' : 'caption', post.caption);
  const endpoint = isVideo ? 'videos' : 'photos';
  const response = await fetch(`https://graph.facebook.com/${metaApiVersion()}/${connection.external_account_id}/${endpoint}`, { method: 'POST', body });
  const payload = await response.json();
  if (!response.ok || !(payload.id || payload.post_id)) throw new Error(payload.error?.message || 'Facebook publishing failed');
  const id = String(payload.post_id || payload.id);
  return { externalPostId: id, externalUrl: `https://www.facebook.com/${id}`, ...(isVideo ? { processing: true } : {}) };
}

async function publishTikTok(post: Post, token: string) {
  const urls = post.assets.map((asset) => createSocialMediaUrl(asset.id, appOrigin(), 86_400));
  const creatorResponse = await fetch('https://open.tiktokapis.com/v2/post/publish/creator_info/query/', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json; charset=UTF-8' } });
  const creator = await creatorResponse.json();
  if (!creatorResponse.ok || creator.error?.code !== 'ok') throw new Error(creator.error?.message || 'TikTok creator information is unavailable');
  const settings = post.settings || {};
  const privacy = typeof settings.privacyLevel === 'string' ? settings.privacyLevel : '';
  const privacyOptions = Array.isArray(creator.data?.privacy_level_options) ? creator.data.privacy_level_options : [];
  if (!privacy || !privacyOptions.includes(privacy)) throw new Error('Choose a TikTok privacy option before publishing');
  if (settings.musicUsageConfirmed !== true || settings.explicitConsent !== true) throw new Error('TikTok music authorization and explicit posting approval are required');
  if (settings.allowComments === true && creator.data?.comment_disabled === true) throw new Error('Comments are unavailable for this TikTok creator');
  if (settings.allowDuet === true && creator.data?.duet_disabled === true) throw new Error('Duet is unavailable for this TikTok creator');
  if (settings.allowStitch === true && creator.data?.stitch_disabled === true) throw new Error('Stitch is unavailable for this TikTok creator');
  if (settings.commercialContent === true && settings.yourBrand !== true && settings.brandContent !== true) throw new Error('Choose a TikTok commercial content disclosure');
  if (settings.commercialContent !== true && (settings.yourBrand === true || settings.brandContent === true)) throw new Error('Turn on TikTok commercial content disclosure before selecting a brand type');
  if (settings.brandContent === true && !['PUBLIC_TO_EVERYONE', 'MUTUAL_FOLLOW_FRIENDS'].includes(privacy)) throw new Error('TikTok branded content visibility cannot be private');
  const isPhoto = post.content_type === 'tiktok_photo' || post.assets.every((asset) => asset.mime_type.startsWith('image/'));
  const endpoint = isPhoto ? 'https://open.tiktokapis.com/v2/post/publish/content/init/' : 'https://open.tiktokapis.com/v2/post/publish/video/init/';
  const videoAsset = isPhoto ? null : post.assets.find((asset) => asset.mime_type.startsWith('video/'));
  if (!isPhoto && !videoAsset) throw new Error('TikTok requires a video file');
  const maxVideoDuration = Number(creator.data?.max_video_post_duration_sec || 0);
  if (videoAsset && maxVideoDuration > 0 && (!videoAsset.duration_seconds || videoAsset.duration_seconds > maxVideoDuration)) {
    throw new Error(videoAsset.duration_seconds
      ? `TikTok limits this account to videos of ${maxVideoDuration} seconds or less`
      : 'TikTok video duration is unavailable; upload the video again before publishing');
  }
  const body = isPhoto
    ? { post_info: { title: post.caption, privacy_level: privacy, disable_comment: settings.allowComments !== true, auto_add_music: settings.autoAddMusic === true, brand_content_toggle: settings.brandContent === true, brand_organic_toggle: settings.yourBrand === true, is_aigc: settings.aiGeneratedContent === true }, source_info: { source: 'PULL_FROM_URL', photo_images: urls, photo_cover_index: 0 }, post_mode: 'DIRECT_POST', media_type: 'PHOTO' }
    : { post_info: { title: post.caption, privacy_level: privacy, disable_duet: settings.allowDuet !== true, disable_comment: settings.allowComments !== true, disable_stitch: settings.allowStitch !== true, brand_content_toggle: settings.brandContent === true, brand_organic_toggle: settings.yourBrand === true, is_aigc: settings.aiGeneratedContent === true }, source_info: { source: 'FILE_UPLOAD', video_size: videoAsset!.byte_size, chunk_size: Math.min(videoAsset!.byte_size, 64 * 1024 * 1024), total_chunk_count: Math.ceil(videoAsset!.byte_size / Math.min(videoAsset!.byte_size, 64 * 1024 * 1024)) } };
  const response = await fetch(endpoint, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) });
  const payload = await response.json();
  if (!response.ok || payload.error?.code !== 'ok' || !payload.data?.publish_id) {
    const code = payload.error?.code && payload.error.code !== 'ok' ? ` [${payload.error.code}]` : '';
    throw new Error(`${payload.error?.message || 'TikTok publishing failed'}${code}`);
  }
  if (videoAsset) {
    const uploadUrl = payload.data?.upload_url;
    if (!uploadUrl) throw new Error('TikTok did not provide a video upload URL');
    const maxChunkSize = 64 * 1024 * 1024;
    const chunkSize = Math.min(videoAsset.byte_size, maxChunkSize);
    const totalChunkCount = Math.ceil(videoAsset.byte_size / chunkSize);
    const sourceUrl = createSocialMediaUrl(videoAsset.id, appOrigin(), 86_400);
    for (let index = 0; index < totalChunkCount; index += 1) {
      const start = index * chunkSize;
      const end = Math.min(start + chunkSize, videoAsset.byte_size) - 1;
      const length = end - start + 1;
      const media = await fetch(sourceUrl, { headers: totalChunkCount > 1 ? { Range: `bytes=${start}-${end}` } : undefined });
      if (!media.ok || !media.body) throw new Error('WolfSocial could not read the selected TikTok video');
      const upload = await fetch(uploadUrl, {
        method: 'PUT',
        headers: { 'Content-Type': videoAsset.mime_type, 'Content-Length': String(length), 'Content-Range': `bytes ${start}-${end}/${videoAsset.byte_size}` },
        body: media.body,
        duplex: 'half',
      } as RequestInit & { duplex: 'half' });
      if (!upload.ok) {
        const details = await upload.text();
        throw new Error(details || `TikTok video upload failed (${upload.status})`);
      }
    }
  }
  return { externalPublishId: payload.data.publish_id as string, processing: true };
}

async function publishYouTube(post: Post, token: string) {
  const asset = post.assets.find((item) => item.mime_type.startsWith('video/'));
  if (!asset) throw new Error('YouTube Shorts requires a video');
  const sourceUrl = createSocialMediaUrl(asset.id, appOrigin(), 7200);
  const media = await fetch(sourceUrl);
  if (!media.ok || !media.body) throw new Error('Could not read the YouTube video');
  const privacy = typeof post.settings?.privacyStatus === 'string' && ['private', 'unlisted', 'public'].includes(post.settings.privacyStatus) ? post.settings.privacyStatus : 'private';
  const metadata = { snippet: { title: post.title || 'WolfSocial Short', description: post.caption, categoryId: '22', tags: ['Shorts'] }, status: { privacyStatus: privacy, selfDeclaredMadeForKids: post.settings?.madeForKids === true } };
  const initialize = await fetch('https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json; charset=UTF-8', 'X-Upload-Content-Type': asset.mime_type, 'X-Upload-Content-Length': String(asset.byte_size) }, body: JSON.stringify(metadata) });
  const uploadUrl = initialize.headers.get('location');
  if (!initialize.ok || !uploadUrl) { const message = await initialize.text(); throw new Error(message || 'YouTube upload could not start'); }
  const upload = await fetch(uploadUrl, { method: 'PUT', headers: { 'Content-Type': asset.mime_type, 'Content-Length': String(asset.byte_size) }, body: media.body, duplex: 'half' } as RequestInit & { duplex: 'half' });
  const payload = await upload.json();
  if (!upload.ok || !payload.id) throw new Error(payload.error?.message || 'YouTube upload failed');
  return { externalPostId: payload.id as string, externalUrl: `https://www.youtube.com/shorts/${payload.id}`, processing: true };
}

function linkedinHeaders(token: string, contentType = 'application/json') {
  return { Authorization: `Bearer ${token}`, 'Content-Type': contentType, 'LinkedIn-Version': process.env.LINKEDIN_API_VERSION || '202601', 'X-Restli-Protocol-Version': '2.0.0' };
}

async function confirmLinkedInPagePostingRole(organizationUrn: string, token: string) {
  for (const role of LINKEDIN_PAGE_POSTING_ROLES) {
    const url = new URL('https://api.linkedin.com/rest/organizationAcls');
    url.searchParams.set('q', 'roleAssignee');
    url.searchParams.set('role', role);
    url.searchParams.set('state', 'APPROVED');
    const response = await fetch(url, { headers: linkedinHeaders(token) });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.message || 'LinkedIn Page access could not be confirmed');
    const match = (payload.elements || []).find((acl: Record<string, unknown>) => acl.organization === organizationUrn && isLinkedInPagePostingRole(acl.role));
    if (match) return role;
  }
  throw new Error('The connected LinkedIn member must be a Page administrator or content admin to publish for this Company Page.');
}

async function uploadLinkedInImage(asset: Asset, authorUrn: string, token: string) {
  const initialize = await fetch('https://api.linkedin.com/rest/images?action=initializeUpload', {
    method: 'POST', headers: linkedinHeaders(token), body: JSON.stringify({ initializeUploadRequest: { owner: authorUrn } }),
  });
  const initialized = await initialize.json();
  const uploadUrl = initialized.value?.uploadUrl;
  const imageUrn = initialized.value?.image;
  if (!initialize.ok || !uploadUrl || !imageUrn) throw new Error(initialized.message || 'LinkedIn image upload could not start');
  const media = await fetch(createSocialMediaUrl(asset.id, appOrigin(), 7200));
  if (!media.ok) throw new Error('LinkedIn could not read the selected image');
  const upload = await fetch(uploadUrl, { method: 'PUT', headers: { Authorization: `Bearer ${token}`, 'Content-Type': asset.mime_type }, body: await media.arrayBuffer() });
  if (!upload.ok) throw new Error('LinkedIn image upload failed');
  return imageUrn as string;
}

type LinkedInVideoUploadInstruction = { uploadUrl: string; firstByte: number; lastByte: number };

async function uploadLinkedInVideo(asset: Asset, authorUrn: string, token: string) {
  const initialize = await fetch('https://api.linkedin.com/rest/videos?action=initializeUpload', {
    method: 'POST',
    headers: linkedinHeaders(token),
    body: JSON.stringify({ initializeUploadRequest: { owner: authorUrn, fileSizeBytes: asset.byte_size, uploadCaptions: false, uploadThumbnail: false } }),
  });
  const initialized = await initialize.json();
  const videoUrn = initialized.value?.video;
  const uploadToken = initialized.value?.uploadToken;
  const instructions = initialized.value?.uploadInstructions as LinkedInVideoUploadInstruction[] | undefined;
  if (!initialize.ok || !videoUrn || uploadToken === undefined || !Array.isArray(instructions) || !instructions.length) {
    throw new Error(initialized.message || 'LinkedIn video upload could not start');
  }

  const sourceUrl = createSocialMediaUrl(asset.id, appOrigin(), 7200);
  const uploadedPartIds: string[] = [];
  for (const instruction of instructions) {
    const firstByte = Number(instruction.firstByte);
    const lastByte = Math.min(Number(instruction.lastByte), asset.byte_size - 1);
    if (!instruction.uploadUrl || !Number.isInteger(firstByte) || !Number.isInteger(lastByte) || firstByte < 0 || lastByte < firstByte) {
      throw new Error('LinkedIn returned invalid video upload instructions');
    }
    const length = lastByte - firstByte + 1;
    const media = await fetch(sourceUrl, { headers: { Range: `bytes=${firstByte}-${lastByte}` } });
    const wholeFile = firstByte === 0 && lastByte === asset.byte_size - 1;
    if ((!media.ok || !media.body) || (!wholeFile && media.status !== 206)) throw new Error('WolfSocial could not read a LinkedIn video part');
    const upload = await fetch(instruction.uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/octet-stream', 'Content-Length': String(length) },
      body: media.body,
      duplex: 'half',
    } as RequestInit & { duplex: 'half' });
    const etag = upload.headers.get('etag');
    if (!upload.ok || !etag) throw new Error('LinkedIn video part upload failed');
    uploadedPartIds.push(etag);
  }

  const finalize = await fetch('https://api.linkedin.com/rest/videos?action=finalizeUpload', {
    method: 'POST',
    headers: linkedinHeaders(token),
    body: JSON.stringify({ finalizeUploadRequest: { video: videoUrn, uploadToken, uploadedPartIds } }),
  });
  if (!finalize.ok) {
    const payload = await finalize.json().catch(() => ({}));
    throw new Error(payload.message || 'LinkedIn video upload could not be finalized');
  }

  for (let attempt = 0; attempt < 48; attempt += 1) {
    const statusResponse = await fetch(`https://api.linkedin.com/rest/videos/${encodeURIComponent(videoUrn)}`, { headers: linkedinHeaders(token) });
    const statusPayload = await statusResponse.json();
    if (!statusResponse.ok) throw new Error(statusPayload.message || 'LinkedIn video processing status is unavailable');
    if (statusPayload.status === 'AVAILABLE') return videoUrn as string;
    if (statusPayload.status === 'PROCESSING_FAILED') throw new Error('LinkedIn could not process the uploaded video');
    await delay(5_000);
  }
  throw new Error('LinkedIn video is still processing. Retry the post in a few minutes.');
}

export async function publishLinkedIn(post: Post, connection: Connection, token: string) {
  const authorUrn = typeof connection.metadata?.authorUrn === 'string'
    ? connection.metadata.authorUrn
    : `urn:li:${connection.metadata?.accountType === 'organization' ? 'organization' : 'person'}:${connection.external_account_id}`;
  const isOrganization = connection.metadata?.accountType === 'organization';
  if (isOrganization) {
    if (!linkedinOrganizationScopesEnabled()) throw new Error('LinkedIn Company Page publishing is disabled until Community Management API approval is complete.');
    if (!connection.scopes?.includes('w_organization_social') || !connection.scopes.includes('rw_organization_admin')) {
      throw new Error('Reconnect LinkedIn after Company Page approval to grant the organization publishing permissions.');
    }
    if (post.settings?.visibility === 'CONNECTIONS') throw new Error('LinkedIn Company Page posts must use public visibility.');
    await confirmLinkedInPagePostingRole(authorUrn, token);
  } else if (!connection.scopes?.includes('w_member_social')) {
    throw new Error('Reconnect LinkedIn and approve Share on LinkedIn before publishing to a personal profile.');
  }
  const images = post.assets.filter((asset) => asset.mime_type.startsWith('image/'));
  const videos = post.assets.filter((asset) => asset.mime_type.startsWith('video/'));
  const imageUrns: string[] = [];
  for (const image of images.slice(0, 20)) imageUrns.push(await uploadLinkedInImage(image, authorUrn, token));
  const videoUrn = videos[0] ? await uploadLinkedInVideo(videos[0], authorUrn, token) : null;
  const content = videoUrn
    ? { media: { id: videoUrn, title: post.title || 'WolfSocial video' } }
    : imageUrns.length > 1
    ? { multiImage: { images: imageUrns.map((id) => ({ id, altText: post.title || 'WolfSocial image' })) } }
    : imageUrns.length === 1
      ? { media: { id: imageUrns[0], title: post.title || 'WolfSocial image' } }
      : undefined;
  const body: Record<string, unknown> = {
    author: authorUrn,
    commentary: post.caption,
    visibility: typeof post.settings?.visibility === 'string' ? post.settings.visibility : 'PUBLIC',
    distribution: { feedDistribution: 'MAIN_FEED', targetEntities: [], thirdPartyDistributionChannels: [] },
    lifecycleState: 'PUBLISHED',
    isReshareDisabledByAuthor: post.settings?.disableReshare === true,
  };
  if (content) body.content = content;
  const response = await fetch('https://api.linkedin.com/rest/posts', { method: 'POST', headers: linkedinHeaders(token), body: JSON.stringify(body) });
  const responseText = await response.text();
  if (!response.ok) {
    let message = responseText; try { message = JSON.parse(responseText).message || responseText; } catch { /* plain response */ }
    throw new Error(message || 'LinkedIn publishing failed');
  }
  const id = response.headers.get('x-restli-id') || response.headers.get('x-linkedin-id') || `linkedin:${Date.now()}`;
  return { externalPostId: id, externalUrl: 'https://www.linkedin.com/feed/' };
}

async function loadPost(postId: string, admin: AdminClient): Promise<Post> {
  const { data, error } = await admin.from('social_posts').select('id,caption,title,content_type,settings,social_post_assets(position,social_media_assets(id,mime_type,byte_size,duration_seconds)),social_post_targets(id,platform,connection_id,format,caption,title,settings,social_connections(id,platform,external_account_id,access_token_encrypted,refresh_token_encrypted,token_expires_at,scopes,metadata))').eq('id', postId).single();
  if (error || !data) throw new Error(error?.message || 'Social post not found');
  const assets = (data.social_post_assets || []).map((row: any) => ({ ...row.social_media_assets, position: row.position })).sort((a: Asset, b: Asset) => a.position - b.position);
  const targets = (data.social_post_targets || []).map((row: any) => ({ id: row.id, platform: row.platform, connection_id: row.connection_id, format: row.format, caption: row.caption, title: row.title, settings: row.settings, connection: row.social_connections }));
  return { id: data.id, caption: data.caption, title: data.title, content_type: data.content_type, settings: data.settings, assets, targets };
}

export async function publishSocialPost(postId: string, admin: AdminClient) {
  const post = await loadPost(postId, admin);
  for (const target of post.targets) {
    await publishSocialTarget(target.id, admin);
  }
  return reconcileSocialPostStatus(postId, admin);
}

export async function reconcileSocialPostStatus(postId: string, admin: AdminClient) {
  const { data: targets } = await admin.from('social_post_targets').select('status,last_error').eq('post_id', postId);
  const values = targets || [];
  const failed = values.filter((target) => target.status === 'failed').length;
  const complete = values.filter((target) => target.status === 'published').length;
  const processing = values.some((target) => ['pending', 'uploading', 'processing'].includes(target.status));
  const status = processing ? 'publishing' : failed === values.length ? 'failed' : failed > 0 ? 'partial_failed' : 'published';
  await admin.from('social_posts').update({ status, published_at: status === 'published' ? new Date().toISOString() : null, last_error: failed ? `${failed} account${failed === 1 ? '' : 's'} failed` : null, updated_at: new Date().toISOString() }).eq('id', postId);
  return { status, outcomes: { published: complete, failed, processing: values.length - complete - failed } };
}

export async function publishSocialTarget(targetId: string, admin: AdminClient) {
  const { data: targetRow, error } = await admin.from('social_post_targets').select('id,post_id,platform,connection_id,format,caption,title,settings,social_connections(id,platform,external_account_id,access_token_encrypted,refresh_token_encrypted,token_expires_at,scopes,metadata)').eq('id', targetId).single();
  if (error || !targetRow) throw new Error(error?.message || 'Social target not found');
  const post = await loadPost(targetRow.post_id, admin);
  const target = post.targets.find((item) => item.id === targetId);
  if (!target) throw new Error('Social target is no longer available');
  const targetPost: Post = {
    ...post,
    caption: target.caption ?? post.caption,
    title: target.title ?? post.title,
    content_type: target.format || post.content_type,
    settings: { ...(post.settings || {}), ...(target.settings || {}) },
    targets: [target],
  };
  try {
    const token = await socialAccessToken(target.connection, admin);
    const result = target.platform === 'facebook'
      ? await publishFacebook(targetPost, target.connection, token)
      : target.platform === 'instagram'
        ? await publishInstagram(targetPost, target.connection, token)
        : target.platform === 'tiktok'
          ? await publishTikTok(targetPost, token)
          : target.platform === 'youtube'
            ? await publishYouTube(targetPost, token)
            : await publishLinkedIn(targetPost, target.connection, token);
    const processing = 'processing' in result && result.processing;
    await admin.from('social_post_targets').update({ status: processing ? 'processing' : 'published', external_publish_id: 'externalPublishId' in result ? result.externalPublishId : null, external_post_id: 'externalPostId' in result ? result.externalPostId : null, external_url: 'externalUrl' in result ? result.externalUrl : null, next_attempt_at: null, last_error: null, updated_at: new Date().toISOString() }).eq('id', target.id);
  } catch (publishError) {
    const message = publishError instanceof Error ? publishError.message : 'Publishing failed';
    if (isExpiredProviderAuthorization(publishError)) {
      await markConnectionExpired(target.connection.id, admin);
    }
    await admin.from('social_post_targets').update({ status: 'failed', next_attempt_at: new Date(Date.now() + 5 * 60_000).toISOString(), last_error: message, updated_at: new Date().toISOString() }).eq('id', target.id);
  }
  return reconcileSocialPostStatus(targetRow.post_id, admin);
}
