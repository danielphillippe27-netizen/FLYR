import type { FieldLeadStatus } from '../types/leads'

export const FIELD_LEAD_STATUS_LABELS: Record<FieldLeadStatus, string> = {
  not_home: 'Not Home',
  interested: 'Interested',
  qr_scanned: 'QR Scanned',
  no_answer: 'No Answer',
}

export const FIELD_LEAD_STATUS_COLORS: Record<FieldLeadStatus, string> = {
  not_home: 'var(--accent)',
  interested: '#34C759',
  qr_scanned: '#007AFF',
  no_answer: '#8E8E93',
}

export function formatRelativeTime(iso: string): string {
  const date = new Date(iso)
  const now = new Date()
  const sec = Math.floor((now.getTime() - date.getTime()) / 1000)
  if (sec < 60) return 'just now'
  if (sec < 3600) return `${Math.floor(sec / 60)}m ago`
  if (sec < 86400) return `${Math.floor(sec / 3600)}h ago`
  if (sec < 604800) return `${Math.floor(sec / 86400)}d ago`
  return date.toLocaleDateString()
}
