import { NextResponse, type NextRequest } from "next/server";
import { resolveAccessContext } from "../access/_utils";

export async function resolveDialerWorkspace(request: NextRequest) {
  const requestedWorkspaceId = request.nextUrl.searchParams.get("workspaceId")?.trim();
  let context = await resolveAccessContext(request, {
    workspaceId: requestedWorkspaceId,
  });
  if (!context) {
    return {
      response: NextResponse.json({ error: "Unauthorized" }, { status: 401 }),
      context: null,
    };
  }

  // Native clients can briefly retain a workspace that was changed or removed.
  // Fall back to the authenticated user's primary accessible workspace instead
  // of rejecting an otherwise valid message/call request.
  if (requestedWorkspaceId && (!context.workspace?.id || !context.hasAccess)) {
    context = await resolveAccessContext(request);
  }

  if (!context.workspace?.id || !context.hasAccess) {
    return {
      response: NextResponse.json(
        { error: "Dialer workspace is not available." },
        { status: 403 }
      ),
      context: null,
    };
  }

  return { response: null, context };
}
