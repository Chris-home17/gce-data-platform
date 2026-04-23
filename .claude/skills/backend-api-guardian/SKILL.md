---
name: backend-api-guardian
description: >
  ASP.NET Core 8 minimal-API endpoint standards for the GCE Data Platform backend.
  Trigger this skill whenever the user adds, modifies, reviews, or audits anything under
  `backend/GcePlatform.Api/Endpoints/`; when the user asks "is this endpoint gated?",
  "should this be scoped to the account?", "how do I add a new endpoint?", or "what
  permission does this need?"; when wiring a new Dapper call, stored-procedure invocation,
  or batch operation; or when touching `Program.cs`, `PlatformAuthService`, `AccessScope`,
  `DbConnectionFactory`, or `appsettings*.json`. Covers permission gating (single + any-of),
  tenant scoping via `AccessScope`, `ApiError` response contract, Dapper parameterisation,
  batch caps, JWT `ValidateAudience`, dev-bypass safety, and `ClaimsPrincipal` UPN
  resolution. Produces a review checklist grounded in this repo's actual patterns.
---

# Backend API Guardian — GCE Data Platform

Use this skill when authoring or reviewing any file under
`backend/GcePlatform.Api/Endpoints/`, `Services/`, `Helpers/`, or `Program.cs`. The stack
is **.NET 8 minimal APIs + Dapper** for runtime data access; EF Core is used **only** for
migrations (see `database-migration-author`).

Three recurring bug classes this skill exists to prevent:

1. **Mutation endpoints with no permission gate** — any authenticated user can trigger a
   state change.
2. **Read endpoints that return cross-tenant data** when the caller is not a super-admin.
3. **Contract drift** — `Results.NotFound()` without an `ApiError` body, raw SQL
   concatenation, wrong claim-type UPN lookup, missing CORS / audience validation.

## Endpoint anatomy — the canonical shape

```csharp
app.MapPost("/thing/{id:int}", async (
    ClaimsPrincipal user,
    int id,
    ThingRequest req,
    DbConnectionFactory db,
    PlatformAuthService platformAuth) =>
{
    using var conn = db.CreateConnection();

    // 1. Permission gate — single OR any-of (see §Permission gating)
    if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
        return Results.Forbid();

    // 2. Input validation — early returns with ApiError bodies
    if (string.IsNullOrWhiteSpace(req.Name))
        return Results.BadRequest(new ApiError("NAME_REQUIRED", "Name is required."));

    // 3. Existence check (if updating a row)
    var exists = await conn.ExecuteScalarAsync<bool>(
        "SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM App.vThings WHERE ThingId = @Id) THEN 1 ELSE 0 END AS bit)",
        new { Id = id });
    if (!exists)
        return Results.NotFound(new ApiError("THING_NOT_FOUND", $"Thing {id} not found."));

    // 4. DB work via Dapper — parameterised, async
    var p = new DynamicParameters();
    p.Add("@Id", id);
    p.Add("@Name", req.Name);
    await conn.ExecuteAsync("App.usp_UpsertThing", p,
        commandType: System.Data.CommandType.StoredProcedure);

    // 5. Return the fresh state or NoContent
    return Results.NoContent();
}).RequireAuthorization();
```

Rules carried by this shape:
- Parameter order: `ClaimsPrincipal user` first (when auth is relevant), then route
  params, then the request body, then DI services last. Matches every existing endpoint.
- `RequireAuthorization()` on every endpoint (unless a token-based public route like
  `/kpi/submission-tokens/{id}`). `AllowAnonymous()` is only used on `/health`.
- Always `using var conn = db.CreateConnection();` and always `await` the DB call. Never
  open a connection outside a `using`; never block on a synchronous Dapper overload.

## Permission gating

### Single permission

```csharp
if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
    return Results.Forbid();
```

Use for endpoints that need exactly one code. Super-admin bypass is built in — don't add
a separate super-admin branch.

### Any-of (KPI split pattern)

```csharp
if (!await platformAuth.HasAnyPermissionAsync(user, conn,
        Permissions.KpiAssign, Permissions.KpiAdmin))
    return Results.Forbid();
```

Use for `kpi.assign` endpoints so `kpi.admin` (strict superset) also satisfies them.
`HasAnyPermissionAsync` takes `params string[] codes` and is the correct primitive —
never chain two `HasPermissionAsync` calls joined by `||`.

### Permission catalogue (current)

```csharp
Permissions.SuperAdmin          = "platform.super_admin"
Permissions.AccountsManage      = "accounts.manage"
Permissions.UsersManage         = "users.manage"
Permissions.GrantsManage        = "grants.manage"
Permissions.KpiAdmin            = "kpi.admin"    // library / periods / packages
Permissions.KpiAssign           = "kpi.assign"   // assignments / submission unlock
Permissions.PoliciesManage      = "policies.manage"
Permissions.PlatformRolesManage = "platform_roles.manage"
```

`Permissions.KpiManage` was removed in Apr 2026. Any reference is a rebase bug.

### Which permission for which endpoint?

| Operation | Permission |
|---|---|
| Account CRUD | `AccountsManage` (super-admin for creation of new tenants) |
| User CRUD + status | `UsersManage` |
| Grants + delegations + role-member add/remove | `GrantsManage` |
| Access-role policies | `PoliciesManage` |
| Platform roles (role definitions + permission assignment) | `PlatformRolesManage` |
| KPI Library, Periods/Schedules, Packages authoring | `KpiAdmin` |
| KPI Assignment templates / materialize / direct / status | `HasAnyPermissionAsync(KpiAssign, KpiAdmin)` |
| `POST /kpi/packages/{id}/assign-templates` | `HasAnyPermissionAsync(KpiAssign, KpiAdmin)` |
| `PATCH /kpi/submissions/{id}/unlock` | `HasAnyPermissionAsync(KpiAssign, KpiAdmin)` |
| BI Reports (per-account artifacts) | `AccountsManage` |
| `Dim.Package` catalog + shared-geo authoring + tags | `SuperAdmin` |

## Tenant scoping — `AccessScope`

`backend/GcePlatform.Api/Helpers/AccessScope.cs` is the canonical helper. Never inline a
copy of the CTE — use the constant.

### Canonical list-endpoint pattern

```csharp
app.MapGet("/kpi/monitoring", async (
    ClaimsPrincipal user,
    int? periodId,
    int? accountId,
    DbConnectionFactory db,
    PlatformAuthService platformAuth) =>
{
    using var conn = db.CreateConnection();

    const string baseSelect = @"
        SELECT ... FROM App.vSiteCompletionSummary
        WHERE (@PeriodId IS NULL OR PeriodId = @PeriodId)
          AND (@AccountId IS NULL OR AccountId = @AccountId)";

    IEnumerable<SiteCompletionDto> items;
    if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
    {
        items = await conn.QueryAsync<SiteCompletionDto>(
            baseSelect + " ORDER BY AccountCode, SiteCode",
            new { PeriodId = periodId, AccountId = accountId });
    }
    else
    {
        var callerId = await AccessScope.GetCurrentUserIdAsync(user, conn);
        if (callerId is null)
            return Results.Ok(new ApiList<SiteCompletionDto>(new List<SiteCompletionDto>(), 0));

        var sql = AccessScope.AccessibleAccountsCte + baseSelect +
                  " AND AccountId IN (SELECT AccountId FROM AccessibleAccounts)" +
                  " ORDER BY AccountCode, SiteCode";
        items = await conn.QueryAsync<SiteCompletionDto>(sql,
            new { PeriodId = periodId, AccountId = accountId, UserId = callerId.Value });
    }

    var list = items.ToList();
    return Results.Ok(new ApiList<SiteCompletionDto>(list, list.Count));
}).RequireAuthorization();
```

Rules:
- Branch on `SuperAdmin` via `HasPermissionAsync`. The `else` branch resolves the caller
  via `AccessScope.GetCurrentUserIdAsync` and filters through `AccessibleAccountsCte`.
- Pass `UserId = callerId.Value` alongside the other Dapper params.
- If the view exposes `AccountId` directly: filter with
  `AccountId IN (SELECT AccountId FROM AccessibleAccounts)`.
- If the view only exposes `AccountCode`: JOIN through `Dim.Account` and filter on
  `a.AccountId IN (SELECT AccountId FROM AccessibleAccounts)`.

### Single-resource gates

For `/{id}/*` endpoints that take a user ID, use `AccessScope.CanAccessUserAsync` — or
for `UserEndpoints.cs`, the canonical `RequireUserAccessAsync` helper at the top of the
file that returns `IResult?` (null = allowed, 404 = denied). Always 404 on a scope miss;
403 would leak existence.

For single-site gates, follow the pattern in `KpiSubmissionEndpoints.cs`
`GET /kpi/site-submissions`: resolve `callerId`, then check
`EXISTS (SELECT 1 FROM Dim.OrgUnit ou WHERE ou.OrgUnitId = @SiteOrgUnitId AND ou.AccountId IN (SELECT AccountId FROM AccessibleAccounts))`.

## Response contract — `ApiError`

Every non-success response MUST carry an `ApiError(Code, Message)` body so the frontend
parser at `lib/api.ts` can surface a useful message:

```csharp
return Results.NotFound(new ApiError("THING_NOT_FOUND", $"Thing {id} not found."));
return Results.BadRequest(new ApiError("INVALID_INPUT", "Name must be 1-200 chars."));
return Results.Conflict(new ApiError("DUPLICATE_CODE", "That code is already in use."));
```

Never return bare `Results.NotFound()` / `Results.BadRequest()`. Never hand-roll a
`Results.Problem(...)` for an API error — it produces a ProblemDetails shape the
frontend doesn't parse.

`Results.Forbid()` (no body) is the one acceptable exception — it's the standard .NET
403 and the frontend interprets status code alone.

## Dapper safety

```csharp
// ✅ Always parameterised
await conn.QueryAsync<T>("SELECT * FROM X WHERE Id = @Id", new { Id = id });

// ✅ DynamicParameters for output params / SP invocation
var p = new DynamicParameters();
p.Add("@AccountId", id);
p.Add("@NewId", dbType: System.Data.DbType.Int32,
                direction: System.Data.ParameterDirection.Output);
await conn.ExecuteAsync("App.usp_UpsertThing", p,
    commandType: System.Data.CommandType.StoredProcedure);

// ❌ Never concatenate user input into SQL
await conn.QueryAsync($"SELECT * FROM X WHERE Code = '{userCode}'");
```

Other rules:
- Use `Async` variants always (`QueryAsync`, `ExecuteAsync`, `QuerySingleOrDefaultAsync`,
  `ExecuteScalarAsync`, `QueryMultipleAsync`).
- Stored procedures go via `commandType: CommandType.StoredProcedure`, not text
  `EXEC sp_name @x, @y`, unless you specifically need `QueryMultipleAsync`.
- For count existence, use `SELECT CAST(CASE WHEN EXISTS (...) THEN 1 ELSE 0 END AS bit)`
  — cheaper than `SELECT COUNT(1)` on large tables.

## Batch endpoints — cap the work

Batches that iterate per item (no batch-wide transaction, partial success semantics by
design) MUST cap the total operations up front:

```csharp
const int MaxBatchOperations = 500;
var totalOps = distinctItems.Count * orgUnitCodes.Count;
if (totalOps > MaxBatchOperations)
    return Results.BadRequest(new ApiError(
        "BATCH_TOO_LARGE",
        $"This batch would create {totalOps} templates; the per-request cap is {MaxBatchOperations}."));
```

Rules:
- Account for multiplicative fan-out (items × sites, items × accounts) in the cap, not
  just the outer list size.
- Don't wrap a partial-success batch in a single transaction — that breaks the per-item
  duplicate-skip / error-report contract.
- If the endpoint is all-or-nothing, wrap in an explicit `BeginTransaction` with
  commit/rollback.

## UPN resolution — use `PlatformAuthService.GetUpn`

```csharp
// ✅ Canonical
var upn = PlatformAuthService.GetUpn(user);

// ❌ Wrong precedence — some endpoints did this historically; it misses preferred_username
var upn = user.FindFirst(ClaimTypes.Email)?.Value
       ?? user.FindFirst(ClaimTypes.Name)?.Value;
```

The static `GetUpn` tries `preferred_username` → `ClaimTypes.Email` → `ClaimTypes.Upn` →
`ClaimTypes.Name` in that order (matches Entra ID claim precedence). Using the wrong
precedence produces misleading results when `preferred_username` is present but email
isn't.

## Program.cs — what MUST be there

```csharp
builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration);
builder.Services.AddAuthorization();
builder.Services.AddSingleton<DbConnectionFactory>();
builder.Services.AddSingleton<PlatformAuthService>();

// CORS — allowed origins per appsettings; never AllowAnyOrigin()
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
    policy.WithOrigins(allowedOrigins).AllowAnyHeader().AllowAnyMethod()));

// Dev-bypass middleware — MUST be inside IsDevelopment()
if (app.Environment.IsDevelopment())
{
    app.Use(async (context, next) =>
    {
        var authHeader = context.Request.Headers["Authorization"].FirstOrDefault() ?? "";
        if (authHeader == "Bearer dev-bypass-token") { /* inject dev principal */ }
        await next();
    });
}
```

Rules:
- Dev-bypass block MUST remain inside the `IsDevelopment()` guard. Removing the guard
  would let any production caller inject a fake identity by sending the literal token.
- `AllowAnyOrigin()` is a bug — always use `WithOrigins(allowedOrigins)`.

## Config — JWT & secrets

`appsettings.json` (base):
```json
"AzureAd": { "ValidateAudience": true }
```

`appsettings.Development.json`:
```json
"AzureAd": { "ValidateAudience": false }   // dev-bypass-only override
```

`appsettings.Production.json`:
- MUST NOT override `ValidateAudience`. Inherits `true` from base.
- No `AzureAd` client secrets in this file — Azure App Service env vars supply them.
- No connection-string passwords — Active Directory Default auth is used.

## Review Checklist

### Permission gating
- [ ] Every mutation endpoint calls `HasPermissionAsync` or `HasAnyPermissionAsync` BEFORE the DB write
- [ ] `kpi.assign` endpoints use `HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin)`
- [ ] Permission strings are referenced via `Permissions.X` constants — no raw `"kpi.admin"` literals
- [ ] No references to the legacy `Permissions.KpiManage` constant
- [ ] `RequireAuthorization()` present on the endpoint (unless it's an explicitly public token-based route)

### Tenant scoping
- [ ] Read endpoints that return multi-tenant data branch on `SuperAdmin` and filter non-admins through `AccessScope.AccessibleAccountsCte`
- [ ] The CTE is pulled from `AccessScope` as a string — not inlined / copy-pasted
- [ ] `@UserId` is supplied as a Dapper parameter (never interpolated)
- [ ] `/{id}/*` sub-resources on `UserEndpoints` use `RequireUserAccessAsync`; other single-resource detail endpoints gate via `CanAccessUserAsync` or an equivalent `EXISTS` check
- [ ] Scope misses return 404 with an `ApiError` body (not 403)

### Response shape
- [ ] Every non-success response uses `new ApiError(Code, Message)` — no bare `Results.NotFound()`, `Results.BadRequest()`, or `Results.Problem(...)`
- [ ] Error codes follow `UPPER_SNAKE_CASE` and are descriptive (`THING_NOT_FOUND`, not `ERR_001`)
- [ ] Lists return `ApiList<T>(list, list.Count)`
- [ ] Creates return `Results.Created(path, dto)`; updates return `Results.NoContent()` or the updated DTO

### Dapper / SQL
- [ ] All SQL uses named parameters (`@Id`, `@Name`) — zero interpolation of user input
- [ ] All Dapper calls use `Async` variants
- [ ] Stored procedures invoked via `commandType: CommandType.StoredProcedure`
- [ ] Existence checks use `SELECT CAST(CASE WHEN EXISTS (...) THEN 1 ELSE 0 END AS bit)` over `COUNT(1)`

### Batch operations
- [ ] Partial-success batches cap total operations (`MaxBatchOperations = 500`) and return `BATCH_TOO_LARGE`
- [ ] All-or-nothing batches wrap in an explicit `IDbTransaction`
- [ ] Multiplicative fan-out (items × sites, items × accounts) is counted in the cap

### Claims
- [ ] UPN resolved via `PlatformAuthService.GetUpn(user)` — not a hand-rolled chain of `FindFirst` calls
- [ ] Parameter order: `ClaimsPrincipal user` first when auth is used, then route/body, then DI last

### Config
- [ ] `appsettings.json` has `"ValidateAudience": true`
- [ ] Only `appsettings.Development.json` sets it to `false`
- [ ] `appsettings.Production.json` does not re-override it
- [ ] No committed secrets or tenant-specific IDs in `appsettings.json` / `appsettings.Production.json`
- [ ] CORS uses `WithOrigins(allowedOrigins)` — never `AllowAnyOrigin()`

### Program.cs
- [ ] Dev-bypass middleware block is inside `if (app.Environment.IsDevelopment())`
- [ ] `AddMicrosoftIdentityWebApiAuthentication` + `AddAuthorization` present
- [ ] `DbConnectionFactory` and `PlatformAuthService` registered as Singletons

## Common anti-patterns to grep for

| Pattern | Why it's a red flag |
|---|---|
| `Permissions.KpiManage` | Legacy constant — removed Apr 2026 |
| `HasPermissionAsync(..., Permissions.KpiAssign)` (alone) | Missing the superset — must be `HasAnyPermissionAsync(..., KpiAssign, KpiAdmin)` |
| `Results.NotFound()` (no `ApiError`) | Breaks the frontend `{code, message}` parser |
| `Results.BadRequest()` without a body | Same — always pair with `ApiError` |
| `Results.Problem(...)` | Diverges from `ApiError` contract for routine errors |
| `$"SELECT ... '{user.Foo}'"` | SQL injection via interpolation |
| `app.MapPost("...", async (...) => { using var conn = ...; var p = ...; await conn.ExecuteAsync(...` with no `HasPermissionAsync` above | Unauthorized mutation |
| Inline `WITH UserGrants AS (...), AccessibleAccounts AS (...)` | Duplicate of `AccessScope.AccessibleAccountsCte` — reuse the constant |
| `user.FindFirst(ClaimTypes.Email)?.Value ?? user.FindFirst(ClaimTypes.Name)?.Value` | Wrong precedence; use `PlatformAuthService.GetUpn` |
| `AllowAnyOrigin()` | Production CORS bug |
| Dev-bypass string handling outside `IsDevelopment()` block | Production auth bypass |

## Key file locations

| Resource | Path |
|---|---|
| Minimal API bootstrap | `backend/GcePlatform.Api/Program.cs` |
| Permission constants + auth service | `backend/GcePlatform.Api/Services/PlatformAuthService.cs` |
| Tenant-scoping helper | `backend/GcePlatform.Api/Helpers/AccessScope.cs` |
| DB connection factory | `backend/GcePlatform.Api/Data/DbConnectionFactory.cs` |
| DTO catalog | `backend/GcePlatform.Api/Models/ApiModels.cs` |
| Endpoint files | `backend/GcePlatform.Api/Endpoints/*.cs` |
| Canonical gated mutation | `backend/GcePlatform.Api/Endpoints/AccountEndpoints.cs` (`POST /accounts`) |
| Canonical scoped list | `backend/GcePlatform.Api/Endpoints/KpiMonitoringEndpoints.cs` |
| Canonical `HasAnyPermissionAsync` + /{id} gate | `backend/GcePlatform.Api/Endpoints/KpiSubmissionEndpoints.cs` · `UserEndpoints.cs` |
| Canonical batch cap | `backend/GcePlatform.Api/Endpoints/KpiAssignmentEndpoints.cs` |
| Config (base) | `backend/GcePlatform.Api/appsettings.json` |
