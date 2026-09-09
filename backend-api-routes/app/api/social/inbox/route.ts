import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { data, error } = await context.admin.from('social_threads').select('id,platform,kind,external_id,subject,last_message_at,unread_count,needs_reply,metadata,social_contacts(id,display_name,username,avatar_url,email,phone,sales_lead_id),social_connections!inner(id,account_name,user_id),social_interactions(id,kind,body,direction,status,occurred_at,sender_name)').eq('social_workspace_id', context.socialWorkspaceId).eq('social_connections.user_id', context.user.id).order('last_message_at', { ascending: false }).limit(100);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ threads: data ?? [], limitations: { tiktok: 'TikTok Content Posting does not provide comments or DMs.', youtubeMessages: 'YouTube does not provide direct messages; comments and replies are supported.' } });
}

