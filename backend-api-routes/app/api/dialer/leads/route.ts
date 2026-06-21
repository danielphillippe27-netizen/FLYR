import { NextResponse, type NextRequest } from "next/server";
import { resolveDialerWorkspace } from "../_utils";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const { response, context } = await resolveDialerWorkspace(request);
    if (response) return response;

    return NextResponse.json({
      leads: [],
      workspaceId: context.workspace!.id,
    });
  } catch (error) {
    console.error("[dialer/leads]", error);
    return NextResponse.json(
      { error: "Failed to load dialer leads." },
      { status: 500 }
    );
  }
}

export async function POST(request: NextRequest) {
  try {
    const { response, context } = await resolveDialerWorkspace(request);
    if (response) return response;

    return NextResponse.json({
      leads: [],
      importedCount: 0,
      workspaceId: context.workspace!.id,
      warning: "Dialer lead storage is not configured yet.",
    });
  } catch (error) {
    console.error("[dialer/leads] POST", error);
    return NextResponse.json(
      { error: "Failed to import dialer leads." },
      { status: 500 }
    );
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const { response } = await resolveDialerWorkspace(request);
    if (response) return response;

    return NextResponse.json(
      { error: "Dialer lead storage is not configured yet." },
      { status: 501 }
    );
  } catch (error) {
    console.error("[dialer/leads] PATCH", error);
    return NextResponse.json(
      { error: "Failed to update dialer lead." },
      { status: 500 }
    );
  }
}

export async function DELETE(request: NextRequest) {
  try {
    const { response } = await resolveDialerWorkspace(request);
    if (response) return response;

    return NextResponse.json(
      { error: "Dialer lead storage is not configured yet." },
      { status: 501 }
    );
  } catch (error) {
    console.error("[dialer/leads] DELETE", error);
    return NextResponse.json(
      { error: "Failed to remove dialer lead." },
      { status: 500 }
    );
  }
}
