using GcePlatform.Api.Models;
using System.Globalization;
using System.Text.RegularExpressions;

namespace GcePlatform.Api.Helpers;

/// <summary>
/// Utilities for normalizing brand colors and computing accessible text colors.
/// </summary>
public static class BrandingHelper
{
    private static readonly Regex HexShort = new(@"^#([0-9A-Fa-f]{3})$", RegexOptions.Compiled);
    private static readonly Regex HexFull  = new(@"^#([0-9A-Fa-f]{6})$", RegexOptions.Compiled);

    /// <summary>
    /// Trims, validates, and normalizes a hex color string.
    /// Returns null for blank, invalid, or unrecognized values.
    /// Accepts #RGB (expanded to #RRGGBB) and #RRGGBB.
    /// </summary>
    public static string? NormalizeColor(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return null;

        var trimmed = raw.Trim().ToUpperInvariant();

        // Expand 3-digit shorthand: #ABC → #AABBCC
        var shortMatch = HexShort.Match(trimmed);
        if (shortMatch.Success)
        {
            var s = shortMatch.Groups[1].Value;
            trimmed = $"#{s[0]}{s[0]}{s[1]}{s[1]}{s[2]}{s[2]}";
        }

        return HexFull.IsMatch(trimmed) ? trimmed : null;
    }

    /// <summary>
    /// Computes a WCAG-accessible foreground text color (black or white) for the
    /// given background hex color. Falls back to "#000000" if parsing fails.
    /// </summary>
    public static string ComputeTextColor(string hexColor)
    {
        if (!TryParseHex(hexColor, out double r, out double g, out double b))
            return "#000000";

        // sRGB linearization
        static double Linearize(double c) =>
            c <= 0.04045 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4);

        var luminance = 0.2126 * Linearize(r) + 0.7152 * Linearize(g) + 0.0722 * Linearize(b);

        // WCAG contrast ratio: (lighter + 0.05) / (darker + 0.05)
        // White background relative luminance = 1.0, black = 0.0
        var contrastAgainstWhiteText = 1.05 / (luminance + 0.05);   // white text on this bg
        var contrastAgainstBlackText = (luminance + 0.05) / 0.05;   // black text on this bg

        // Use whichever text color produces the higher contrast
        return contrastAgainstWhiteText >= contrastAgainstBlackText ? "#FFFFFF" : "#000000";
    }

    /// <summary>
    /// Builds a resolved <see cref="AccountBrandingDto"/> from raw DB values.
    /// Returns null when no meaningful branding data is present.
    /// </summary>
    public static AccountBrandingDto? Resolve(AccountBrandingRaw? raw)
    {
        if (raw is null)
            return null;

        // Consider branding absent when no colors and no logo are stored
        if (raw.PrimaryColor is null && raw.PrimaryColor2 is null &&
            raw.SecondaryColor is null && raw.SecondaryColor2 is null &&
            raw.AccentColor is null && raw.LogoDataUrl is null)
        {
            return null;
        }

        var textOnPrimary = raw.TextOnPrimaryOverride
            ?? (raw.PrimaryColor is not null ? ComputeTextColor(raw.PrimaryColor) : "#000000");

        var textOnSecondary = raw.TextOnSecondaryOverride
            ?? (raw.SecondaryColor is not null ? ComputeTextColor(raw.SecondaryColor) : "#000000");

        return new AccountBrandingDto(
            AccountId:      raw.AccountId,
            PrimaryColor:   raw.PrimaryColor,
            PrimaryColor2:  raw.PrimaryColor2,
            SecondaryColor: raw.SecondaryColor,
            SecondaryColor2: raw.SecondaryColor2,
            AccentColor:    raw.AccentColor,
            TextOnPrimary:  textOnPrimary,
            TextOnSecondary: textOnSecondary,
            LogoDataUrl:    raw.LogoDataUrl
        );
    }

    // ---------------------------------------------------------------------------
    // Private helpers
    // ---------------------------------------------------------------------------

    private static bool TryParseHex(string hex, out double r, out double g, out double b)
    {
        r = g = b = 0;
        var normalized = NormalizeColor(hex);
        if (normalized is null || normalized.Length != 7)
            return false;

        r = int.Parse(normalized[1..3], NumberStyles.HexNumber) / 255.0;
        g = int.Parse(normalized[3..5], NumberStyles.HexNumber) / 255.0;
        b = int.Parse(normalized[5..7], NumberStyles.HexNumber) / 255.0;
        return true;
    }
}
