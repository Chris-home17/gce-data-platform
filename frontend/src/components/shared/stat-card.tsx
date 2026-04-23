import type { ElementType } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { cn } from '@/lib/utils'

export interface StatCardProps {
  title: string
  value: string | number
  subtitle?: string
  icon: ElementType
  iconColor: string
  loading?: boolean
  onClick?: () => void
}

// Small summary card rendered in stat-strip layouts across the dashboard,
// account detail, and KPI monitoring views. Consolidated so every surface
// uses the same card chrome, padding, and skeleton.
export function StatCard({
  title,
  value,
  subtitle,
  icon: Icon,
  iconColor,
  loading,
  onClick,
}: StatCardProps) {
  return (
    <Card
      className={cn(
        'rounded-xl',
        onClick && 'cursor-pointer transition-colors hover:border-primary/40',
      )}
      onClick={onClick}
    >
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
        <div className={cn('rounded-lg p-2', iconColor)}>
          <Icon className="h-4 w-4" />
        </div>
      </CardHeader>
      <CardContent>
        {loading ? (
          <div className="h-8 w-16 animate-pulse rounded bg-muted" />
        ) : (
          <>
            <div className="text-2xl font-bold tabular-nums">{value}</div>
            {subtitle && <p className="mt-0.5 text-xs text-muted-foreground">{subtitle}</p>}
          </>
        )}
      </CardContent>
    </Card>
  )
}
