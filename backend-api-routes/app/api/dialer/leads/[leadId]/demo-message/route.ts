import { NextRequest, NextResponse } from "next/server";
import { resolveDialerWorkspace } from "../../../_utils";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RouteContext = {
  params: Promise<{ leadId: string }>;
};

type OfferKey = "solo" | "team" | "brokerage";

const OFFER_TITLES: Record<OfferKey, string> = {
  solo: "Solo",
  team: "Team",
  brokerage: "Brokerage",
};

function cleanString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function normalizedOffer(value: unknown): OfferKey {
  const normalized = cleanString(value)?.toLowerCase().replace(/[_\s-]+/g, "-");
  switch (normalized) {
    case "team":
      return "team";
    case "brokerage":
    case "brokerage-office":
      return "brokerage";
    case "solo":
    default:
      return "solo";
  }
}

function configuredOfferUrl(offer: OfferKey): string | null {
  const key = `FLYR_DEMO_${offer.toUpperCase()}_URL`;
  return cleanString(process.env[key]);
}

function demoUrl(offer: OfferKey): string {
  const configured = configuredOfferUrl(offer);
  if (configured) return configured;

  const base =
    cleanString(process.env.FLYR_DEMO_BASE_URL) ??
    "https://www.flyrpro.app/demo-1?source=DANIELPHILLIPPE";
  const url = new URL(base);
  url.searchParams.set("offer", offer);
  return url.toString();
}

export async function POST(request: NextRequest, _routeContext: RouteContext) {
  try {
    const payload = await request.json().catch(() => ({}));
    const offer = normalizedOffer(payload.offer ?? payload.offerType ?? payload.plan);
    const requestedWorkspaceId = cleanString(payload.workspaceId);
    const url = new URL(request.url);
    if (requestedWorkspaceId) {
      url.searchParams.set("workspaceId", requestedWorkspaceId);
    }

    const { response } = await resolveDialerWorkspace(
      new NextRequest(url, {
        headers: request.headers,
        method: request.method,
      })
    );
    if (response) return response;

    const link = demoUrl(offer);
    const offerTitle = OFFER_TITLES[offer];

    return NextResponse.json({
      demoUrl: link,
      demoLinkToken: null,
      textBody: `Hey, Daniel with WolfGrid. Here is the ${offerTitle} demo: ${link}`,
      emailSubject: `Quick WolfGrid ${offerTitle} demo`,
      emailBody: `Hey,\n\nDaniel with WolfGrid here. Here is the ${offerTitle} demo video: ${link}\n\nBest,\nDaniel`,
      tracked: false,
      offer,
    });
  } catch (error) {
    console.error("[dialer/leads/demo-message] POST", error);
    return NextResponse.json(
      { error: "Failed to prepare demo message." },
      { status: 500 }
    );
  }
}
