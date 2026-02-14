import type { ReactNode } from 'react'

interface StatCardProps {
  icon: ReactNode
  color: string
  title: string
  value: number | string
}

function formatValue(value: number | string): string {
  if (typeof value === 'number') {
    return value % 1 === 0 ? String(value) : value.toFixed(1)
  }
  return String(value)
}

export default function StatCard({ icon, color, title, value }: StatCardProps) {
  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: 8,
        padding: '20px 12px',
        background: 'color-mix(in srgb, var(--bg-secondary) 50%, transparent)',
        borderRadius: 16,
        flex: 1,
        minWidth: 0,
      }}
    >
      <span style={{ color, fontSize: 28, lineHeight: 1 }}>{icon}</span>
      <span style={{ fontSize: 24, fontWeight: 700, color: 'var(--text)' }}>
        {formatValue(value)}
      </span>
      <span style={{ fontSize: 13, color: 'var(--muted)' }}>{title}</span>
    </div>
  )
}
