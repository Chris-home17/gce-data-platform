/**
 * Mirror of backend `SubmissionValidator.cs` so the capture form can give
 * instant red-text feedback before the user submits. The backend is still the
 * authoritative check on POST /kpi/submissions.
 */

export interface ValidationRules {
  minValue: number | null
  maxValue: number | null
  precision: number | null
  regex: string | null
  message: string | null
}

export type ValidationResult = { ok: true } | { ok: false; error: string }

const PASS: ValidationResult = { ok: true }

export function validateSubmission(args: {
  dataType: string
  rules: ValidationRules
  value?: number | null
  text?: string | null
}): ValidationResult {
  const { dataType, rules, value, text } = args

  // Numeric-like: range + precision check on `value`.
  if (
    dataType === 'Numeric' ||
    dataType === 'Percentage' ||
    dataType === 'Currency' ||
    dataType === 'Time'
  ) {
    if (value === null || value === undefined) return PASS

    if (rules.minValue !== null && value < rules.minValue)
      return fail(rules, `Value must be at least ${rules.minValue}.`)
    if (rules.maxValue !== null && value > rules.maxValue)
      return fail(rules, `Value must be at most ${rules.maxValue}.`)
    if (rules.precision !== null) {
      // Match the C# Math.Round semantics: round half-to-even is JS default
      // for toFixed via Number, but for our purposes we just check whether
      // any digit beyond `precision` is non-zero.
      const factor = Math.pow(10, rules.precision)
      if (Math.round(value * factor) / factor !== value) {
        return fail(
          rules,
          rules.precision === 0
            ? 'Value must be a whole number.'
            : `Value must have at most ${rules.precision} decimal place${rules.precision === 1 ? '' : 's'}.`,
        )
      }
    }
    return PASS
  }

  // Text / DropDown — regex only.
  if (dataType === 'Text' || dataType === 'DropDown') {
    if (!rules.regex) return PASS
    if (text === null || text === undefined) return PASS
    try {
      const re = new RegExp(rules.regex)
      if (!re.test(text))
        return fail(rules, 'Value does not match the required format.')
    } catch {
      return fail(rules, 'Validation regex is invalid. Contact your admin.')
    }
    return PASS
  }

  // Boolean / unknown: nothing to validate.
  return PASS
}

function fail(rules: ValidationRules, defaultMessage: string): ValidationResult {
  const m = rules.message?.trim()
  return { ok: false, error: m && m.length > 0 ? m : defaultMessage }
}
