import { NextResponse, type NextRequest } from "next/server";
import { resolveAccessContext } from "../access/_utils";

export async function resolveDialerWorkspace(request: NextRequest) {
  const context = await resolveAccessContext(request);
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

  const requestedWorkspaceId = request.nextUrl.searchParams.get("workspaceId")?.trim();
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
