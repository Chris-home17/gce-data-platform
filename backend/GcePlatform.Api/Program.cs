using System.Security.Claims;
using GcePlatform.Api.Data;
using GcePlatform.Api.Endpoints;
using GcePlatform.Api.Services;
using Microsoft.Identity.Web;
using Serilog;

// ---------------------------------------------------------------------------
// Bootstrap Serilog before anything else so startup errors are captured
// ---------------------------------------------------------------------------
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);

    // -----------------------------------------------------------------------
    // Logging — Serilog reads from appsettings Serilog section if present,
    // otherwise falls back to the bootstrap logger above.
    // -----------------------------------------------------------------------
    builder.Host.UseSerilog((ctx, services, cfg) =>
        cfg.ReadFrom.Configuration(ctx.Configuration)
           .ReadFrom.Services(services)
           .WriteTo.Console());

    // -----------------------------------------------------------------------
    // Authentication — Microsoft.Identity.Web validates the Bearer token
    // issued by Azure AD. ValidateAudience=false in DEV (see appsettings).
    // -----------------------------------------------------------------------
    builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration);
    builder.Services.AddAuthorization();

    // -----------------------------------------------------------------------
    // Data access
    // -----------------------------------------------------------------------
    builder.Services.AddSingleton<DbConnectionFactory>();

    // -----------------------------------------------------------------------
    // Platform auth (permission resolution)
    // -----------------------------------------------------------------------
    builder.Services.AddSingleton<PlatformAuthService>();

    // -----------------------------------------------------------------------
    // CORS — allow the Next.js dev server (and any configured origins in prod)
    // -----------------------------------------------------------------------
    var allowedOrigins = (builder.Configuration["CORS_ALLOWED_ORIGINS"] ?? "")
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    builder.Services.AddCors(options =>
    {
        options.AddDefaultPolicy(policy =>
            policy.WithOrigins(allowedOrigins)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials());
    });

    // -----------------------------------------------------------------------
    // Build
    // -----------------------------------------------------------------------
    var app = builder.Build();

    app.UseSerilogRequestLogging();
    app.UseCors();

    // In Development, accept the frontend's dev-bypass-token without JWT validation.
    // This avoids the Microsoft Graph token signature mismatch until a proper API
    // scope is configured in Azure AD.
    if (app.Environment.IsDevelopment())
    {
        app.Use(async (context, next) =>
        {
            var authHeader = context.Request.Headers["Authorization"].FirstOrDefault() ?? "";
            if (authHeader == "Bearer dev-bypass-token")
            {
                var claims = new[]
                {
                    new Claim(ClaimTypes.NameIdentifier, "dev-user-001"),
                    new Claim(ClaimTypes.Name, "Dev User"),
                    new Claim(ClaimTypes.Email, "dev@gce-platform.local"),
                };
                var identity = new ClaimsIdentity(claims, "DevBypass");
                context.User = new ClaimsPrincipal(identity);
            }
            await next();
        });
    }

    app.UseAuthentication();
    app.UseAuthorization();

    // -----------------------------------------------------------------------
    // Endpoints
    // -----------------------------------------------------------------------
    app.MapPlatformRoleEndpoints();
    app.MapAccountEndpoints();
    app.MapUserEndpoints();
    app.MapRoleEndpoints();
    app.MapPolicyEndpoints();
    app.MapPackageEndpoints();
    app.MapBiReportEndpoints();
    app.MapOrgUnitEndpoints();
    app.MapKpiPeriodEndpoints();
    app.MapKpiDefinitionEndpoints();
    app.MapKpiAssignmentEndpoints();
    app.MapKpiMonitoringEndpoints();
    app.MapKpiSubmissionEndpoints();
    app.MapKpiSubmissionTokenEndpoints();
    app.MapSourceMappingEndpoints();
    app.MapCoverageEndpoints();
    app.MapGrantEndpoints();
    app.MapDelegationEndpoints();

    // Health probe — useful for Container Apps liveness/readiness checks
    app.MapGet("/health", () => Results.Ok(new { status = "healthy" }))
       .AllowAnonymous();

    app.Run();
}
catch (Exception ex) when (ex.GetType().Name is not "HostAbortedException")
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}
