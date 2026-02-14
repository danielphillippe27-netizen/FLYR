import type { ReactNode } from 'react'

interface CompactStatRowProps {
  icon: ReactNode
  label: string
  progress: number
  value: string
}

const barAccent = 'var(--accent)'

export default function CompactStatRow({ icon, label, progress, value }: CompactStatRowProps) {
  const capped = Math.max(0, Math.min(1, progress))
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        minHeight: 52,
      }}
    >
      <span
        style={{
          color: barAccent,
          fontSize: 20,
          width: 24,
          height: 20,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {icon}
      </span>
      <span style={{ fontSize: 15, fontWeight: 600, color: 'var(--text)', flex: '0 0 auto' }}>
        {label}
      </span>
      <div
        style={{
          flex: 1,
          minWidth: 0,
          height: 6,
          borderRadius: 3,
          background: 'rgba(255,255,255,0.2)',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            height: '100%',
            width: `${capped * 100}%`,
            background: barAccent,
            borderRadius: 3,
          }}
        />
      </div>
      <span
        style={{
          fontSize: 20,
          fontWeight: 600,
          fontVariantNumeric: 'tabular-nums',
          color: 'var(--text)',
          minWidth: 40,
          textAlign: 'right',
        }}
      >
        {value}
      </span>
    </div>
  )
}
