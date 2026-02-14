import type { ReactNode } from 'react'

interface SuccessMetricBarProps {
  title: string
  value: number
  icon: ReactNode
  color: string
  description?: string
}

export default function SuccessMetricBar({
  title,
  value,
  icon,
  color,
  description,
}: SuccessMetricBarProps) {
  const progress = Math.min(value / 100, 1)
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8, padding: '4px 0' }}>
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
        }}
      >
        <span style={{ color, fontSize: 16 }}>{icon}</span>
        <span style={{ fontSize: 15, fontWeight: 500, color: 'var(--text)', flex: 1 }}>
          {title}
        </span>
        <span style={{ fontSize: 14, fontWeight: 600, color: 'var(--muted)' }}>
          {value.toFixed(1)}%
        </span>
      </div>
      {description && (
        <span style={{ fontSize: 12, color: 'var(--muted)' }}>{description}</span>
      )}
      <div
        style={{
          height: 6,
          borderRadius: 3,
          background: 'rgba(255,255,255,0.1)',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            height: '100%',
            width: `${progress * 100}%`,
            background: color,
            borderRadius: 3,
          }}
        />
      </div>
    </div>
  )
}
