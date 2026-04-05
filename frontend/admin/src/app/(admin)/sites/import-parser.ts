import type { BulkOrgUnitRow, OrgUnit, OrgUnitType } from '@/types/api'

const ALLOWED_TYPES: OrgUnitType[] = ['Area', 'Branch', 'Site']

const ALLOWED_PARENT_TYPES: Record<string, OrgUnitType[]> = {
  Area: ['Country'],
  Branch: ['Country', 'Area'],
  Site: ['Country', 'Area', 'Branch'],
}

// ---------------------------------------------------------------------------
// CSV parser
// ---------------------------------------------------------------------------

export function parseCsv(text: string): BulkOrgUnitRow[] {
  const lines = text.trim().split(/\r?\n/)
  if (lines.length < 2) return []

  const headers = lines[0].split(',').map((h) => h.trim().toLowerCase())
  const typeIdx = headers.indexOf('type')
  const codeIdx = headers.indexOf('code')
  const nameIdx = headers.indexOf('name')
  const parentTypeIdx = headers.indexOf('parenttype')
  const parentCodeIdx = headers.indexOf('parentcode')

  if (typeIdx === -1 || codeIdx === -1 || nameIdx === -1) return []

  return lines.slice(1).map((line) => {
    const cols = splitCsvLine(line)
    return {
      orgUnitType: cols[typeIdx]?.trim() ?? '',
      orgUnitCode: cols[codeIdx]?.trim() ?? '',
      orgUnitName: cols[nameIdx]?.trim() ?? '',
      parentOrgUnitType: parentTypeIdx !== -1 ? cols[parentTypeIdx]?.trim() || undefined : undefined,
      parentOrgUnitCode: parentCodeIdx !== -1 ? cols[parentCodeIdx]?.trim() || undefined : undefined,
    }
  }).filter((r) => r.orgUnitCode || r.orgUnitName)
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

// ---------------------------------------------------------------------------
// Indented text parser
//
// Accepts lines like:
//   Area PN: Paris North
//     Branch PN-WEST: Paris West Branch
//       Site PHQ: Paris HQ
//
// Indentation (spaces or tabs) determines parent-child relationship.
// Format per line: <Type> <Code>: <Name>
// ---------------------------------------------------------------------------

export function parseIndented(text: string): BulkOrgUnitRow[] {
  const lines = text.split(/\r?\n/).filter((l) => l.trim())
  const result: BulkOrgUnitRow[] = []

  // stack entries: { indent, row }
  const stack: Array<{ indent: number; row: BulkOrgUnitRow }> = []

  for (const line of lines) {
    const indent = line.match(/^(\s*)/)?.[1].length ?? 0
    const trimmed = line.trim()

    // Match: Type Code: Name  OR  Type Code Name (colon optional)
    const match = trimmed.match(/^(\w+)\s+([^\s:]+)\s*:\s*(.+)$/) ??
                  trimmed.match(/^(\w+)\s+([^\s]+)\s+(.+)$/)
    if (!match) continue

    const [, rawType, code, name] = match

    // Pop stack entries that are at same or deeper indentation
    while (stack.length > 0 && stack[stack.length - 1].indent >= indent) {
      stack.pop()
    }

    const parent = stack.length > 0 ? stack[stack.length - 1].row : null

    const row: BulkOrgUnitRow = {
      orgUnitType: rawType,
      orgUnitCode: code.trim(),
      orgUnitName: name.trim(),
      parentOrgUnitType: parent?.orgUnitType,
      parentOrgUnitCode: parent?.orgUnitCode,
    }

    result.push(row)
    stack.push({ indent, row })
  }

  return result
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

export type RowStatus = 'valid' | 'warning' | 'error'

export interface ValidatedRow {
  row: BulkOrgUnitRow
  status: RowStatus
  errors: string[]
  warnings: string[]
}

export function validateRows(rows: BulkOrgUnitRow[], existingOrgUnits: OrgUnit[]): ValidatedRow[] {
  // Build a set of codes available: from DB + from earlier rows in this batch
  const knownUnits = new Map<string, OrgUnitType>(
    existingOrgUnits.map((u) => [`${u.orgUnitType}:${u.orgUnitCode}`, u.orgUnitType])
  )

  return rows.map((row, idx) => {
    const errors: string[] = []
    const warnings: string[] = []

    // Type check
    if (!row.orgUnitType) {
      errors.push('Type is required.')
    } else if (!(ALLOWED_TYPES as string[]).includes(row.orgUnitType)) {
      errors.push(`Type must be one of: ${ALLOWED_TYPES.join(', ')}. Got "${row.orgUnitType}".`)
    }

    // Code check
    if (!row.orgUnitCode) {
      errors.push('Code is required.')
    }

    // Name check
    if (!row.orgUnitName) {
      errors.push('Name is required.')
    }

    // Parent checks
    if (row.orgUnitType && (ALLOWED_TYPES as string[]).includes(row.orgUnitType)) {
      const allowed = ALLOWED_PARENT_TYPES[row.orgUnitType] ?? []

      if (!row.parentOrgUnitType || !row.parentOrgUnitCode) {
        errors.push('Parent type and code are required for Area, Branch, and Site.')
      } else if (!allowed.includes(row.parentOrgUnitType as OrgUnitType)) {
        errors.push(
          `${row.orgUnitType} cannot have a ${row.parentOrgUnitType} parent. Allowed: ${allowed.join(', ')}.`
        )
      } else {
        const parentKey = `${row.parentOrgUnitType}:${row.parentOrgUnitCode}`
        const inBatchEarlier = rows
          .slice(0, idx)
          .some(
            (r) => r.orgUnitType === row.parentOrgUnitType && r.orgUnitCode === row.parentOrgUnitCode
          )

        if (!knownUnits.has(parentKey) && !inBatchEarlier) {
          warnings.push(
            `Parent "${row.parentOrgUnitCode}" (${row.parentOrgUnitType}) not found in database. ` +
            'It may need to exist before import.'
          )
        }
      }
    }

    // Register this row in knownUnits so later rows can reference it
    if (row.orgUnitType && row.orgUnitCode) {
      knownUnits.set(`${row.orgUnitType}:${row.orgUnitCode}`, row.orgUnitType as OrgUnitType)
    }

    const status: RowStatus =
      errors.length > 0 ? 'error' : warnings.length > 0 ? 'warning' : 'valid'

    return { row, status, errors, warnings }
  })
}

// ---------------------------------------------------------------------------
// Template CSV content
// ---------------------------------------------------------------------------

export const TEMPLATE_CSV =
  'Type,Code,Name,ParentType,ParentCode\n' +
  'Area,AREA-001,My Area,Country,US\n' +
  'Branch,BR-001,My Branch,Area,AREA-001\n' +
  'Site,SITE-001,My Site,Branch,BR-001\n' +
  'Site,SITE-002,Another Site,Area,AREA-001\n'
