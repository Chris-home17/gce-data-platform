'use client'

import { useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CheckCircle2, Download, Upload, XCircle } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import { Badge } from '@/components/ui/badge'
import { OrgUnitTypeBadge } from '@/components/shared/org-unit-type-badge'
import { api } from '@/lib/api'
import type { BulkSharedGeoUnitResult, SharedGeoUnit } from '@/types/api'
import {
  parseCsv,
  parseIndented,
  validateRows,
  TEMPLATE_CSV,
  type ValidatedRow,
} from './import-parser'

type Step = 'input' | 'preview' | 'results'


export function ImportSharedGeoDialog() {
  const [open, setOpen] = useState(false)
  const [step, setStep] = useState<Step>('input')
  const [inputTab, setInputTab] = useState('paste-csv')
  const [csvText, setCsvText] = useState('')
  const [indentedText, setIndentedText] = useState('')
  const [validatedRows, setValidatedRows] = useState<ValidatedRow[]>([])
  const [importResults, setImportResults] = useState<BulkSharedGeoUnitResult[]>([])
  const fileInputRef = useRef<HTMLInputElement>(null)
  const queryClient = useQueryClient()

  const { data: sharedGeoUnits } = useQuery({
    queryKey: ['shared-geo-units'],
    queryFn: () => api.sharedGeoUnits.list(),
    enabled: open,
  })

  const importMutation = useMutation({
    mutationFn: () =>
      api.sharedGeoUnits.bulkCreate({
        rows: validatedRows.map((vr) => ({
          geoUnitType: vr.row.geoUnitType,
          geoUnitCode: vr.row.geoUnitCode.trim().toUpperCase(),
          geoUnitName: vr.row.geoUnitName.trim(),
          countryCode:
            vr.row.geoUnitType === 'Country' ? vr.row.countryCode?.trim().toUpperCase() : undefined,
        })),
      }),
    onSuccess: (response) => {
      setImportResults(response.results)
      setStep('results')
      queryClient.invalidateQueries({ queryKey: ['shared-geo-units'] })
      queryClient.invalidateQueries({ queryKey: ['org-units'] })
      const successCount = response.results.filter((r) => r.success).length
      const failCount = response.results.length - successCount
      if (failCount === 0) {
        toast.success(`${successCount} shared geography item${successCount !== 1 ? 's' : ''} imported.`)
      } else {
        toast.warning(`${successCount} imported, ${failCount} failed. See details below.`)
      }
    },
    onError: (err: Error) => {
      toast.error('Import failed', { description: err.message })
    },
  })

  function handleOpen() {
    setOpen(true)
    setStep('input')
    setInputTab('paste-csv')
    setCsvText('')
    setIndentedText('')
    setValidatedRows([])
    setImportResults([])
  }

  function handleClose() {
    if (importMutation.isPending) return
    setOpen(false)
  }

  function handleFileUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = (ev) => {
      setCsvText(ev.target?.result as string)
    }
    reader.readAsText(file)
    e.target.value = ''
  }

  function handlePreview() {
    const rawText = inputTab === 'indented' ? indentedText : csvText
    const rows = inputTab === 'indented' ? parseIndented(rawText) : parseCsv(rawText)
    const validated = validateRows(rows, sharedGeoUnits?.items ?? [])
    setValidatedRows(validated)
    setStep('preview')
  }

  function downloadTemplate() {
    const blob = new Blob([TEMPLATE_CSV], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'shared-geography-template.csv'
    a.click()
    URL.revokeObjectURL(url)
  }

  const hasErrors = validatedRows.some((r) => r.status === 'error')
  const errorCount = validatedRows.filter((r) => r.status === 'error').length
  const warningCount = validatedRows.filter((r) => r.status === 'warning').length

  return (
    <>
      <Button variant="outline" size="sm" onClick={handleOpen}>
        <Upload className="mr-1.5 h-4 w-4" />
        Import
      </Button>

      <Dialog open={open} onOpenChange={handleClose}>
        <DialogContent className="sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>Import Shared Geography</DialogTitle>
          </DialogHeader>

          {step === 'input' && (
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">
                Bulk-import canonical <strong>Region</strong>, <strong>SubRegion</strong>, <strong>Cluster</strong>, and <strong>Country</strong> items from CSV or simple text. Shared Geography is a flat canonical catalog, so the import only needs type, code, name, and optional country code for countries.
              </p>

              <Tabs value={inputTab} onValueChange={setInputTab}>
                <div className="flex items-center justify-between">
                  <TabsList>
                    <TabsTrigger value="paste-csv">Paste CSV</TabsTrigger>
                    <TabsTrigger value="upload-csv">Upload CSV</TabsTrigger>
                    <TabsTrigger value="indented">Indented Text</TabsTrigger>
                  </TabsList>
                  <Button variant="ghost" size="sm" onClick={downloadTemplate} className="h-7 gap-1 text-xs">
                    <Download className="h-3.5 w-3.5" />
                    Template
                  </Button>
                </div>

                <TabsContent value="paste-csv" className="mt-3">
                  <Textarea
                    className="font-mono text-xs"
                    rows={10}
                    placeholder={
                      'Type,Code,Name,CountryCode\n' +
                      'Region,EMEA,Europe Middle East & Africa,\n' +
                      'SubRegion,WEU,Western Europe,\n' +
                      'Cluster,BENELUX,Benelux,\n' +
                      'Country,BE,Belgium,BE'
                    }
                    value={csvText}
                    onChange={(e) => setCsvText(e.target.value)}
                  />
                </TabsContent>

                <TabsContent value="upload-csv" className="mt-3">
                  <div
                    className="flex cursor-pointer flex-col items-center justify-center gap-3 rounded-md border-2 border-dashed py-10 transition-colors hover:border-primary/50 hover:bg-muted/30"
                    onClick={() => fileInputRef.current?.click()}
                  >
                    <Upload className="h-8 w-8 text-muted-foreground" />
                    <div className="text-center">
                      <p className="text-sm font-medium">Click to upload a CSV file</p>
                      <p className="mt-0.5 text-xs text-muted-foreground">or drag and drop</p>
                    </div>
                    {csvText && (
                      <Badge variant="secondary" className="text-xs">
                        File loaded — {csvText.split('\n').length - 1} data rows
                      </Badge>
                    )}
                  </div>
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept=".csv,text/csv"
                    className="hidden"
                    onChange={handleFileUpload}
                  />
                </TabsContent>

                <TabsContent value="indented" className="mt-3">
                  <Textarea
                    className="font-mono text-xs"
                    rows={10}
                    placeholder={
                      'Region EMEA: Europe Middle East & Africa\n' +
                      'SubRegion WEU: Western Europe\n' +
                      'Cluster BENELUX: Benelux\n' +
                      'Country BE: Belgium'
                    }
                    value={indentedText}
                    onChange={(e) => setIndentedText(e.target.value)}
                  />
                  <p className="mt-1.5 text-xs text-muted-foreground">
                    Format: <code className="font-mono">Type Code: Name</code>. For countries,
                    the code is also used as the default country code.
                  </p>
                </TabsContent>
              </Tabs>
            </div>
          )}

          {step === 'preview' && (
            <div className="space-y-3">
              <div className="flex items-center gap-3">
                <span className="text-sm font-medium">{validatedRows.length} rows parsed</span>
                {errorCount > 0 && (
                  <Badge variant="destructive" className="text-xs">
                    {errorCount} error{errorCount !== 1 ? 's' : ''}
                  </Badge>
                )}
                {warningCount > 0 && (
                  <Badge variant="secondary" className="border-warning-border bg-warning-muted text-xs text-warning-muted-foreground">
                    {warningCount} warning{warningCount !== 1 ? 's' : ''}
                  </Badge>
                )}
                {!hasErrors && errorCount === 0 && warningCount === 0 && (
                  <Badge variant="secondary" className="border-success-border bg-success-muted text-xs text-success-muted-foreground">
                    All valid
                  </Badge>
                )}
              </div>

              <div className="max-h-80 overflow-auto rounded-md border">
                <table className="w-full text-xs">
                  <thead className="sticky top-0 bg-muted/80">
                    <tr className="border-b">
                      <th className="w-8 px-3 py-2 text-left font-medium text-muted-foreground">#</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Type</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Code</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Name</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Country</th>
                      <th className="w-8 px-3 py-2 text-left font-medium text-muted-foreground" />
                    </tr>
                  </thead>
                  <tbody>
                    {validatedRows.map((vr, i) => (
                      <tr
                        key={i}
                        className={[
                          'border-b last:border-0',
                          vr.status === 'error' ? 'bg-danger-muted/50' : '',
                          vr.status === 'warning' ? 'bg-warning-muted/50' : '',
                        ].join(' ')}
                      >
                        <td className="px-3 py-1.5 tabular-nums text-muted-foreground">{i + 1}</td>
                        <td className="px-3 py-1.5">
                          <OrgUnitTypeBadge type={vr.row.geoUnitType} />
                        </td>
                        <td className="px-3 py-1.5 font-mono">{vr.row.geoUnitCode || <span className="text-muted-foreground/40">—</span>}</td>
                        <td className="px-3 py-1.5">{vr.row.geoUnitName || <span className="text-muted-foreground/40">—</span>}</td>
                        <td className="px-3 py-1.5 font-mono text-muted-foreground">{vr.row.countryCode || <span className="text-muted-foreground/40">—</span>}</td>
                        <td className="px-3 py-1.5">
                          {vr.status === 'error' && (
                            <span title={vr.errors.join(' ')}>
                              <XCircle className="h-4 w-4 text-destructive" />
                            </span>
                          )}
                          {vr.status === 'warning' && (
                            <span className="text-xs text-warning" title={vr.warnings.join(' ')}>⚠</span>
                          )}
                          {vr.status === 'valid' && <CheckCircle2 className="h-4 w-4 text-success" />}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {(errorCount > 0 || warningCount > 0) && (
                <div className="max-h-32 space-y-1 overflow-auto">
                  {validatedRows.flatMap((vr, i) => [
                    ...vr.errors.map((e) => (
                      <p key={`e-${i}-${e}`} className="text-xs text-destructive">
                        Row {i + 1}: {e}
                      </p>
                    )),
                    ...vr.warnings.map((w) => (
                      <p key={`w-${i}-${w}`} className="text-xs text-warning-muted-foreground">
                        Row {i + 1}: {w}
                      </p>
                    )),
                  ])}
                </div>
              )}
            </div>
          )}

          {step === 'results' && (
            <div className="space-y-3">
              <div className="max-h-80 overflow-auto rounded-md border">
                <table className="w-full text-xs">
                  <thead className="sticky top-0 bg-muted/80">
                    <tr className="border-b">
                      <th className="w-8 px-3 py-2 text-left font-medium text-muted-foreground">#</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Result</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Details</th>
                    </tr>
                  </thead>
                  <tbody>
                    {importResults.map((result) => (
                      <tr key={result.rowIndex} className="border-b last:border-0">
                        <td className="px-3 py-1.5 tabular-nums text-muted-foreground">{result.rowIndex + 1}</td>
                        <td className="px-3 py-1.5">
                          {result.success ? (
                            <span className="inline-flex items-center gap-1 text-success-muted-foreground">
                              <CheckCircle2 className="h-4 w-4" />
                              Imported
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1 text-destructive">
                              <XCircle className="h-4 w-4" />
                              Failed
                            </span>
                          )}
                        </td>
                        <td className="px-3 py-1.5 text-muted-foreground">
                          {result.success
                            ? `SharedGeoUnitId ${result.sharedGeoUnitId}`
                            : (result.error ?? 'Unknown error')}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          <DialogFooter>
            {step === 'input' && (
              <>
                <Button type="button" variant="outline" onClick={handleClose}>
                  Cancel
                </Button>
                <Button
                  type="button"
                  onClick={handlePreview}
                  disabled={
                    (inputTab === 'indented' ? !indentedText.trim() : !csvText.trim()) ||
                    sharedGeoUnits === undefined
                  }
                >
                  Preview Import
                </Button>
              </>
            )}

            {step === 'preview' && (
              <>
                <Button type="button" variant="outline" onClick={() => setStep('input')}>
                  Back
                </Button>
                <Button
                  type="button"
                  onClick={() => importMutation.mutate()}
                  disabled={hasErrors || importMutation.isPending || validatedRows.length === 0}
                >
                  {importMutation.isPending ? 'Importing...' : 'Import Shared Geography'}
                </Button>
              </>
            )}

            {step === 'results' && (
              <Button type="button" onClick={handleClose}>
                Close
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
