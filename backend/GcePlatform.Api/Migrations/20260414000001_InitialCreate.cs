using System.Reflection;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GcePlatform.Api.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        /// Runs the full baseline DDL — use this to initialise a brand-new empty database.
        /// On databases that are already populated, insert this migration's ID into
        /// __EFMigrationsHistory manually (see WORKFLOW.md) and apply only AccountBranding.
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.InitialCreate.Up.sql");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.InitialCreate.Down.sql");
        }

        // ---------------------------------------------------------------------------
        // Helper — loads an embedded SQL script and executes each GO-delimited batch.
        // suppressTransaction=true is required for DDL (CREATE TABLE, ALTER TABLE, etc.)
        // that SQL Server cannot run inside a transaction.
        // ---------------------------------------------------------------------------

        private static void ExecuteSqlScript(MigrationBuilder migrationBuilder, string resourceName)
        {
            var assembly = typeof(InitialCreate).Assembly;
            using var stream = assembly.GetManifestResourceStream(resourceName)
                ?? throw new InvalidOperationException(
                    $"Embedded SQL resource '{resourceName}' was not found. " +
                    "Ensure the file is marked as EmbeddedResource in the project.");

            using var reader = new StreamReader(stream);
            var sql = reader.ReadToEnd();

            // Split on GO statement separator (SQL Server batch separator, not native SQL)
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
