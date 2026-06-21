const API_BASE = import.meta.env.VITE_FLYR_API_URL?.replace(/\/$/, '') ?? ''

export type LeadTextMessage = {
  id: string
  direction: 'inbound' | 'outbound'
  from: string
  to: string
  body: string
  status: string
  createdAt: string
  sentAt?: string | null
  receivedAt?: string | null
}

async function requestJson<T>(url: string, accessToken: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    ...init,
    headers: {
      ...(init?.headers ?? {}),
      Authorization: `Bearer ${accessToken}`,
    },
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) {
    throw new Error(json.error ?? 'Texting request failed')
  }
  return json as T
}

export async function fetchLeadTexts(leadId: string, accessToken: string): Promise<LeadTextMessage[]> {
  const json = await requestJson<{ messages: LeadTextMessage[] }>(
    `${API_BASE}/api/dialer/leads/${encodeURIComponent(leadId)}/sms`,
    accessToken
  )
  return json.messages ?? []
}

export async function sendLeadText(
  leadId: string,
  body: string,
  accessToken: string
): Promise<LeadTextMessage> {
  const json = await requestJson<{ message: LeadTextMessage }>(
    `${API_BASE}/api/dialer/leads/${encodeURIComponent(leadId)}/sms`,
    accessToken,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ body }),
    }
  )
  return json.message
}
