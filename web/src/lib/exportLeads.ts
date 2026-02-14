import type { FieldLead } from '../types/leads'
import { FIELD_LEAD_STATUS_LABELS } from './leadDisplay'

function escapeCsv(value: string): string {
  if (value.includes(',') || value.includes('\n') || value.includes('"')) {
    return '"' + value.replace(/"/g, '""') + '"'
  }
  return value
}

const CSV_HEADER = 'Address,Name,Phone,Status,Notes,QR Code,Campaign ID,Session ID,Created At\n'

export function leadsToCsv(leads: FieldLead[]): string {
  const dateFmt = (iso: string) => {
    const d = new Date(iso)
    return d.toISOString().slice(0, 16).replace('T', ' ')
  }
  let out = CSV_HEADER
  for (const l of leads) {
    out += [
      escapeCsv(l.address),
      escapeCsv(l.name ?? ''),
      escapeCsv(l.phone ?? ''),
      escapeCsv(FIELD_LEAD_STATUS_LABELS[l.status]),
      escapeCsv(l.notes ?? ''),
      escapeCsv(l.qr_code ?? ''),
      l.campaign_id ?? '',
      l.session_id ?? '',
      dateFmt(l.created_at),
    ].join(',') + '\n'
  }
  return out
}

export function downloadCsv(leads: FieldLead[], filename: string) {
  const csv = leadsToCsv(leads)
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
