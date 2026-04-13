import type { BulkSharedGeoUnitRow, SharedGeoUnit } from '@/types/api'

const ALLOWED_TYPES = ['Region', 'SubRegion', 'Cluster', 'Country'] as const

export function parseCsv(text: string): BulkSharedGeoUnitRow[] {
  const lines = text.trim().split(/\r?\n/)
  if (lines.length < 2) return []

  const headers = lines[0].split(',').map((h) => h.trim().toLowerCase())
  const typeIdx = headers.indexOf('type')
  const codeIdx = headers.indexOf('code')
  const nameIdx = headers.indexOf('name')
  const countryCodeIdx = headers.indexOf('countrycode')

  if (typeIdx === -1 || codeIdx === -1 || nameIdx === -1) return []

  return lines
    .slice(1)
    .map((line) => {
      const cols = splitCsvLine(line)
      return {
        geoUnitType: cols[typeIdx]?.trim() ?? '',
        geoUnitCode: cols[codeIdx]?.trim() ?? '',
        geoUnitName: cols[nameIdx]?.trim() ?? '',
        countryCode: countryCodeIdx !== -1 ? cols[countryCodeIdx]?.trim() || undefined : undefined,
      }
    })
    .filter((r) => r.geoUnitCode || r.geoUnitName)
}

function splitCsvLine(line: string): string[] {
  const result: string[] = []
  let current = ''
  let inQuotes = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (ch === '"') {
      if (inQuotes && line[i + 1] === '"') {
        current += '"'
        i++
      } else {
        inQuotes = !inQuotes
      }
    } else if (ch === ',' && !inQuotes) {
      result.push(current)
      current = ''
    } else {
      current += ch
    }
  }
  result.push(current)
  return result
}

export function parseIndented(text: string): BulkSharedGeoUnitRow[] {
  const lines = text.split(/\r?\n/).filter((l) => l.trim())
  const result: BulkSharedGeoUnitRow[] = []

  for (const line of lines) {
    const trimmed = line.trim()

    const match =
      trimmed.match(/^(\w+)\s+([^\s:]+)\s*:\s*(.+)$/) ??
      trimmed.match(/^(\w+)\s+([^\s]+)\s+(.+)$/)
    if (!match) continue

    const [, rawType, code, name] = match
    const row: BulkSharedGeoUnitRow = {
      geoUnitType: rawType,
      geoUnitCode: code.trim(),
      geoUnitName: name.trim(),
      countryCode: rawType === 'Country' ? code.trim() : undefined,
    }

    result.push(row)
  }

  return result
}

export type RowStatus = 'valid' | 'warning' | 'error'

export interface ValidatedRow {
  row: BulkSharedGeoUnitRow
  status: RowStatus
  errors: string[]
  warnings: string[]
}

export function validateRows(rows: BulkSharedGeoUnitRow[], existingSharedGeoUnits: SharedGeoUnit[]): ValidatedRow[] {
  const knownSharedGeo = new Set<string>(
    existingSharedGeoUnits.map((g) => `${g.geoUnitType}:${g.geoUnitCode}`)
  )
  const batchSeen = new Set<string>()

  return rows.map((row) => {
    const errors: string[] = []
    const warnings: string[] = []

    if (!row.geoUnitType) {
      errors.push('Type is required.')
    } else if (!(ALLOWED_TYPES as readonly string[]).includes(row.geoUnitType)) {
      errors.push(`Type must be one of: ${ALLOWED_TYPES.join(', ')}. Got "${row.geoUnitType}".`)
    }

    if (!row.geoUnitCode) {
      errors.push('Code is required.')
    }

    if (!row.geoUnitName) {
      errors.push('Name is required.')
    }

    if (row.geoUnitType === 'Country') {
      if (!row.countryCode?.trim()) {
        errors.push('Country code is required for Country.')
      }
    } else if (row.countryCode?.trim()) {
      warnings.push('Country code is only used for Country rows and will be ignored for other types.')
    }

    if (row.geoUnitType && row.geoUnitCode) {
      const key = `${row.geoUnitType}:${row.geoUnitCode}`
      if (knownSharedGeo.has(key)) {
        warnings.push(`Shared Geography "${row.geoUnitCode}" (${row.geoUnitType}) already exists and may fail on import.`)
      }
      if (batchSeen.has(key)) {
        errors.push(`Duplicate row in this import for "${row.geoUnitCode}" (${row.geoUnitType}).`)
      }
      batchSeen.add(key)
    }

    const status: RowStatus =
      errors.length > 0 ? 'error' : warnings.length > 0 ? 'warning' : 'valid'

    return { row, status, errors, warnings }
  })
}

export const TEMPLATE_CSV =
  'Type,Code,Name,CountryCode\n' +
  'Region,EMEA,Europe Middle East & Africa,\n' +
  'SubRegion,WEU,Western Europe,\n' +
  'Cluster,BENELUX,Benelux,\n' +
  'Country,BE,Belgium,BE\n'
