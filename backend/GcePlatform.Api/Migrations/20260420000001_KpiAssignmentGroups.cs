using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GcePlatform.Api.Migrations
{
    /// <inheritdoc />
    public partial class KpiAssignmentGroups : Migration
    {
        /// <inheritdoc />
        /// Adds optional named group support to KPI assignments.
        /// Groups allow the same account/site to have separate sets of KPI assignments
        /// (e.g. "Technology" and "Operational") tracked independently in monitoring.
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.KpiAssignmentGroups.Up.sql");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.KpiAssignmentGroups.Down.sql");
        }

        private static void ExecuteSqlScript(MigrationBuilder migrationBuilder, string resourceName)
        {
            var assembly = typeof(KpiAssignmentGroups).Assembly;
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
