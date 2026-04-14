'use client'

import { useEffect, useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Palette, Image as ImageIcon, RotateCcw, Save } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { PermissionGate } from '@/components/shared/permission-gate'
import { api } from '@/lib/api'
import { PERMISSIONS } from '@/types/api'
import type { AccountBranding, UpdateAccountBrandingInput } from '@/types/api'
import { cn } from '@/lib/utils'

// ---------------------------------------------------------------------------
// Defaults used when no branding is set
// ---------------------------------------------------------------------------

const DEFAULT_PRIMARY    = '#3B82F6'
const DEFAULT_SECONDARY  = '#64748B'
const DEFAULT_ACCENT     = '#3B82F6'
const DEFAULT_TEXT_DARK  = '#000000'
const DEFAULT_TEXT_LIGHT = '#FFFFFF'

// ---------------------------------------------------------------------------
// Simple luminance check used for the live preview (mirrors backend logic)
// ---------------------------------------------------------------------------

function computeTextColor(hex: string): string {
  const r = parseInt(hex.slice(1, 3), 16) / 255
  const g = parseInt(hex.slice(3, 5), 16) / 255
  const b = parseInt(hex.slice(5, 7), 16) / 255

  const lin = (c: number) =>
    c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)

  const L = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)

  // WCAG contrast: white text on this bg vs black text on this bg
  const contrastWhiteText = 1.05 / (L + 0.05)
  const contrastBlackText = (L + 0.05) / 0.05
  return contrastWhiteText >= contrastBlackText ? DEFAULT_TEXT_LIGHT : DEFAULT_TEXT_DARK
}

function isValidHex(value: string): boolean {
  return /^#[0-9A-Fa-f]{6}$/.test(value)
}

// ---------------------------------------------------------------------------
// Live preview card
// ---------------------------------------------------------------------------

interface PreviewProps {
  accountName: string
  form: BrandingFormState
}

function BrandingPreview({ accountName, form }: PreviewProps) {
  const primary   = isValidHex(form.primaryColor)   ? form.primaryColor   : DEFAULT_PRIMARY
  const secondary = isValidHex(form.secondaryColor) ? form.secondaryColor : DEFAULT_SECONDARY
  const accent    = isValidHex(form.accentColor)    ? form.accentColor    : DEFAULT_ACCENT

  const textOnPrimary   = isValidHex(form.textOnPrimaryOverride)
    ? form.textOnPrimaryOverride
    : computeTextColor(primary)
  const textOnSecondary = isValidHex(form.textOnSecondaryOverride)
    ? form.textOnSecondaryOverride
    : computeTextColor(secondary)

  const logoDataUrl = form.logoDataUrl.trim() || null

  return (
    <div className="rounded-xl overflow-hidden border shadow-sm select-none">
      {/* Header band */}
      <div
        className="px-5 py-4 flex items-center justify-between gap-3"
        style={{ background: primary, color: textOnPrimary }}
      >
        <div className="flex items-center gap-3 min-w-0">
          {logoDataUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={logoDataUrl}
              alt="Logo preview"
              className="h-8 w-auto max-w-[120px] object-contain shrink-0"
              onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
            />
          ) : null}
          <span className="font-semibold text-sm truncate">{accountName}</span>
        </div>
        <div
          className="px-3 py-1 rounded-md text-xs font-medium shrink-0"
          style={{ background: accent, color: computeTextColor(accent) }}
        >
          Sample Button
        </div>
      </div>

      {/* Secondary band */}
      <div
        className="px-5 py-3"
        style={{ background: secondary, color: textOnSecondary }}
      >
        <p className="text-xs">Secondary surface — {secondary}</p>
      </div>

      {/* Body */}
      <div className="px-5 py-4 bg-white dark:bg-card">
        <div className="flex gap-2 flex-wrap">
          {[
            { label: 'Primary',   color: primary   },
            { label: 'Secondary', color: secondary },
            { label: 'Accent',    color: accent    },
          ].map(({ label, color }) => (
            <div key={label} className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <span
                className="inline-block h-3 w-3 rounded-full border"
                style={{ background: color }}
              />
              {label}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Color field: color picker + hex text input in sync
// ---------------------------------------------------------------------------

interface ColorFieldProps {
  id: string
  label: string
  value: string
  onChange: (v: string) => void
  optional?: boolean
  placeholder?: string
}

function ColorField({ id, label, value, onChange, optional, placeholder }: ColorFieldProps) {
  const displayColor = isValidHex(value) ? value : '#FFFFFF'

  return (
    <div className="space-y-1.5">
      <Label htmlFor={id} className="text-sm font-medium">
        {label}
        {optional && <span className="ml-1 text-xs text-muted-foreground font-normal">(optional)</span>}
      </Label>
      <div className="flex items-center gap-2">
        <div className="relative">
          <input
            type="color"
            value={displayColor}
            onChange={(e) => onChange(e.target.value.toUpperCase())}
            className="h-9 w-9 cursor-pointer rounded-md border border-input p-0.5"
            title={`Pick ${label}`}
          />
        </div>
        <Input
          id={id}
          value={value}
          onChange={(e) => onChange(e.target.value.toUpperCase())}
          placeholder={placeholder ?? '#000000'}
          className={cn(
            'font-mono text-sm h-9 flex-1',
            value && !isValidHex(value) && 'border-destructive focus-visible:ring-destructive'
          )}
          maxLength={7}
        />
      </div>
      {value && !isValidHex(value) && (
        <p className="text-xs text-destructive">Enter a valid hex color (e.g. #1B4F72)</p>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Form state
// ---------------------------------------------------------------------------

interface BrandingFormState {
  primaryColor: string
  primaryColor2: string
  secondaryColor: string
  secondaryColor2: string
  accentColor: string
  textOnPrimaryOverride: string
  textOnSecondaryOverride: string
  logoDataUrl: string
}

function brandingToForm(b: AccountBranding | null | undefined): BrandingFormState {
  return {
    primaryColor:           b?.primaryColor            ?? '',
    primaryColor2:          b?.primaryColor2           ?? '',
    secondaryColor:         b?.secondaryColor          ?? '',
    secondaryColor2:        b?.secondaryColor2         ?? '',
    accentColor:            b?.accentColor             ?? '',
    textOnPrimaryOverride:  '',  // overrides not returned by resolved DTO; start blank
    textOnSecondaryOverride: '',
    logoDataUrl:            b?.logoDataUrl             ?? '',
  }
}

const EMPTY_FORM: BrandingFormState = {
  primaryColor: '', primaryColor2: '', secondaryColor: '', secondaryColor2: '',
  accentColor: '', textOnPrimaryOverride: '', textOnSecondaryOverride: '', logoDataUrl: '',
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

interface AccountBrandingTabProps {
  accountId: number
  accountName: string
}

export function AccountBrandingTab({ accountId, accountName }: AccountBrandingTabProps) {
  const queryClient = useQueryClient()

  const { data: branding, isLoading } = useQuery({
    queryKey: ['account-branding', accountId],
    queryFn: () => api.accounts.getBranding(accountId),
  })

  const [form, setForm] = useState<BrandingFormState>(EMPTY_FORM)
  const [initialized, setInitialized] = useState(false)

  // Initialize form once branding data arrives
  useEffect(() => {
    if (!isLoading && !initialized) {
      setForm(brandingToForm(branding))
      setInitialized(true)
    }
  }, [isLoading, branding, initialized])

  const updateField = (field: keyof BrandingFormState) => (value: string) =>
    setForm((prev) => ({ ...prev, [field]: value }))

  const saveMutation = useMutation({
    mutationFn: (data: UpdateAccountBrandingInput) =>
      api.accounts.updateBranding(accountId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['account-branding', accountId] })
      toast.success('Branding saved')
    },
    onError: () => {
      toast.error('Failed to save branding')
    },
  })

  function buildPayload(): UpdateAccountBrandingInput {
    const norm = (v: string) => (isValidHex(v) ? v : null)
    return {
      primaryColor:            norm(form.primaryColor),
      primaryColor2:           norm(form.primaryColor2),
      secondaryColor:          norm(form.secondaryColor),
      secondaryColor2:         norm(form.secondaryColor2),
      accentColor:             norm(form.accentColor),
      textOnPrimaryOverride:   norm(form.textOnPrimaryOverride),
      textOnSecondaryOverride: norm(form.textOnSecondaryOverride),
      logoDataUrl:             form.logoDataUrl.trim() || null,
    }
  }

  function handleSave() {
    saveMutation.mutate(buildPayload())
  }

  function handleClear() {
    setForm(EMPTY_FORM)
    saveMutation.mutate({
      primaryColor: null, primaryColor2: null, secondaryColor: null, secondaryColor2: null,
      accentColor: null, textOnPrimaryOverride: null, textOnSecondaryOverride: null, logoDataUrl: null,
    })
  }

  if (isLoading) {
    return (
      <div className="space-y-3">
        {[1, 2, 3].map((i) => (
          <div key={i} className="h-10 animate-pulse rounded-lg bg-muted" />
        ))}
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Live preview */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium flex items-center gap-2">
            <Palette className="h-4 w-4 text-muted-foreground" />
            Preview
          </CardTitle>
        </CardHeader>
        <CardContent>
          <BrandingPreview accountName={accountName} form={form} />
          {!branding && (
            <p className="mt-3 text-xs text-muted-foreground">
              No branding configured. Default app styling will be used until colors are saved.
            </p>
          )}
        </CardContent>
      </Card>

      {/* Edit form — gated to admin */}
      <PermissionGate permission={PERMISSIONS.ACCOUNTS_MANAGE}>
        <div className="grid gap-6 lg:grid-cols-2">
          {/* Primary colors */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">Primary Colors</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <ColorField
                id="primaryColor"
                label="Primary Color"
                value={form.primaryColor}
                onChange={updateField('primaryColor')}
                placeholder="#1B4F72"
              />
              <ColorField
                id="primaryColor2"
                label="Primary Color 2"
                value={form.primaryColor2}
                onChange={updateField('primaryColor2')}
                optional
                placeholder="#2471A3"
              />
              <ColorField
                id="textOnPrimaryOverride"
                label="Text on Primary (override)"
                value={form.textOnPrimaryOverride}
                onChange={updateField('textOnPrimaryOverride')}
                optional
                placeholder="Auto-computed"
              />
            </CardContent>
          </Card>

          {/* Secondary colors */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">Secondary Colors</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <ColorField
                id="secondaryColor"
                label="Secondary Color"
                value={form.secondaryColor}
                onChange={updateField('secondaryColor')}
                optional
                placeholder="#2E86AB"
              />
              <ColorField
                id="secondaryColor2"
                label="Secondary Color 2"
                value={form.secondaryColor2}
                onChange={updateField('secondaryColor2')}
                optional
                placeholder="#5DADE2"
              />
              <ColorField
                id="textOnSecondaryOverride"
                label="Text on Secondary (override)"
                value={form.textOnSecondaryOverride}
                onChange={updateField('textOnSecondaryOverride')}
                optional
                placeholder="Auto-computed"
              />
            </CardContent>
          </Card>

          {/* Accent */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">Accent Color</CardTitle>
            </CardHeader>
            <CardContent>
              <ColorField
                id="accentColor"
                label="Accent Color"
                value={form.accentColor}
                onChange={updateField('accentColor')}
                optional
                placeholder="#F39C12"
              />
              <p className="mt-2 text-xs text-muted-foreground">
                Used for buttons, highlights, and interactive elements.
              </p>
            </CardContent>
          </Card>

          {/* Logo */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium flex items-center gap-2">
                <ImageIcon className="h-4 w-4 text-muted-foreground" />
                Logo
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="space-y-1.5">
                <Label htmlFor="logoDataUrl" className="text-sm font-medium">
                  Logo URL
                  <span className="ml-1 text-xs text-muted-foreground font-normal">(optional)</span>
                </Label>
                <textarea
                  id="logoDataUrl"
                  value={form.logoDataUrl}
                  onChange={(e) => updateField('logoDataUrl')(e.target.value)}
                  placeholder="https://example.com/logo.png  or  data:image/png;base64,..."
                  rows={3}
                  className="w-full rounded-md border border-input bg-background px-3 py-2 text-xs font-mono text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring resize-none"
                />
              </div>
              {(form.logoDataUrl.startsWith('data:') || form.logoDataUrl.startsWith('https://') || form.logoDataUrl.startsWith('http://')) && (
                <div className="flex items-center gap-2">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={form.logoDataUrl}
                    alt="Logo preview"
                    className="h-10 max-w-[160px] object-contain rounded border bg-white p-1"
                    onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
                  />
                  <span className="text-xs text-muted-foreground">Logo preview</span>
                </div>
              )}
              <p className="text-xs text-muted-foreground">
                Accepts an <code className="font-mono">https://</code> URL to an image, or a base64 data URL (<code className="font-mono">data:image/png;base64,…</code>). Leave blank to show account name text instead.
              </p>
            </CardContent>
          </Card>
        </div>

        {/* Action bar */}
        <div className="flex items-center justify-between gap-3 pt-2">
          <Button
            variant="outline"
            size="sm"
            onClick={handleClear}
            disabled={saveMutation.isPending}
            className="text-muted-foreground"
          >
            <RotateCcw className="mr-1.5 h-3.5 w-3.5" />
            Clear Branding
          </Button>
          <Button
            size="sm"
            onClick={handleSave}
            disabled={saveMutation.isPending}
          >
            <Save className="mr-1.5 h-3.5 w-3.5" />
            {saveMutation.isPending ? 'Saving…' : 'Save Branding'}
          </Button>
        </div>
      </PermissionGate>
    </div>
  )
}
