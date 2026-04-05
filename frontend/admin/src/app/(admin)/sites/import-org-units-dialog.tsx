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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import { Badge } from '@/components/ui/badge'
import { api } from '@/lib/api'
import type { BulkOrgUnitResult } from '@/types/api'
import {
  parseCsv,
  parseIndented,
  validateRows,
  TEMPLATE_CSV,
  type ValidatedRow,
} from './import-parser'

type Step = 'input' | 'preview' | 'results'

export function ImportOrgUnitsDialog() {
  const [open, setOpen] = useState(false)
  const [step, setStep] = useState<Step>('input')
  const [accountCode, setAccountCode] = useState('')
  const [inputTab, setInputTab] = useState('paste-csv')
  const [csvText, setCsvText] = useState('')
  const [indentedText, setIndentedText] = useState('')
  const [validatedRows, setValidatedRows] = useState<ValidatedRow[]>([])
  const [importResults, setImportResults] = useState<BulkOrgUnitResult[]>([])
  const fileInputRef = useRef<HTMLInputElement>(null)
  const queryClient = useQueryClient()

  const { data: accounts } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: open,
  })

  const { data: orgUnitsData } = useQuery({
    queryKey: ['org-units', accountCode],
    queryFn: () => {
      const account = accounts?.items.find((a) => a.accountCode === accountCode)
      return account ? api.orgUnits.list({ accountId: account.accountId }) : Promise.resolve(null)
    },
    enabled: open && !!accountCode && !!accounts,
  })

  const importMutation = useMutation({
    mutationFn: () =>
      api.orgUnits.bulkCreate({
        accountCode,
        rows: validatedRows.map((vr) => vr.row),
      }),
    onSuccess: (response) => {
      setImportResults(response.results)
      setStep('results')
      queryClient.invalidateQueries({ queryKey: ['org-units'] })
      const successCount = response.results.filter((r) => r.success).length
      const failCount = response.results.length - successCount
      if (failCount === 0) {
        toast.success(`${successCount} org unit${successCount !== 1 ? 's' : ''} imported.`)
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
    setAccountCode('')
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
    const rows =
      inputTab === 'indented' ? parseIndented(rawText) : parseCsv(rawText)

    const existing = orgUnitsData?.items ?? []
    const validated = validateRows(rows, existing)
    setValidatedRows(validated)
    setStep('preview')
  }

  function downloadTemplate() {
    const blob = new Blob([TEMPLATE_CSV], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'org-units-template.csv'
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
            <DialogTitle>Import Org Units</DialogTitle>
          </DialogHeader>

          {step === 'input' && (
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">
                Bulk-create <strong>Area</strong>, <strong>Branch</strong>, and <strong>Site</strong> org
                units from a CSV or indented text. Rows are processed in order — parents must appear
                before their children.
              </p>

              {/* Account selector */}
              <div className="space-y-1.5">
                <label className="text-sm font-medium">Account</label>
                <Select value={accountCode} onValueChange={setAccountCode}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select account…" />
                  </SelectTrigger>
                  <SelectContent>
                    {accounts?.items.map((a) => (
                      <SelectItem key={a.accountId} value={a.accountCode}>
                        {a.accountName} ({a.accountCode})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {/* Input method tabs */}
              <Tabs value={inputTab} onValueChange={setInputTab}>
                <div className="flex items-center justify-between">
                  <TabsList>
                    <TabsTrigger value="paste-csv">Paste CSV</TabsTrigger>
                    <TabsTrigger value="upload-csv">Upload CSV</TabsTrigger>
                    <TabsTrigger value="indented">Indented Text</TabsTrigger>
                  </TabsList>
                  <Button variant="ghost" size="sm" onClick={downloadTemplate} className="h-7 text-xs gap-1">
                    <Download className="h-3.5 w-3.5" />
                    Template
                  </Button>
                </div>

                <TabsContent value="paste-csv" className="mt-3">
                  <Textarea
                    className="font-mono text-xs"
                    rows={10}
                    placeholder={
                      'Type,Code,Name,ParentType,ParentCode\n' +
                      'Area,PN,Paris North,Country,FR\n' +
                      'Branch,PN-W,Paris West,Area,PN\n' +
                      'Site,PHQ,Paris HQ,Branch,PN-W'
                    }
                    value={csvText}
                    onChange={(e) => setCsvText(e.target.value)}
                  />
                </TabsContent>

                <TabsContent value="upload-csv" className="mt-3">
                  <div
                    className="flex flex-col items-center justify-center gap-3 rounded-md border-2 border-dashed py-10 cursor-pointer hover:border-primary/50 hover:bg-muted/30 transition-colors"
                    onClick={() => fileInputRef.current?.click()}
                  >
                    <Upload className="h-8 w-8 text-muted-foreground" />
                    <div className="text-center">
                      <p className="text-sm font-medium">Click to upload a CSV file</p>
                      <p className="text-xs text-muted-foreground mt-0.5">or drag and drop</p>
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
                      'Area PN: Paris North\n' +
                      '  Branch PN-W: Paris West\n' +
                      '    Site PHQ: Paris HQ\n' +
                      '  Site PST: Paris Saint-Lazare'
                    }
                    value={indentedText}
                    onChange={(e) => setIndentedText(e.target.value)}
                  />
                  <p className="mt-1.5 text-xs text-muted-foreground">
                    Format: <code className="font-mono">Type Code: Name</code> — indentation
                    determines parent/child relationship.
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
                  <Badge variant="secondary" className="text-xs text-amber-700 bg-amber-100 border-amber-200">
                    {warningCount} warning{warningCount !== 1 ? 's' : ''}
                  </Badge>
                )}
                {!hasErrors && errorCount === 0 && warningCount === 0 && (
                  <Badge variant="secondary" className="text-xs text-emerald-700 bg-emerald-100 border-emerald-200">
                    All valid
                  </Badge>
                )}
              </div>

              <div className="rounded-md border max-h-80 overflow-auto">
                <table className="w-full text-xs">
                  <thead className="sticky top-0 bg-muted/80">
                    <tr className="border-b">
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground w-8">#</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Type</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Code</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Name</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Parent</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground w-8" />
                    </tr>
                  </thead>
                  <tbody>
                    {validatedRows.map((vr, i) => (
                      <tr
                        key={i}
                        className={[
                          'border-b last:border-0',
                          vr.status === 'error' ? 'bg-red-50' : '',
                          vr.status === 'warning' ? 'bg-amber-50' : '',
                        ].join(' ')}
                      >
                        <td className="px-3 py-1.5 text-muted-foreground tabular-nums">{i + 1}</td>
                        <td className="px-3 py-1.5">
                          <TypeChip type={vr.row.orgUnitType} />
                        </td>
                        <td className="px-3 py-1.5 font-mono">{vr.row.orgUnitCode || <span className="text-muted-foreground/40">—</span>}</td>
                        <td className="px-3 py-1.5">{vr.row.orgUnitName || <span className="text-muted-foreground/40">—</span>}</td>
                        <td className="px-3 py-1.5 text-muted-foreground">
                          {vr.row.parentOrgUnitCode
                            ? `${vr.row.parentOrgUnitType} ${vr.row.parentOrgUnitCode}`
                            : <span className="text-muted-foreground/40">—</span>}
                        </td>
                        <td className="px-3 py-1.5">
                          {vr.status === 'error' && (
                            <XCircle className="h-4 w-4 text-destructive" title={vr.errors.join(' ')} />
                          )}
                          {vr.status === 'warning' && (
                            <span className="text-amber-500 text-xs" title={vr.warnings.join(' ')}>⚠</span>
                          )}
                          {vr.status === 'valid' && (
                            <CheckCircle2 className="h-4 w-4 text-emerald-500" />
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Inline error messages */}
              {(errorCount > 0 || warningCount > 0) && (
                <div className="space-y-1 max-h-32 overflow-auto">
                  {validatedRows.flatMap((vr, i) => [
                    ...vr.errors.map((e) => (
                      <p key={`e-${i}-${e}`} className="text-xs text-destructive">
                        Row {i + 1}: {e}
                      </p>
                    )),
                    ...vr.warnings.map((w) => (
                      <p key={`w-${i}-${w}`} className="text-xs text-amber-600">
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
              <div className="flex items-center gap-3">
                <span className="text-sm font-medium">{importResults.length} rows processed</span>
                <Badge variant="secondary" className="text-xs text-emerald-700 bg-emerald-100 border-emerald-200">
                  {importResults.filter((r) => r.success).length} created
                </Badge>
                {importResults.some((r) => !r.success) && (
                  <Badge variant="destructive" className="text-xs">
                    {importResults.filter((r) => !r.success).length} failed
                  </Badge>
                )}
              </div>

              <div className="rounded-md border max-h-80 overflow-auto">
                <table className="w-full text-xs">
                  <thead className="sticky top-0 bg-muted/80">
                    <tr className="border-b">
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground w-8">#</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Type</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Code</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Name</th>
                      <th className="px-3 py-2 text-left font-medium text-muted-foreground">Result</th>
                    </tr>
                  </thead>
                  <tbody>
                    {importResults.map((result, i) => {
                      const vr = validatedRows[result.rowIndex]
                      return (
                        <tr
                          key={i}
                          className={[
                            'border-b last:border-0',
                            !result.success ? 'bg-red-50' : '',
                          ].join(' ')}
                        >
                          <td className="px-3 py-1.5 text-muted-foreground tabular-nums">{result.rowIndex + 1}</td>
                          <td className="px-3 py-1.5">
                            {vr && <TypeChip type={vr.row.orgUnitType} />}
                          </td>
                          <td className="px-3 py-1.5 font-mono">{vr?.row.orgUnitCode}</td>
                          <td className="px-3 py-1.5">{vr?.row.orgUnitName}</td>
                          <td className="px-3 py-1.5">
                            {result.success ? (
                              <span className="flex items-center gap-1 text-emerald-600">
                                <CheckCircle2 className="h-3.5 w-3.5" /> Created
                              </span>
                            ) : (
                              <span className="flex items-center gap-1 text-destructive">
                                <XCircle className="h-3.5 w-3.5" />
                                <span className="truncate max-w-[200px]" title={result.error ?? ''}>
                                  {result.error}
                                </span>
                              </span>
                            )}
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          <DialogFooter className="gap-2">
            {step === 'input' && (
              <>
                <Button variant="outline" onClick={handleClose}>Cancel</Button>
                <Button
                  onClick={handlePreview}
                  disabled={!accountCode || (inputTab === 'indented' ? !indentedText.trim() : !csvText.trim())}
                >
                  Preview
                </Button>
              </>
            )}
            {step === 'preview' && (
              <>
                <Button variant="outline" onClick={() => setStep('input')}>Back</Button>
                <Button
                  onClick={() => importMutation.mutate()}
                  disabled={hasErrors || validatedRows.length === 0 || importMutation.isPending}
                >
                  {importMutation.isPending
                    ? 'Importing…'
                    : `Import ${validatedRows.length} row${validatedRows.length !== 1 ? 's' : ''}`}
                </Button>
              </>
            )}
            {step === 'results' && (
              <Button onClick={handleClose}>Done</Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}

function TypeChip({ type }: { type: string }) {
  const colours: Record<string, string> = {
    Area: 'bg-teal-100 text-teal-700 border-teal-200',
    Branch: 'bg-orange-100 text-orange-700 border-orange-200',
    Site: 'bg-emerald-100 text-emerald-700 border-emerald-200',
  }
  return (
    <span
      className={`inline-flex items-center rounded border px-1.5 py-0.5 text-xs font-medium ${colours[type] ?? 'bg-muted text-muted-foreground'}`}
    >
      {type || '?'}
    </span>
  )
}
