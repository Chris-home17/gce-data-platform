---
name: access-control-guardian
description: >
  Access control and data-scoping reviewer for the GCE Data Platform admin app (frontend
  AND backend). Trigger this skill whenever the user asks to audit, review, or check
  access control, RBAC, permission gating, or data scoping; when adding or modifying any
  page/table/query that fetches entity lists; when wiring action buttons that mutate data;
  when adding a new backend endpoint or changing an existing one's authorization; or when
  the user asks "is this view scoped to the current account?", "is this action gated?",
  "why is the user seeing data from other accounts?", or "should this endpoint require
  kpi.admin or kpi.assign?". Also trigger on PR reviews that touch `useQuery` / `api.*`
  calls, `useAccount()`, `usePermissions()`, `PERMISSIONS.*`, navigation/sidebar visibility,
  `HasPermissionAsync` / `HasAnyPermissionAsync`, `AccessScope`, or any `Endpoints/*.cs`
  file. Produces a structured scoping + gating checklist covering both layers.
---

# Access Control Guardian — GCE Data Platform

This skill reviews new and modified code for correct account scoping and permission
gating across **both** the Next.js frontend and the ASP.NET Core backend. Visual design
review lives in `design-system-guardian`; this one is strictly about authorization and
data boundaries.

Two recurring bug classes this skill exists to prevent:

1. **Unscoped frontend `api.*.list()` calls** that hand a tenant-level user every
   account's data instead of their own.
2. **Unscoped backend endpoints** that return or mutate rows without checking whether
   the caller can see the target account / user / site.

## Permission registry (keep both sides in sync)

### Frontend — `src/types/api.ts`

```ts
PERMISSIONS = {
  SUPER_ADMIN:           'platform.super_admin',
  ACCOUNTS_MANAGE:       'accounts.manage',
  USERS_MANAGE:          'users.manage',
  GRANTS_MANAGE:         'grants.manage',
  KPI_ADMIN:             'kpi.admin',    // library / periods / packages (strict superset)
  KPI_ASSIGN:            'kpi.assign',   // assignments / submission unlock (account-scoped)
  POLICIES_MANAGE:       'policies.manage',
  PLATFORM_ROLES_MANAGE: 'platform_roles.manage',
}
```

### Backend — `Services/PlatformAuthService.cs` (`Permissions` static class)

```csharp
public const string SuperAdmin          = "platform.super_admin";
public const string AccountsManage      = "accounts.manage";
public const string UsersManage         = "users.manage";
public const string GrantsManage        = "grants.manage";
public const string KpiAdmin            = "kpi.admin";
public const string KpiAssign           = "kpi.assign";
public const string PoliciesManage      = "policies.manage";
public const string PlatformRolesManage = "platform_roles.manage";
```

Rules:
- Reference via the constant (`PERMISSIONS.X` / `Permissions.X`), never hardcode the
  string literal.
- Adding a new code? Update BOTH sides, plus the `App.PlatformPermission` seed in
  `database/ddl/tables/baseline_create.sql` AND the EF migration that inserts it
  (see `database-migration-author`).
- `kpi.admin` is a **strict superset** of `kpi.assign`. Every `kpi.assign` check must
  also accept `kpi.admin` — use the array / `HasAnyPermissionAsync` patterns below.

## Frontend primitives — know these cold

### `usePermissions()` — `src/hooks/usePermissions.ts`

```tsx
const { can, isSuperAdmin, permissions, userId } = usePermissions()

can(PERMISSIONS.USERS_MANAGE)    // true if user has the code OR is SUPER_ADMIN
isSuperAdmin                      // true only if user has 'platform.super_admin'
```

- **Never** compare `permissions.includes(...)` directly — always use `can(...)` so
  super-admins auto-pass.
- `isSuperAdmin` gates platform-wide aggregation views (All Accounts, All Users, BI
  Reports, Coverage, Shared Geography, Source Mapping).

### `useAccount()` — `src/contexts/account-context.tsx`

```tsx
const { accounts, selectedAccount, isLoading, selectAccount } = useAccount()
selectedAccount?.accountId
```

- `selectedAccount` is `undefined` while loading — account-scoped queries MUST set
  `enabled: !!selectedAccount?.accountId`.
- Persists to `localStorage` under `gce:selectedAccountId`. Sign-out MUST clear this
  key (`topbar.tsx` `handleSignOut`) AND call `queryClient.clear()`.

### `useAccessibleSites()` — `src/hooks/useAccessibleSites.ts`

```tsx
const accessible = useAccessibleSites()
// accessible.mode === 'all'     -> super-admin; no filter
// accessible.mode === 'scoped'  -> filter rows by accessible.siteCodes: Set<string>
```

Use this when the backend returns account-level data but the UI must hide sites the
caller can't reach (see `kpi/assignments/page-client.tsx` for the canonical pattern:
scope dropdown options AND row filters pass through `isSiteAccessible`).

### `<PermissionGate>` — `src/components/shared/permission-gate.tsx`

```tsx
<PermissionGate permission={PERMISSIONS.ACCOUNTS_MANAGE}>
  <Button onClick={onCreate}>Create Account</Button>
</PermissionGate>
```

Canonical way to gate **write-oriented UI** (buttons, dropdown items, dialog triggers).
Read-oriented gating (whole pages, tabs) uses `can(...)` directly at the top of the
page component.

### Route permissions — `src/lib/route-permissions.ts`

Single source for "what permission does URL X need". Supports single code or array
("any of") for the KPI split pattern:

```ts
export type RequiredPermission = Permission | readonly Permission[]

{ prefix: '/kpi/definitions', permission: PERMISSIONS.KPI_ADMIN },
{ prefix: '/kpi/assignments', permission: [PERMISSIONS.KPI_ASSIGN, PERMISSIONS.KPI_ADMIN] },

// Consumers use the predicate, NOT can() directly:
hasRequiredPermission(required, can)
```

- `admin-shell.tsx` uses `hasRequiredPermission` for the route guard.
- `sidebar.tsx` uses the same predicate for visibility, and `NavItem.permission` accepts
  `RequiredPermission`.
- **If you add a route that needs "A or B" gating, use the array form** — don't
  duplicate the check with two separate prefixes.

## Backend primitives — know these cold

### `PlatformAuthService` — `Services/PlatformAuthService.cs`

```csharp
// Single-permission check (super-admin bypass built in).
await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin);

// "Any of" check — use for kpi.assign endpoints so kpi.admin also satisfies them.
await platformAuth.HasAnyPermissionAsync(user, conn,
    Permissions.KpiAssign, Permissions.KpiAdmin);
```

Rules:
- Dev-bypass (`ClaimsPrincipal.Identity.AuthenticationType == "DevBypass"`) returns all
  permissions without a DB call. Gated behind `app.Environment.IsDevelopment()` in
  `Program.cs`.
- `HasAnyPermissionAsync` is the **only** correct check for endpoints that should
  accept any of multiple codes.

### `AccessScope` — `Helpers/AccessScope.cs`

Two primitives for tenant scoping of non-super-admin list/detail endpoints:

```csharp
// Resolves the caller's Sec.[User].UserId from their UPN claim.
var callerId = await AccessScope.GetCurrentUserIdAsync(user, conn);

// Reusable CTE that defines AccessibleAccounts(AccountId) for @UserId.
var sql = AccessScope.AccessibleAccountsCte + @"
    SELECT ... FROM App.vKpiAssignments
    WHERE AccountId IN (SELECT AccountId FROM AccessibleAccounts)";

// Helper for /users/{id}/* sub-resources.
await AccessScope.CanAccessUserAsync(conn, callerId.Value, targetUserId);
```

Pattern for every list endpoint that returns tenant-scoped data:

```csharp
if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
{
    // unfiltered query
}
else
{
    var callerId = await AccessScope.GetCurrentUserIdAsync(user, conn);
    if (callerId is null) return Results.Ok(new ApiList<T>(..., 0));
    var sql = AccessScope.AccessibleAccountsCte + @"
        SELECT ... WHERE AccountId IN (SELECT AccountId FROM AccessibleAccounts)";
    // ... with new { UserId = callerId.Value }
}
```

For `/{id}/*` detail endpoints that take a user ID, wrap with
`AccessScope.CanAccessUserAsync` and 404 on a miss so you don't leak existence.
`UserEndpoints.cs` `RequireUserAccessAsync` is the canonical helper — reuse it; don't
re-implement.

## The three levels of data scoping (frontend)

### Level 1 — Account-scoped (the default)

```tsx
const { selectedAccount } = useAccount()
const { data, isLoading } = useQuery({
  queryKey: ['accounts', selectedAccount?.accountId, 'users'],
  queryFn: () => api.accounts.users(selectedAccount!.accountId),
  enabled: !!selectedAccount?.accountId,
})
```

- `queryKey` includes `selectedAccount?.accountId` so it re-fetches on account switch.
- Use the scoped endpoint (`api.accounts.users(id)`), not `api.users.list()`.
- Mutations invalidate the scoped key, not just the global one.

### Level 2 — Platform-wide (Super Admin only)

```tsx
const { isSuperAdmin } = usePermissions()
const { data } = useQuery({
  queryKey: ['users'],
  queryFn: () => api.users.list(),
  enabled: isSuperAdmin,
})
if (!isSuperAdmin) return <NotFound />
```

- Page-level guard BEFORE any unscoped `api.*.list()` call.
- Sidebar entry MUST have the matching `permission` prop.
- Account filtering on a platform view uses its own dropdown (see
  `kpi/assignments/page-client.tsx`), NOT `useAccount().selectedAccount`.

### Level 3 — User-self (the signed-in user's own data)

```tsx
const { userId } = usePermissions()
const { data } = useQuery({
  queryKey: ['users', userId, 'effective-access'],
  queryFn: () => api.users.effectiveAccess(userId!),
  enabled: !!userId,
})
```

- Never accept a user ID from URL/props when the page means "my" data — read
  `usePermissions().userId` so the user can't impersonate.

## KPI permission split — the canonical example

| Surface | Permission |
|---|---|
| `/kpi/definitions`, `/kpi/periods`, `/kpi/packages` (authoring) | `kpi.admin` only |
| `/kpi/assignments` (route guard + sidebar) | `[kpi.assign, kpi.admin]` |
| Backend: Definitions / Period Schedules / Periods / Packages mutations | `HasPermissionAsync(..., KpiAdmin)` |
| Backend: Assignment templates / materialize / direct create / submission unlock / package→assign-templates | `HasAnyPermissionAsync(..., KpiAssign, KpiAdmin)` |

Rule: **if an endpoint or route is `kpi.assign`-gated, it must ALSO accept `kpi.admin`**
— the admin permission is a strict superset. This is encoded via `HasAnyPermissionAsync`
on the backend and via the `RequiredPermission` array on the frontend.

## Endpoint surface — which API to call (frontend)

| Scoped endpoint (Level 1) | Unscoped endpoint (Level 2) |
|---|---|
| `api.accounts.users(accountId)` | `api.users.list()` |
| `api.roles.list({ accountId })` | `api.roles.list()` |
| `api.kpi.assignments.list({ accountId })` | `api.kpi.assignments.list()` |
| `api.kpi.monitoring.list({ accountId, periodId })` | — |

**If you reach for the unscoped variant on a page a non-super-admin can reach, that's
the bug.** Switch to the scoped variant with `selectedAccount.accountId` OR add a
page-level `isSuperAdmin` gate AND update the sidebar permission.

## Sign-out cache hygiene

`topbar.tsx` `handleSignOut` must:

```tsx
queryClient.clear()
localStorage.removeItem('gce:selectedAccountId')
await signOut({ redirectTo: '/login' })
```

And `lib/api.ts` has a global 401 handler with a single-fire latch: on `401`, calls
`signOut({ callbackUrl: '/login' })` unless already on `/login`. Don't duplicate that
logic in per-query error handlers.

## Review Checklist

### Frontend — Page-level gating
- [ ] Account-scoped pages resolve `selectedAccount` and gate initial render on `isLoading`
- [ ] Platform-wide pages check `isSuperAdmin` (or the platform permission) at top of component with an early return
- [ ] Detail routes verify the user can see this entity (scoped endpoint returning 404, or explicit `can(...)`)
- [ ] "My data" routes read `userId` from `usePermissions()`, never from URL params
- [ ] Routes needing "any of" gating use the `RequiredPermission` array form and `hasRequiredPermission(required, can)`

### Frontend — Queries (`useQuery`)
- [ ] Account-scoped queries include `selectedAccount?.accountId` in `queryKey`
- [ ] Account-scoped queries set `enabled: !!selectedAccount?.accountId`
- [ ] Account-scoped queries call `api.accounts.X(id)` or `api.X.list({ accountId })`, NOT `api.X.list()`
- [ ] Platform-wide queries set `enabled: isSuperAdmin` (or relevant `can(...)`)
- [ ] User-self queries key on `userId` with `enabled: !!userId`
- [ ] Site-scoped UI narrowing (below account level) uses `useAccessibleSites()` and passes BOTH dropdown options AND row rendering through the predicate

### Frontend — Mutations
- [ ] Mutations invalidate the scoped query keys, not only the global one
- [ ] Account-level mutations invalidate `['accounts', accountId]` and `['accounts', accountId, <entity>]`
- [ ] Cross-account writes wrapped in `<PermissionGate>` or guarded inline with `can(PERMISSIONS.X)`

### Frontend — UI gating
- [ ] Create / Edit / Delete / Onboard buttons use `<PermissionGate>` or inline `can(PERMISSIONS.X) ? ... : null`
- [ ] `<RowActions onToggle>` only rendered when the user can manage the entity
- [ ] Destructive actions inside `<ConfirmDialog>` still require a permission gate on the trigger
- [ ] No hardcoded permission strings — use `PERMISSIONS.X`
- [ ] No `permissions.includes(...)` — use `can(...)` so super-admins auto-pass

### Frontend — Sidebar & navigation
- [ ] Nav items for platform-scoped pages have `permission` in `NAV_SECTIONS`
- [ ] Nav items for "any-of" routes set `permission` to the matching array (see KPI Assignments)
- [ ] Visibility changes paired with a page-level guard — hiding alone is never an authorization control
- [ ] `admin-shell.tsx` and `sidebar.tsx` both route through `hasRequiredPermission(required, can)` — no duplicated `Array.isArray` branches

### Backend — Permission gating
- [ ] Every mutation endpoint calls `HasPermissionAsync` or `HasAnyPermissionAsync` BEFORE any DB write
- [ ] `kpi.assign` endpoints use `HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin)` — never `HasPermissionAsync(..., KpiAssign)` alone
- [ ] Read endpoints that return multi-tenant data branch on `SuperAdmin` and filter non-admins through `AccessScope.AccessibleAccountsCte`
- [ ] `/users/{id}/*` sub-resources go through `RequireUserAccessAsync` (or equivalent `CanAccessUserAsync` gate) to prevent ID enumeration
- [ ] 404 (not 403) on scope misses so callers cannot distinguish "doesn't exist" from "outside your scope"

### Backend — Scoping SQL
- [ ] `AccessScope.AccessibleAccountsCte` is prepended (not inlined / copy-pasted); `@UserId` is supplied as a Dapper parameter
- [ ] Views that expose `AccountId` filter on `AccountId IN (SELECT AccountId FROM AccessibleAccounts)`
- [ ] Views that only expose `AccountCode` join through `Dim.Account` and filter on `AccountId IN ...`
- [ ] SQL is parameterised — no string interpolation of user input into a query
- [ ] Site-level gating on a single-resource endpoint verifies `Dim.OrgUnit.AccountId IN AccessibleAccounts` before returning data

### Config
- [ ] `appsettings.json` sets `"ValidateAudience": true` (base); only `appsettings.Development.json` overrides to `false` for dev-bypass
- [ ] Dev-bypass middleware in `Program.cs` is wrapped in `if (app.Environment.IsDevelopment())`
- [ ] Frontend `DEV_BYPASS` flows through `lib/dev-bypass.ts` (requires `NODE_ENV !== 'production'`); `next.config.mjs` build-time guard rejects prod builds with the flag set

## Common anti-patterns to grep for

### Frontend
| Pattern | Why it's a red flag |
|---|---|
| `api.users.list()` in a non-super-admin page | Unscoped list |
| `api.roles.list()` (no args) | Usually should be `api.roles.list({ accountId })` |
| `'kpi.manage'` string literal | Legacy code — split into `kpi.admin` / `kpi.assign` |
| `PERMISSIONS.KPI_MANAGE` | Legacy constant — removed in Apr 2026 |
| `permissions.includes(` | Use `can(...)` so super-admins auto-pass |
| `queryKey: ['users']` on a non-super-admin page | Global key on scoped data |
| `process.env.NEXT_PUBLIC_DEV_BYPASS === 'true'` (direct) | Use `DEV_BYPASS` from `lib/dev-bypass.ts` |

### Backend
| Pattern | Why it's a red flag |
|---|---|
| `Permissions.KpiManage` | Legacy constant — removed |
| `HasPermissionAsync(..., Permissions.KpiAssign)` without `KpiAdmin` | Missing the superset — use `HasAnyPermissionAsync` |
| `Results.NotFound()` (no `ApiError` body) | Breaks the frontend `{code, message}` parser |
| Inline CTE copied from `AccountEndpoints.cs` | Should use `AccessScope.AccessibleAccountsCte` |
| `app.MapGet("...", async (...) =>` with no `Permissions.` check inside a mutation-style path | Unauthorized write |
| `user.FindFirst(ClaimTypes.Email)?.Value ?? user.FindFirst(ClaimTypes.Name)?.Value` | Bypasses `PlatformAuthService.GetUpn` precedence — use the static helper |

## Key file locations

| Resource | Path |
|---|---|
| Frontend permission enum | `frontend/src/types/api.ts` (top) |
| `usePermissions` | `frontend/src/hooks/usePermissions.ts` |
| `useAccount` | `frontend/src/contexts/account-context.tsx` |
| `useAccessibleSites` | `frontend/src/hooks/useAccessibleSites.ts` |
| `<PermissionGate>` | `frontend/src/components/shared/permission-gate.tsx` |
| Route → permission map | `frontend/src/lib/route-permissions.ts` |
| Admin shell guard | `frontend/src/app/(admin)/admin-shell.tsx` |
| Sidebar + nav | `frontend/src/components/layout/sidebar.tsx` |
| Topbar / sign-out cleanup | `frontend/src/components/layout/topbar.tsx` |
| Global 401 handler | `frontend/src/lib/api.ts` (`handleUnauthorized`) |
| Dev bypass guard | `frontend/src/lib/dev-bypass.ts` · `frontend/next.config.mjs` |
| Canonical scoped-vs-global table | `frontend/src/app/(admin)/users/users-table.tsx` (`UserTableContent`) |
| Canonical site-level UI narrowing | `frontend/src/app/(admin)/kpi/assignments/page-client.tsx` |
| Backend `Permissions` constants | `backend/GcePlatform.Api/Services/PlatformAuthService.cs` |
| Backend scoping helper | `backend/GcePlatform.Api/Helpers/AccessScope.cs` |
| Canonical scoped list endpoint | `backend/GcePlatform.Api/Endpoints/AccountEndpoints.cs` |
| Canonical `/{id}/*` gating | `backend/GcePlatform.Api/Endpoints/UserEndpoints.cs` (`RequireUserAccessAsync`) |
| Canonical `HasAnyPermissionAsync` usage | `backend/GcePlatform.Api/Endpoints/KpiSubmissionEndpoints.cs` |
