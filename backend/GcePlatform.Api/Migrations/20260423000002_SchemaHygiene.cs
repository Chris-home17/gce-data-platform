using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GcePlatform.Api.Migrations
{
    /// <inheritdoc />
    public partial class SchemaHygiene : Migration
    {
        /// <inheritdoc />
        /// Closes a handful of schema-hygiene gaps: audit columns on
        /// KPI.PeriodSchedule and KPI.AssignmentTemplate become NOT NULL with
        /// the same defaults as the rest of the platform, Dim.Tag.TagName gets
        /// a UNIQUE index so the procedural guard can't be bypassed, and two
        /// missing supporting indexes are added.
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.SchemaHygiene.Up.sql");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            ExecuteSqlScript(migrationBuilder,
                "GcePlatform.Api.Migrations.Scripts.SchemaHygiene.Down.sql");
        }

        private static void ExecuteSqlScript(MigrationBuilder migrationBuilder, string resourceName)
        {
            var assembly = typeof(SchemaHygiene).Assembly;
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
