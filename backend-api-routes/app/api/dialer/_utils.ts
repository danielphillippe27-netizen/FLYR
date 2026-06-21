import { NextResponse, type NextRequest } from "next/server";
import { resolveAccessContext } from "../access/_utils";

export async function resolveDialerWorkspace(request: NextRequest) {
  const requestedWorkspaceId = request.nextUrl.searchParams.get("workspaceId")?.trim();
  const context = await resolveAccessContext(request, {
    workspaceId: requestedWorkspaceId,
  });
  if (!context) {
    return {
      response: NextResponse.json({ error: "Unauthorized" }, { status: 401 }),
      context: null,
    };
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

  if (requestedWorkspaceId && requestedWorkspaceId !== context.workspace.id) {
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
