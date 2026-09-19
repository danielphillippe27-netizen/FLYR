import { NextRequest, NextResponse } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import { createZoomState, zoomAuthorizeUrl } from '@/lib/zoom';

export async function GET(request: NextRequest) {
  const user = await resolveUserFromRequest(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const platform = request.nextUrl.searchParams.get('platform') === 'ios' ? 'ios' : 'web';
    const state = createZoomState(user.id, platform);
    return NextResponse.json({
      success: true,
      authorizeUrl: zoomAuthorizeUrl(request.nextUrl.origin, state),
    });
  } catch (error) {
    return NextResponse.json({
      error: error instanceof Error ? error.message : 'Unable to start Zoom authorization.',
    }, { status: 500 });
  }
}
