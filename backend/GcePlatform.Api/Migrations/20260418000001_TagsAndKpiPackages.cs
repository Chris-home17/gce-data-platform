using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GcePlatform.Api.Migrations
{
    /// <inheritdoc />
    public partial class TagsAndKpiPackages : Migration
    {
        /// <inheritdoc />
        /// Adds Tags, KPI-to-Tag relationship, KPI Packages, and package-based
        /// assignment tracking to the platform.
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.TagsAndKpiPackages.Up.sql");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.TagsAndKpiPackages.Down.sql");
        }

        private static void ExecuteSqlScript(MigrationBuilder migrationBuilder, string resourceName)
        {
            var assembly = typeof(TagsAndKpiPackages).Assembly;
            using var stream = assembly.GetManifestResourceStream(resourceName)
                ?? throw new InvalidOperationException(
                    $"Embedded SQL resource '{resourceName}' was not found.");

            using var reader = new StreamReader(stream);
            var sql = reader.ReadToEnd();

            var batches = Regex.Split(
                sql,
                @"^\s*GO\s*$",
                RegexOptions.Multiline | RegexOptions.IgnoreCase);

            foreach (var batch in batches)
            {
                var trimmed = batch.Trim();
                if (!string.IsNullOrWhiteSpace(trimmed))
                    migrationBuilder.Sql(trimmed, suppressTransaction: true);
            }
        }
    }
}
