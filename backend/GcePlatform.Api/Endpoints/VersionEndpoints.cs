using System.Reflection;
using Dapper;
using GcePlatform.Api.Data;

namespace GcePlatform.Api.Endpoints;

public static class VersionEndpoints
{
    private static readonly Lazy<VersionInfoStatic> StaticInfo = new(LoadStatic);
    private static readonly TimeSpan SchemaTtl = TimeSpan.FromSeconds(30);
    private static readonly object SchemaLock = new();
    private static (string? schema, DateTime fetchedAt) _schemaCache;

    public static WebApplication MapVersionEndpoints(this WebApplication app)
    {
        app.MapGet("/version", async (DbConnectionFactory db, IHostEnvironment env) =>
        {
            var s = StaticInfo.Value;
            var schema = await GetSchemaVersionAsync(db);
            return Results.Ok(new
            {
                appVersion = s.AppVersion,
                informationalVersion = s.Informational,
                gitSha = s.GitSha,
                buildDate = s.BuildDate,
                schemaVersion = schema,
                environment = env.EnvironmentName,
            });
        }).AllowAnonymous();

        return app;
    }

    private static async Task<string?> GetSchemaVersionAsync(DbConnectionFactory db)
    {
        if (_schemaCache.schema is not null &&
            DateTime.UtcNow - _schemaCache.fetchedAt < SchemaTtl)
        {
            return _schemaCache.schema;
        }

        try
        {
            using var conn = db.CreateConnection();
            var migrationId = await conn.ExecuteScalarAsync<string?>(@"
                IF OBJECT_ID('dbo.__EFMigrationsHistory','U') IS NOT NULL
                    SELECT TOP 1 MigrationId FROM dbo.__EFMigrationsHistory ORDER BY MigrationId DESC;
                ELSE
                    SELECT CAST(NULL AS NVARCHAR(150));");

            lock (SchemaLock)
            {
                _schemaCache = (migrationId, DateTime.UtcNow);
            }
            return migrationId;
        }
        catch
        {
            return null;
        }
    }

    private static VersionInfoStatic LoadStatic()
    {
        var asm = Assembly.GetExecutingAssembly();
        var info = asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0";
        var fileVer = asm.GetName().Version?.ToString(3) ?? "0.0.0";
        var sha = info.Contains('+') ? info.Split('+', 2)[1] : null;
        var buildDate = asm.GetCustomAttributes<AssemblyMetadataAttribute>()
                           .FirstOrDefault(a => a.Key == "BuildDate")?.Value;
        return new VersionInfoStatic(fileVer, info, sha, buildDate);
    }

    private sealed record VersionInfoStatic(string AppVersion, string Informational, string? GitSha, string? BuildDate);
}
