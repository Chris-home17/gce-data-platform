'use client'

import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { Badge } from '@/components/ui/badge'
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover'

const FE_VERSION = process.env.NEXT_PUBLIC_APP_VERSION ?? 'dev'
const FE_GIT_SHA = process.env.NEXT_PUBLIC_GIT_SHA ?? 'unknown'
const FE_BUILD_DATE = process.env.NEXT_PUBLIC_BUILD_DATE ?? null

function formatBuildDate(iso: string | null | undefined): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3 text-xs">
      <dt className="shrink-0 text-muted-foreground">{label}</dt>
      <dd className="truncate text-right font-mono text-foreground">{value ?? '—'}</dd>
    </div>
  )
}

export function VersionChip() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['version'],
    queryFn: () => api.version.get(),
    staleTime: 5 * 60_000,
    retry: false,
  })

  return (
    <Popover>
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label="Build information"
          className="rounded-full focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
        >
          <Badge
            variant="secondary"
            className="cursor-pointer font-mono tracking-tight"
          >
            v{FE_VERSION}
          </Badge>
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-80">
        <div className="space-y-3">
          <div>
            <p className="text-sm font-semibold leading-none">Build info</p>
            <p className="mt-1 text-xs text-muted-foreground">
              {isLoading ? 'Loading server details…' : isError ? 'Server details unavailable.' : 'Frontend, API, and database schema.'}
            </p>
          </div>

          <dl className="space-y-1.5">
            <Row label="App" value={`v${FE_VERSION} · ${FE_GIT_SHA}`} />
            <Row
              label="API"
              value={data ? `v${data.appVersion}${data.gitSha ? ` · ${data.gitSha}` : ''}` : '—'}
            />
            <Row label="Schema" value={data?.schemaVersion ?? '—'} />
            <Row label="Environment" value={data?.environment ?? '—'} />
            <Row label="Built (frontend)" value={formatBuildDate(FE_BUILD_DATE)} />
            <Row label="Built (API)" value={formatBuildDate(data?.buildDate ?? null)} />
          </dl>
        </div>
      </PopoverContent>
    </Popover>
  )
}
