using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GcePlatform.Api.Migrations
{
    /// <inheritdoc />
    public partial class SplitKpiPermissions : Migration
    {
        /// <inheritdoc />
        /// Replaces the coarse `kpi.manage` platform permission with two
        /// codes: `kpi.admin` (library/periods/packages) and `kpi.assign`
        /// (account-scoped assignments and submission unlock).
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.SplitKpiPermissions.Up.sql");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.SplitKpiPermissions.Down.sql");
        }

        private static void ExecuteSqlScript(MigrationBuilder migrationBuilder, string resourceName)
        {
            var assembly = typeof(SplitKpiPermissions).Assembly;
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
