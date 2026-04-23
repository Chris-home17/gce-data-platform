using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class KpiPeriodEndpoints
{
    public static WebApplication MapKpiPeriodEndpoints(this WebApplication app)
    {
        app.MapGet("/kpi/period-schedules", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<KpiPeriodScheduleDto>(@"
                SELECT
                    PeriodScheduleId,
                    ExternalId,
                    ScheduleName,
                    FrequencyType,
                    FrequencyInterval,
                    StartDate,
                    EndDate,
                    SubmissionOpenDay,
                    SubmissionCloseDay,
                    GenerateMonthsAhead,
                    Notes,
                    IsActive,
                    GeneratedPeriodCount,
                    FirstGeneratedPeriodLabel,
                    LastGeneratedPeriodLabel
                FROM App.vKpiPeriodSchedules
                ORDER BY IsActive DESC, ScheduleName");

            var list = items.ToList();
            return Results.Ok(new ApiList<KpiPeriodScheduleDto>(list, list.Count));
        }).RequireAuthorization();

        app.MapPost("/kpi/period-schedules", async (ClaimsPrincipal user, CreateKpiPeriodScheduleRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            var p = new DynamicParameters();
            p.Add("@ScheduleName", request.ScheduleName);
            p.Add("@FrequencyType", request.FrequencyType);
            p.Add("@FrequencyInterval", request.FrequencyInterval);
            p.Add("@StartDate", request.StartDate);
            p.Add("@EndDate", request.EndDate);
            p.Add("@SubmissionOpenDay", request.SubmissionOpenDay);
            p.Add("@SubmissionCloseDay", request.SubmissionCloseDay);
            p.Add("@GenerateMonthsAhead", request.GenerateMonthsAhead);
            p.Add("@Notes", request.Notes);
            p.Add("@PeriodScheduleID", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertKpiPeriodSchedule", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@PeriodScheduleID");

            if (request.GenerateNow)
            {
                await conn.ExecuteAsync("App.usp_GenerateKpiPeriods",
                    new { PeriodScheduleID = newId },
                    commandType: System.Data.CommandType.StoredProcedure);
                await conn.ExecuteAsync("App.usp_MaterializeKpiAssignmentTemplates",
                    commandType: System.Data.CommandType.StoredProcedure);
            }

            var created = await conn.QuerySingleAsync<KpiPeriodScheduleDto>(@"
                SELECT
                    PeriodScheduleId,
                    ExternalId,
                    ScheduleName,
                    FrequencyType,
                    FrequencyInterval,
                    StartDate,
                    EndDate,
                    SubmissionOpenDay,
                    SubmissionCloseDay,
                    GenerateMonthsAhead,
                    Notes,
                    IsActive,
                    GeneratedPeriodCount,
                    FirstGeneratedPeriodLabel,
                    LastGeneratedPeriodLabel
                FROM App.vKpiPeriodSchedules
                WHERE PeriodScheduleId = @Id",
                new { Id = newId });

            return Results.Created($"/kpi/period-schedules/{newId}", created);
        }).RequireAuthorization();

        app.MapPost("/kpi/period-schedules/{id:int}/generate", async (ClaimsPrincipal user, int id, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            var exists = await conn.QuerySingleOrDefaultAsync<int?>(@"
                SELECT PeriodScheduleId
                FROM App.vKpiPeriodSchedules
                WHERE PeriodScheduleId = @Id",
                new { Id = id });

            if (exists is null)
                return Results.NotFound(new ApiError("PERIOD_SCHEDULE_NOT_FOUND", $"Period schedule {id} not found."));

            await conn.ExecuteAsync("App.usp_GenerateKpiPeriods",
                new { PeriodScheduleID = id },
                commandType: System.Data.CommandType.StoredProcedure);
            await conn.ExecuteAsync("App.usp_MaterializeKpiAssignmentTemplates",
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        app.MapMethods("/kpi/period-schedules/{id:int}/status", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, SetActiveRequest body, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();
            var item = await conn.QuerySingleOrDefaultAsync<KpiPeriodScheduleDto>(@"
                SELECT
                    PeriodScheduleId,
                    ExternalId,
                    ScheduleName,
                    FrequencyType,
                    FrequencyInterval,
                    StartDate,
                    EndDate,
                    SubmissionOpenDay,
                    SubmissionCloseDay,
                    GenerateMonthsAhead,
                    Notes,
                    IsActive,
                    GeneratedPeriodCount,
                    FirstGeneratedPeriodLabel,
                    LastGeneratedPeriodLabel
                FROM App.vKpiPeriodSchedules
                WHERE PeriodScheduleId = @Id",
                new { Id = id });

            if (item is null)
                return Results.NotFound(new ApiError("PERIOD_SCHEDULE_NOT_FOUND", $"Period schedule {id} not found."));

            await conn.ExecuteAsync("App.usp_SetKpiPeriodScheduleActive",
                new { PeriodScheduleID = id, body.IsActive },
                commandType: System.Data.CommandType.StoredProcedure);

            if (body.IsActive)
            {
                await conn.ExecuteAsync("App.usp_GenerateKpiPeriods",
                    new { PeriodScheduleID = id },
                    commandType: System.Data.CommandType.StoredProcedure);
                await conn.ExecuteAsync("App.usp_MaterializeKpiAssignmentTemplates",
                    commandType: System.Data.CommandType.StoredProcedure);
            }

            return Results.NoContent();
        }).RequireAuthorization();

        // GET /kpi/periods
        app.MapGet("/kpi/periods", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<KpiPeriodDto>(@"
                SELECT
                    PeriodId,
                    ExternalId,
                    PeriodScheduleId,
                    ScheduleName,
                    PeriodLabel,
                    PeriodYear,
                    PeriodMonth,
                    SubmissionOpenDate,
                    SubmissionCloseDate,
                    Status,
                    CAST(IsCurrentlyOpen AS bit) AS IsCurrentlyOpen,
                    DaysRemaining
                FROM App.vKpiPeriods
                ORDER BY PeriodYear DESC, PeriodMonth DESC");

            var list = items.ToList();
            return Results.Ok(new ApiList<KpiPeriodDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /kpi/periods/{id}
        app.MapGet("/kpi/periods/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<KpiPeriodDto>(@"
                SELECT
                    PeriodId,
                    ExternalId,
                    PeriodScheduleId,
                    ScheduleName,
                    PeriodLabel,
                    PeriodYear,
                    PeriodMonth,
                    SubmissionOpenDate,
                    SubmissionCloseDate,
                    Status,
                    CAST(IsCurrentlyOpen AS bit) AS IsCurrentlyOpen,
                    DaysRemaining
                FROM App.vKpiPeriods
                WHERE PeriodId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("PERIOD_NOT_FOUND", $"Period {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // POST /kpi/periods
        app.MapPost("/kpi/periods", async (ClaimsPrincipal user, CreateKpiPeriodRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            var p = new DynamicParameters();
            p.Add("@PeriodYear", request.PeriodYear);
            p.Add("@PeriodMonth", request.PeriodMonth);
            p.Add("@SubmissionOpenDate", request.SubmissionOpenDate);
            p.Add("@SubmissionCloseDate", request.SubmissionCloseDate);
            p.Add("@Notes", request.Notes);
            p.Add("@PeriodId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertKpiPeriod", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@PeriodId");

            var created = await conn.QuerySingleAsync<KpiPeriodDto>(@"
                SELECT PeriodId, ExternalId, PeriodScheduleId, ScheduleName, PeriodLabel, PeriodYear, PeriodMonth,
                       SubmissionOpenDate, SubmissionCloseDate, Status,
                       CAST(IsCurrentlyOpen AS bit) AS IsCurrentlyOpen,
                       DaysRemaining
                FROM App.vKpiPeriods
                WHERE PeriodId = @Id",
                new { Id = newId });

            return Results.Created($"/kpi/periods/{newId}", created);
        }).RequireAuthorization();

        // POST /kpi/periods/{id}/open
        app.MapPost("/kpi/periods/{id:int}/open", async (ClaimsPrincipal user, int id, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            await conn.ExecuteAsync("App.usp_OpenPeriod",
                new { PeriodId = id },
                commandType: System.Data.CommandType.StoredProcedure);

            var updated = await conn.QuerySingleOrDefaultAsync<KpiPeriodDto>(@"
                SELECT PeriodId, ExternalId, PeriodScheduleId, ScheduleName, PeriodLabel, PeriodYear, PeriodMonth,
                       SubmissionOpenDate, SubmissionCloseDate, Status,
                       CAST(IsCurrentlyOpen AS bit) AS IsCurrentlyOpen,
                       DaysRemaining
                FROM App.vKpiPeriods
                WHERE PeriodId = @Id",
                new { Id = id });

            return updated is null
                ? Results.NotFound(new ApiError("PERIOD_NOT_FOUND", $"Period {id} not found."))
                : Results.Ok(updated);
        }).RequireAuthorization();

        // POST /kpi/periods/{id}/close
        app.MapPost("/kpi/periods/{id:int}/close", async (ClaimsPrincipal user, int id, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            await conn.ExecuteAsync("App.usp_ClosePeriod",
                new { PeriodId = id },
                commandType: System.Data.CommandType.StoredProcedure);

            var updated = await conn.QuerySingleOrDefaultAsync<KpiPeriodDto>(@"
                SELECT PeriodId, ExternalId, PeriodScheduleId, ScheduleName, PeriodLabel, PeriodYear, PeriodMonth,
                       SubmissionOpenDate, SubmissionCloseDate, Status,
                       CAST(IsCurrentlyOpen AS bit) AS IsCurrentlyOpen,
                       DaysRemaining
                FROM App.vKpiPeriods
                WHERE PeriodId = @Id",
                new { Id = id });

            return updated is null
                ? Results.NotFound(new ApiError("PERIOD_NOT_FOUND", $"Period {id} not found."))
                : Results.Ok(updated);
        }).RequireAuthorization();

        return app;
    }
}
