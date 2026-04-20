'use client'

import { Suspense, useState, useCallback } from 'react'
import { useSearchParams } from 'next/navigation'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  Lock,
  CheckCircle2,
  AlertCircle,
  Clock,
  Building2,
  Calendar,
  Layers,
  Send,
  TrendingUp,
  TrendingDown,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { api } from '@/lib/api'
import type { AssignmentWithSubmission, SubmissionTokenContext } from '@/types/api'

const KPI_MONITORING_REFRESH_EVENT = 'gce:kpi-monitoring-refresh'

// ---------------------------------------------------------------------------
// Fonts + global styles for this isolated page
// ---------------------------------------------------------------------------

const PAGE_STYLES = `
  @import url('https://fonts.googleapis.com/css2?family=Lora:ital,wght@0,400;0,500;0,600;1,400&family=IBM+Plex+Sans:wght@300;400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap');

  /* Default brand tokens — overridden at runtime when account branding is set */
  :root {
    --kpi-primary:          #1B6B3A;
    --kpi-primary2:         #22C55E;
    --kpi-accent:           #1B4332;
    --kpi-accent-hover:     #1B6B3A;
    --kpi-required-color:   #D97706;
    --kpi-category-color:   #9B9589;
    --kpi-progress-track:   #E5E3DD;
    --kpi-divider-color:    #E8E6E1;
  }

  .kpi-page {
    font-family: 'IBM Plex Sans', sans-serif;
    background: #F7F6F3;
    min-height: 100vh;
  }

  .kpi-page .display-font {
    font-family: 'Lora', Georgia, serif;
  }

  .kpi-page .mono-font {
    font-family: 'IBM Plex Mono', 'Courier New', monospace;
  }

  .kpi-progress-bar {
    height: 3px;
    background: var(--kpi-progress-track);
    border-radius: 2px;
    overflow: hidden;
  }

  .kpi-progress-fill {
    height: 100%;
    background: linear-gradient(90deg, var(--kpi-primary), var(--kpi-primary2));
    border-radius: 2px;
    transition: width 0.6s cubic-bezier(0.4, 0, 0.2, 1);
  }

  .kpi-card {
    background: #fff;
    border: 1px solid #E8E6E1;
    border-radius: 8px;
    transition: box-shadow 0.15s ease;
  }

  .kpi-card:focus-within {
    box-shadow: 0 0 0 2px color-mix(in srgb, var(--kpi-primary) 12%, transparent), 0 4px 16px rgba(0,0,0,0.06);
    border-color: color-mix(in srgb, var(--kpi-primary) 25%, transparent);
  }

  .kpi-card.is-submitted {
    border-color: #BBF7D0;
    background: #F0FDF4;
  }

  .kpi-card.is-locked {
    background: #FAFAF9;
    border-color: #E5E3DD;
    opacity: 0.85;
  }

  .threshold-pip {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    padding: 2px 7px;
    border-radius: 4px;
    font-size: 11px;
    font-weight: 500;
    font-family: 'IBM Plex Mono', monospace;
  }

  .kpi-save-btn {
    background: var(--kpi-accent);
    color: #fff;
    border: none;
    transition: background 0.15s, transform 0.1s;
  }

  .kpi-save-btn:hover:not(:disabled) {
    background: var(--kpi-accent-hover);
    transform: translateY(-1px);
  }

  .kpi-save-btn:active:not(:disabled) {
    transform: translateY(0);
  }

  .sticky-header {
    position: sticky;
    top: 0;
    z-index: 10;
    background: #fff;
    border-bottom: 1px solid #E8E6E1;
    backdrop-filter: blur(8px);
  }

  .fade-in {
    animation: fadeInUp 0.4s ease both;
  }

  .fade-in-delay-1 { animation-delay: 0.05s; }
  .fade-in-delay-2 { animation-delay: 0.10s; }
  .fade-in-delay-3 { animation-delay: 0.15s; }

  @keyframes fadeInUp {
    from { opacity: 0; transform: translateY(10px); }
    to   { opacity: 1; transform: translateY(0); }
  }

  .category-label {
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--kpi-category-color);
    font-family: 'IBM Plex Sans', sans-serif;
  }

  .kpi-required {
    color: var(--kpi-required-color);
  }

  .kpi-divider {
    background-color: var(--kpi-divider-color);
  }

  .required-dot::before {
    content: '•';
    color: #DC2626;
    margin-right: 4px;
    font-size: 14px;
    vertical-align: middle;
  }
`

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })
}

function periodStatusVariant(status: string): 'default' | 'secondary' | 'destructive' | 'outline' {
  if (status === 'Open') return 'default'
  if (status === 'Closed') return 'secondary'
  return 'outline'
}

function thresholdLabel(direction: string | null | undefined, green?: number | null, amber?: number | null, red?: number | null) {
  if (!green && !amber && !red) return null
  const arrow = direction === 'Higher' ? '↑' : direction === 'Lower' ? '↓' : '—'
  return { arrow, green, amber, red }
}

// ---------------------------------------------------------------------------
// KPI Row component
// ---------------------------------------------------------------------------

interface KpiRowProps {
  assignment: AssignmentWithSubmission
  index: number
  onSaved: () => void
}

// Parse pipe-delimited drop-down options into an array
function parseOptions(raw: string | null | undefined): string[] {
  if (!raw) return []
  return raw.split('||').map((o) => o.trim()).filter(Boolean)
}

function KpiRow({ assignment, index, onSaved }: KpiRowProps) {
  const isText     = assignment.dataType === 'Text'
  const isBoolean  = assignment.dataType === 'Boolean'
  const isDropDown = assignment.dataType === 'DropDown'
  const isNumeric  = !isText && !isBoolean && !isDropDown
  const isLocked   = !!assignment.lockState && assignment.lockState !== 'Unlocked'

  const dropDownOptions = parseOptions(assignment.dropDownOptionsRaw)

  const [value, setValue] = useState<string>(
    isText
      ? (assignment.submissionText ?? '')
      : isNumeric
        ? (assignment.submissionValue != null ? String(assignment.submissionValue) : '')
        : isDropDown
          ? (assignment.submissionText ?? '')
          : ''
  )
  // Boolean: null = unset, true/false = chosen
  const [boolValue, setBoolValue] = useState<boolean | null>(
    isBoolean ? (assignment.submissionBoolean ?? null) : null
  )
  // DropDown multi-select: array of selected values
  const [selectedOptions, setSelectedOptions] = useState<string[]>(() => {
    if (!isDropDown) return []
    if (!assignment.submissionText) return []
    // stored as comma-separated for multi; single value for single-select
    return assignment.submissionText.split(',').map((s) => s.trim()).filter(Boolean)
  })
  const [notes, setNotes] = useState<string>(assignment.submissionNotes ?? '')
  const [dirty, setDirty] = useState(false)

  const handleChange = useCallback((v: string) => {
    setValue(v)
    setDirty(true)
  }, [])

  const handleNotesChange = useCallback((v: string) => {
    setNotes(v)
    setDirty(true)
  }, [])

  const handleBoolChange = useCallback((v: boolean) => {
    setBoolValue(v)
    setDirty(true)
  }, [])

  const toggleOption = useCallback((opt: string) => {
    setSelectedOptions((prev) => {
      if (assignment.allowMultiValue) {
        return prev.includes(opt) ? prev.filter((o) => o !== opt) : [...prev, opt]
      }
      // single-select: replace
      return prev.includes(opt) ? [] : [opt]
    })
    setDirty(true)
  }, [assignment.allowMultiValue])

  const mutation = useMutation({
    mutationFn: () => {
      const submissionText = isDropDown
        ? (selectedOptions.length > 0 ? selectedOptions.join(',') : undefined)
        : isText
          ? (value || undefined)
          : undefined

      return api.kpi.submissions.submit({
        assignmentExternalId: assignment.externalId,
        submissionValue:      isNumeric ? (value ? Number(value) : undefined) : undefined,
        submissionText,
        submissionBoolean:    isBoolean ? (boolValue ?? undefined) : undefined,
        submissionNotes:      notes || undefined,
        lockOnSubmit:         true,
        bypassLock:           false,
      })
    },
    onSuccess: () => {
      toast.success(`${assignment.effectiveKpiName} — saved`, {
        description: 'Submission recorded.',
        duration: 3000,
      })
      if (typeof window !== 'undefined') {
        const refreshMarker = String(Date.now())
        window.localStorage.setItem(KPI_MONITORING_REFRESH_EVENT, refreshMarker)
        window.dispatchEvent(new CustomEvent(KPI_MONITORING_REFRESH_EVENT, { detail: refreshMarker }))
      }
      setDirty(false)
      onSaved()
    },
    onError: (err: Error) => {
      toast.error('Could not save', { description: err.message })
    },
  })

  const thresholds = thresholdLabel(
    assignment.effectiveThresholdDirection,
    assignment.thresholdGreen,
    assignment.thresholdAmber,
    assignment.thresholdRed
  )

  const cardClass = [
    'kpi-card p-5 fade-in',
    isLocked ? 'is-locked' : '',
    assignment.isSubmitted && !isLocked ? 'is-submitted' : '',
  ].filter(Boolean).join(' ')

  const animationDelay: React.CSSProperties = { animationDelay: `${index * 0.04}s` }

  return (
    <div className={cardClass} style={animationDelay}>
      {/* Row header */}
      <div className="flex items-start justify-between gap-4 mb-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span
              className={`text-sm font-semibold text-gray-800 leading-snug ${assignment.isRequired ? 'required-dot' : ''}`}
            >
              {assignment.effectiveKpiName}
            </span>
            <span className="mono-font text-[11px] text-gray-400">{assignment.kpiCode}</span>
          </div>
          {assignment.effectiveKpiDescription && (
            <p className="text-xs text-gray-500 mt-0.5 leading-relaxed">
              {assignment.effectiveKpiDescription}
            </p>
          )}
        </div>

        {/* Status badge */}
        <div className="shrink-0">
          {isLocked ? (
            <span className="inline-flex items-center gap-1 text-xs text-gray-400 font-medium">
              <Lock className="w-3 h-3" /> Locked
            </span>
          ) : assignment.isSubmitted ? (
            <span className="inline-flex items-center gap-1 text-xs text-green-600 font-semibold">
              <CheckCircle2 className="w-3.5 h-3.5" /> Submitted
            </span>
          ) : (
            <span className="kpi-required text-xs font-medium">
              {assignment.isRequired ? 'Required' : 'Optional'}
            </span>
          )}
        </div>
      </div>

      {/* Threshold guidance */}
      {thresholds && (
        <div className="flex flex-wrap items-center gap-1.5 mb-3">
          <span className="text-[11px] text-gray-400 mr-0.5">
            {thresholds.arrow === '↑' ? (
              <TrendingUp className="w-3 h-3 inline" />
            ) : (
              <TrendingDown className="w-3 h-3 inline" />
            )}{' '}
            Target
          </span>
          {thresholds.green != null && (
            <span className="threshold-pip" style={{ background: '#D1FAE5', color: '#065F46' }}>
              ● {thresholds.green}
            </span>
          )}
          {thresholds.amber != null && (
            <span className="threshold-pip" style={{ background: '#FEF3C7', color: '#92400E' }}>
              ● {thresholds.amber}
            </span>
          )}
          {thresholds.red != null && (
            <span className="threshold-pip" style={{ background: '#FEE2E2', color: '#991B1B' }}>
              ● {thresholds.red}
            </span>
          )}
          {assignment.targetValue != null && (
            <span className="threshold-pip" style={{ background: '#E0E7FF', color: '#3730A3' }}>
              ◎ {assignment.targetValue}
            </span>
          )}
        </div>
      )}

      {/* Submitter guidance */}
      {assignment.submitterGuidance && (
        <p className="text-xs italic text-gray-400 border-l-2 border-gray-200 pl-2 mb-3 leading-relaxed">
          {assignment.submitterGuidance}
        </p>
      )}

      {/* Input fields */}
      {isLocked ? (
        <div className="text-sm text-gray-500 bg-gray-50 rounded px-3 py-2 mono-font">
          {isBoolean
            ? (assignment.submissionBoolean === true ? 'Yes' : assignment.submissionBoolean === false ? 'No' : '—')
            : isDropDown
              ? (assignment.submissionText ?? '—')
              : isText
                ? (assignment.submissionText ?? '—')
                : (assignment.submissionValue != null ? String(assignment.submissionValue) : '—')}
          {assignment.submissionNotes && (
            <p className="text-xs text-gray-400 mt-1 not-italic font-sans">
              {assignment.submissionNotes}
            </p>
          )}
        </div>
      ) : (
        <div className="space-y-2">
          {/* Boolean input */}
          {isBoolean ? (
            <div className="flex gap-2 items-center">
              <div className="flex gap-1.5 flex-1">
                <button
                  type="button"
                  onClick={() => handleBoolChange(true)}
                  disabled={mutation.isPending}
                  className={[
                    'flex-1 rounded-md border px-4 py-1.5 text-sm font-medium transition-all',
                    boolValue === true
                      ? 'border-green-600 bg-green-50 text-green-700'
                      : 'border-gray-200 bg-white text-gray-600 hover:border-gray-300',
                  ].join(' ')}
                >
                  Yes
                </button>
                <button
                  type="button"
                  onClick={() => handleBoolChange(false)}
                  disabled={mutation.isPending}
                  className={[
                    'flex-1 rounded-md border px-4 py-1.5 text-sm font-medium transition-all',
                    boolValue === false
                      ? 'border-red-400 bg-red-50 text-red-700'
                      : 'border-gray-200 bg-white text-gray-600 hover:border-gray-300',
                  ].join(' ')}
                >
                  No
                </button>
              </div>
              <Button
                className="kpi-save-btn shrink-0 h-9 px-4 text-sm font-medium"
                onClick={() => mutation.mutate()}
                disabled={mutation.isPending || boolValue === null || (!dirty && assignment.isSubmitted)}
              >
                {mutation.isPending ? (
                  <span className="flex items-center gap-1.5">
                    <span className="w-3 h-3 rounded-full border-2 border-white/40 border-t-white animate-spin" />
                    Saving
                  </span>
                ) : (
                  <span className="flex items-center gap-1.5">
                    <Send className="w-3.5 h-3.5" />
                    Save
                  </span>
                )}
              </Button>
            </div>
          ) : isDropDown ? (
            /* DropDown input */
            <div className="space-y-2">
              <div className="flex flex-wrap gap-1.5">
                {dropDownOptions.map((opt) => {
                  const selected = selectedOptions.includes(opt)
                  return (
                    <button
                      key={opt}
                      type="button"
                      onClick={() => toggleOption(opt)}
                      disabled={mutation.isPending}
                      className={[
                        'rounded-md border px-3 py-1 text-sm font-medium transition-all',
                        selected
                          ? 'border-[#1B6B3A] bg-[#1B6B3A]/10 text-[#1B4332]'
                          : 'border-gray-200 bg-white text-gray-600 hover:border-gray-300',
                      ].join(' ')}
                    >
                      {opt}
                    </button>
                  )
                })}
                {dropDownOptions.length === 0 && (
                  <span className="text-xs text-gray-400 italic">No options configured.</span>
                )}
              </div>
              {assignment.allowMultiValue && (
                <p className="text-[11px] text-gray-400">Multiple selections allowed.</p>
              )}
              <div className="flex gap-2">
                <Input
                  value={notes}
                  onChange={(e) => handleNotesChange(e.target.value)}
                  placeholder="Notes (optional)…"
                  className="text-xs text-gray-500 flex-1"
                  disabled={mutation.isPending}
                />
                <Button
                  className="kpi-save-btn shrink-0 h-9 px-4 text-sm font-medium"
                  onClick={() => mutation.mutate()}
                  disabled={mutation.isPending || selectedOptions.length === 0 || (!dirty && assignment.isSubmitted)}
                >
                  {mutation.isPending ? (
                    <span className="flex items-center gap-1.5">
                      <span className="w-3 h-3 rounded-full border-2 border-white/40 border-t-white animate-spin" />
                      Saving
                    </span>
                  ) : (
                    <span className="flex items-center gap-1.5">
                      <Send className="w-3.5 h-3.5" />
                      Save
                    </span>
                  )}
                </Button>
              </div>
            </div>
          ) : (
            /* Numeric or Text input */
            <div className="flex gap-2">
              {isText ? (
                <Textarea
                  value={value}
                  onChange={(e) => handleChange(e.target.value)}
                  placeholder="Enter value…"
                  className="text-sm resize-none h-16 flex-1"
                  disabled={mutation.isPending}
                />
              ) : (
                <Input
                  type="number"
                  value={value}
                  onChange={(e) => handleChange(e.target.value)}
                  placeholder="Enter value…"
                  className="text-sm flex-1 mono-font"
                  disabled={mutation.isPending}
                />
              )}
              <Button
                className="kpi-save-btn shrink-0 h-9 px-4 text-sm font-medium"
                onClick={() => mutation.mutate()}
                disabled={mutation.isPending || !dirty && assignment.isSubmitted}
              >
                {mutation.isPending ? (
                  <span className="flex items-center gap-1.5">
                    <span className="w-3 h-3 rounded-full border-2 border-white/40 border-t-white animate-spin" />
                    Saving
                  </span>
                ) : (
                  <span className="flex items-center gap-1.5">
                    <Send className="w-3.5 h-3.5" />
                    Save
                  </span>
                )}
              </Button>
            </div>
          )}

          {/* Notes input — only shown for non-boolean, non-dropdown (those have it inline) */}
          {!isBoolean && !isDropDown && (
            <Input
              value={notes}
              onChange={(e) => handleNotesChange(e.target.value)}
              placeholder="Notes (optional)…"
              className="text-xs text-gray-500"
              disabled={mutation.isPending}
            />
          )}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main content (needs Suspense for useSearchParams)
// ---------------------------------------------------------------------------

function KpiCompleteContent() {
  const searchParams = useSearchParams()
  const token = searchParams.get('token') ?? ''
  const queryClient = useQueryClient()

  const { data: ctx, isLoading, isError, error } = useQuery<SubmissionTokenContext>({
    queryKey: ['submission-token', token],
    queryFn:  () => api.kpi.submissionTokens.getContext(token),
    enabled:  !!token,
    staleTime: 60_000,
  })

  const refresh = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['submission-token', token] })
  }, [queryClient, token])

  // Derived stats
  const requiredAssignments  = ctx?.assignments.filter((a) => a.isRequired) ?? []
  const submittedRequired    = requiredAssignments.filter((a) => a.isSubmitted).length
  const totalRequired        = requiredAssignments.length
  const progressPct          = totalRequired > 0 ? Math.round((submittedRequired / totalRequired) * 100) : 0
  const allDone              = totalRequired > 0 && submittedRequired === totalRequired

  // Group by category
  const grouped = ctx
    ? ctx.assignments.reduce<Record<string, AssignmentWithSubmission[]>>((acc, a) => {
        const cat = a.category ?? 'General'
        if (!acc[cat]) acc[cat] = []
        acc[cat].push(a)
        return acc
      }, {})
    : {}

  // No token
  if (!token) {
    return (
      <div className="kpi-page flex items-center justify-center min-h-screen p-6">
        <div className="max-w-md w-full text-center space-y-4">
          <AlertCircle className="w-12 h-12 text-amber-500 mx-auto" />
          <h1 className="display-font text-2xl text-gray-800">No link token found</h1>
          <p className="text-sm text-gray-500">
            Please use the link provided in your email. It should look like
            <br />
            <code className="mono-font text-xs bg-gray-100 px-2 py-0.5 rounded">/kpi/complete?token=…</code>
          </p>
        </div>
      </div>
    )
  }

  if (isLoading) {
    return (
      <div className="kpi-page flex items-center justify-center min-h-screen">
        <div className="text-center space-y-3">
          <div className="w-8 h-8 rounded-full border-2 border-gray-200 border-t-green-700 animate-spin mx-auto" />
          <p className="text-sm text-gray-400">Loading your KPIs…</p>
        </div>
      </div>
    )
  }

  if (isError || !ctx) {
    return (
      <div className="kpi-page flex items-center justify-center min-h-screen p-6">
        <div className="max-w-md w-full text-center space-y-4">
          <AlertCircle className="w-12 h-12 text-red-400 mx-auto" />
          <h1 className="display-font text-2xl text-gray-800">Link expired or invalid</h1>
          <p className="text-sm text-gray-500">
            {(error as Error)?.message ?? 'This link is no longer valid.'}
          </p>
          <p className="text-xs text-gray-400">
            Please contact your account manager for a new link.
          </p>
        </div>
      </div>
    )
  }

  // Client-side text color computation (WCAG contrast) — used so the header
  // is always readable regardless of whether the backend has been restarted.
  function resolveTextColor(hex: string): string {
    if (!/^#[0-9A-Fa-f]{6}$/.test(hex)) return '#000000'
    const r = parseInt(hex.slice(1, 3), 16) / 255
    const g = parseInt(hex.slice(3, 5), 16) / 255
    const b = parseInt(hex.slice(5, 7), 16) / 255
    const lin = (c: number) => c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    const L = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    return (1.05 / (L + 0.05)) >= (L + 0.05) / 0.05 ? '#FFFFFF' : '#000000'
  }

  const branding = ctx.branding
  const branded = !!branding?.primaryColor

  // Compute text color client-side — this is authoritative for the header
  const computedTextOnPrimary = branded ? resolveTextColor(branding!.primaryColor!) : '#111827'

  // Derive a readable accent for required labels from the accent or primary color
  const accentColor = branding?.accentColor ?? branding?.primaryColor

  const brandingOverride = branded
    ? `:root {
        --kpi-primary:        ${branding!.primaryColor};
        --kpi-primary2:       ${branding!.primaryColor2 ?? branding!.primaryColor};
        --kpi-accent:         ${accentColor};
        --kpi-accent-hover:   ${branding!.primaryColor2 ?? branding!.primaryColor};
        --kpi-required-color: ${accentColor};
        --kpi-category-color: ${branding!.secondaryColor ?? branding!.primaryColor};
        --kpi-progress-track: ${branding!.secondaryColor ?? branding!.primaryColor};
        --kpi-divider-color:  ${branding!.secondaryColor ?? branding!.primaryColor};
      }`
    : ''

  // Inline styles for the header
  const headerStyle = branded
    ? { background: branding!.primaryColor!, borderBottomColor: 'transparent' }
    : {}
  const titleStyle = branded ? { color: computedTextOnPrimary }                              : {}
  const metaStyle  = branded ? { color: computedTextOnPrimary, opacity: 0.8 as number }      : {}
  const doneStyle  = branded ? { color: computedTextOnPrimary }                              : {}
  // Progress bar track in the branded header — semi-transparent white
  const trackStyle = branded ? { background: `${computedTextOnPrimary}22` }                 : {}

  return (
    <div className="kpi-page">
      {brandingOverride && <style dangerouslySetInnerHTML={{ __html: brandingOverride }} />}
      {/* Sticky header */}
      <header className="sticky-header" style={headerStyle}>
        <div className="max-w-2xl mx-auto px-5 py-4">
          {/* Site + period info */}
          <div className="flex items-start justify-between gap-3 mb-3">
            <div className="min-w-0">
              {/* Logo inline with site name */}
              <div className="flex items-center gap-3 fade-in">
                {branding?.logoDataUrl && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={branding.logoDataUrl}
                    alt={ctx.accountName}
                    className="h-8 max-w-[100px] object-contain shrink-0"
                    onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
                  />
                )}
                <h1
                  className="display-font text-xl leading-tight"
                  style={branded ? titleStyle : { color: '#111827' }}
                >
                  {ctx.siteName}
                </h1>
              </div>
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1 fade-in fade-in-delay-1">
                <span className="inline-flex items-center gap-1 text-xs" style={branded ? metaStyle : { color: '#9CA3AF' }}>
                  <Building2 className="w-3 h-3" /> {ctx.accountName}
                </span>
                <span className="inline-flex items-center gap-1 text-xs" style={branded ? metaStyle : { color: '#9CA3AF' }}>
                  <Calendar className="w-3 h-3" /> {ctx.periodLabel}
                </span>
                <span className="inline-flex items-center gap-1 text-xs" style={branded ? metaStyle : { color: '#9CA3AF' }}>
                  <Clock className="w-3 h-3" /> Until {formatDate(ctx.periodCloseDate)}
                </span>
                {ctx.assignmentGroupName && (
                  <span
                    className="inline-flex items-center gap-1 text-xs font-semibold px-2 py-0.5 rounded-full"
                    style={branded
                      ? { background: `${computedTextOnPrimary}22`, color: computedTextOnPrimary }
                      : { background: '#EFF6FF', color: '#1D4ED8' }}
                  >
                    <Layers className="w-3 h-3" /> {ctx.assignmentGroupName}
                  </span>
                )}
              </div>
            </div>

            <div className="shrink-0 fade-in fade-in-delay-2">
              <Badge
                variant={periodStatusVariant(ctx.periodStatus)}
                className={ctx.periodStatus === 'Open' ? 'bg-green-100 text-green-800 border-green-200' : ''}
              >
                {ctx.periodStatus}
              </Badge>
            </div>
          </div>

          {/* Progress bar */}
          <div className="fade-in fade-in-delay-3">
            <div className="flex items-center justify-between mb-1">
              <span className="text-xs font-medium" style={branded ? metaStyle : { color: '#6B7280' }}>
                {allDone ? (
                  <span className="flex items-center gap-1" style={branded ? doneStyle : { color: '#15803D' }}>
                    <CheckCircle2 className="w-3.5 h-3.5" />
                    All required KPIs submitted
                  </span>
                ) : (
                  `${submittedRequired} of ${totalRequired} required KPIs submitted`
                )}
              </span>
              <span className="mono-font text-xs font-medium" style={branded ? metaStyle : { color: '#6B7280' }}>{progressPct}%</span>
            </div>
            <div className="kpi-progress-bar" style={branded ? trackStyle : {}}>
              <div className="kpi-progress-fill" style={{ width: `${progressPct}%` }} />
            </div>
          </div>
        </div>
      </header>

      {/* KPI list */}
      <main className="max-w-2xl mx-auto px-5 py-6 space-y-6 pb-16">
        {Object.entries(grouped).map(([category, items]) => (
          <section key={category}>
            <div className="flex items-center gap-3 mb-3">
              <span className="category-label">{category}</span>
              <div className="kpi-divider flex-1 h-px" />
              <span className="text-[11px] text-gray-400 mono-font">
                {items.filter((i) => i.isSubmitted).length}/{items.length}
              </span>
            </div>

            <div className="space-y-2.5">
              {items.map((assignment, i) => (
                <KpiRow
                  key={assignment.externalId}
                  assignment={assignment}
                  index={i}
                  onSaved={refresh}
                />
              ))}
            </div>
          </section>
        ))}

        {/* Footer note */}
        <div className="text-center pt-4">
          <p className="text-xs text-gray-400">
            Submissions are automatically locked when saved.
            <br />
            Contact your account manager to make changes after locking.
          </p>
        </div>
      </main>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Page export — wraps content in Suspense (required for useSearchParams)
// ---------------------------------------------------------------------------

export default function KpiCompletePage() {
  return (
    <>
      <style dangerouslySetInnerHTML={{ __html: PAGE_STYLES }} />
      <Suspense
        fallback={
          <div className="kpi-page flex items-center justify-center min-h-screen">
            <div className="w-8 h-8 rounded-full border-2 border-gray-200 border-t-green-700 animate-spin" />
          </div>
        }
      >
        <KpiCompleteContent />
      </Suspense>
    </>
  )
}
