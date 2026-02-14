import { useNavigate } from 'react-router-dom'
import type { FieldLead } from '../types/leads'
import { FIELD_LEAD_STATUS_LABELS, FIELD_LEAD_STATUS_COLORS, formatRelativeTime } from '../lib/leadDisplay'

interface LeadRowProps {
  lead: FieldLead
}

export default function LeadRow({ lead }: LeadRowProps) {
  const navigate = useNavigate()
  const displayName = lead.name?.trim() ? lead.name : 'Unknown'
  const notePreview = lead.notes?.trim()
    ? (lead.notes.length > 30 ? lead.notes.slice(0, 30) + '…' : lead.notes)
    : lead.qr_code
      ? `QR: ${lead.qr_code}`
      : ''

  return (
    <button
      type="button"
      onClick={() => navigate(`/leads/${lead.id}`)}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        width: '100%',
        padding: '12px 16px',
        border: 'none',
        background: 'transparent',
        color: 'inherit',
        textAlign: 'left',
        cursor: 'pointer',
        font: 'inherit',
      }}
    >
      <span style={{ fontSize: 20, color: 'var(--accent)' }} aria-hidden>📍</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 600, fontSize: 16, marginBottom: 4 }}>{lead.address}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap', marginBottom: 2 }}>
          <span style={{ fontSize: 15 }}>{displayName}</span>
          <span style={{ color: 'var(--muted)' }}>•</span>
          <span
            style={{
              fontSize: 11,
              fontWeight: 500,
              color: '#fff',
              background: FIELD_LEAD_STATUS_COLORS[lead.status],
              padding: '4px 8px',
              borderRadius: 8,
            }}
          >
            {FIELD_LEAD_STATUS_LABELS[lead.status]}
          </span>
        </div>
        <div style={{ fontSize: 13, color: 'var(--muted)' }}>
          {formatRelativeTime(lead.created_at)}
          {notePreview && <> • {notePreview}</>}
        </div>
      </div>
      <span style={{ color: 'var(--muted)', fontSize: 14 }}>›</span>
    </button>
  )
}
