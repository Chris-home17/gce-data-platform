using System.Text.RegularExpressions;

namespace GcePlatform.Api.Helpers;

/// <summary>
/// Per-assignment validation: range, precision, regex. All rules optional.
/// Authoritative server-side check, mirrored client-side for instant UX.
/// usp_SubmitKpi only snapshots the rules; the validator runs in the endpoint.
/// </summary>
public static class SubmissionValidator
{
    public record Rules(
        decimal? MinValue,
        decimal? MaxValue,
        int?     Precision,
        string?  Regex,
        string?  Message);

    public record Result(bool Ok, string? ErrorMessage);

    public static readonly Result Pass = new(true, null);

    /// <summary>
    /// Validates a submission's payload against the assignment's rules.
    /// Returns <see cref="Pass"/> when no rule of the relevant kind is set,
    /// otherwise the first failing rule's message (custom if provided).
    /// </summary>
    public static Result Validate(string dataType, Rules rules,
                                  decimal? value, string? text)
    {
        // Numeric-like data types: range + precision on `value`.
        if (dataType is "Numeric" or "Percentage" or "Currency" or "Time")
        {
            if (value is null)
                return Pass; // Empty submission handled by IsRequired logic, not here.

            if (rules.MinValue is not null && value < rules.MinValue)
                return Fail(rules, $"Value must be at least {rules.MinValue}.");
            if (rules.MaxValue is not null && value > rules.MaxValue)
                return Fail(rules, $"Value must be at most {rules.MaxValue}.");
            if (rules.Precision is not null)
            {
                var rounded = Math.Round(value.Value, rules.Precision.Value);
                if (rounded != value.Value)
                {
                    var places = rules.Precision.Value;
                    return Fail(rules, places == 0
                        ? "Value must be a whole number."
                        : $"Value must have at most {places} decimal place{(places == 1 ? "" : "s")}.");
                }
            }
            return Pass;
        }

        // Text / DropDown — regex only.
        if (dataType is "Text" or "DropDown")
        {
            if (rules.Regex is null || string.IsNullOrEmpty(rules.Regex))
                return Pass;
            if (text is null) return Pass;

            try
            {
                var match = Regex.IsMatch(
                    text,
                    rules.Regex,
                    RegexOptions.None,
                    matchTimeout: TimeSpan.FromMilliseconds(100));
                if (!match)
                    return Fail(rules, "Value does not match the required format.");
            }
            catch (RegexMatchTimeoutException)
            {
                return Fail(rules, "Validation regex took too long to evaluate. Contact your admin.");
            }
            catch (ArgumentException)
            {
                // Malformed regex on the assignment — surface to the admin via the error.
                return Fail(rules, "Validation regex is invalid. Contact your admin.");
            }
            return Pass;
        }

        // Boolean / unknown types: nothing to validate.
        return Pass;
    }

    private static Result Fail(Rules rules, string defaultMessage)
        => new(false, string.IsNullOrWhiteSpace(rules.Message) ? defaultMessage : rules.Message);
}
