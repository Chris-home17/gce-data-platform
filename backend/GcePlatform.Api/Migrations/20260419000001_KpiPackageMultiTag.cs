using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GcePlatform.Api.Migrations
{
    /// <inheritdoc />
    public partial class KpiPackageMultiTag : Migration
    {
        /// <inheritdoc />
        /// Converts KPI.KpiPackage from a single-tag FK to a many-to-many junction table
        /// (KPI.KpiPackageTag), and updates the view + stored procedures accordingly.
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.KpiPackageMultiTag.Up.sql");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.KpiPackageMultiTag.Down.sql");
        }

        private static void ExecuteSqlScript(MigrationBuilder migrationBuilder, string resourceName)
        {
            var assembly = typeof(KpiPackageMultiTag).Assembly;
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
