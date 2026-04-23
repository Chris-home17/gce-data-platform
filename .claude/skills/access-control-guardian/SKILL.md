---
name: access-control-guardian
description: >
  Access control and data-scoping reviewer for the GCE Data Platform admin app.
  Trigger this skill whenever the user asks to audit, review, or check access control,
  RBAC, permission gating, or data scoping in the frontend; when adding or modifying any
  page/table/query that fetches entity lists; when wiring action buttons that mutate data;
  or when the user asks "is this view scoped to the current account?", "is this action
  gated?", or "why is the user seeing data from other accounts?". Also trigger on PR
  reviews that touch `useQuery` / `api.*` calls, `useAccount()`, `usePermissions()`, or
  navigation/sidebar visibility. Produces a structured scoping + gating checklist.
---

# Access Control Guardian — GCE Data Platform

Use this skill to review new and modified frontend code for correct account scoping and
permission gating. This is a **data / authorization** review, distinct from the visual
design review handled by `design-system-guardian`.

The recurring bug class this skill exists to prevent: **views that use an unscoped
`api.*.list()` call and display every account's data to a tenant-level user, when they
should only see the account they manage.** Every account-scoped query needs to pass
through `useAccount().selectedAccount.accountId`, and any super-admin-only aggregation
needs `usePermissions().isSuperAdmin` as an explicit precondition.

## Authorization primitives — know these cold

### `usePermissions()` — `src/hooks/usePermissions.ts`

```tsx
const { can, isSuperAdmin, permissions, userId } = usePermissions()

can(PERMISSIONS.USERS_MANAGE)    // true if user has the permission OR is SUPER_ADMIN
isSuperAdmin                      // true only if user has 'platform.super_admin'
```

- `can(...)` auto-grants to Super Admins — **never compare `permissions.includes(...)` directly**, always use `can(...)`
- `isSuperAdmin` is the right gate for platform-wide aggregation views (All accounts, All users, cross-tenant reports)

### `PERMISSIONS` enum — `src/types/api.ts`

```ts
PERMISSIONS = {
  SUPER_ADMIN:           'platform.super_admin',
  ACCOUNTS_MANAGE:       'accounts.manage',
  USERS_MANAGE:          'users.manage',
  GRANTS_MANAGE:         'grants.manage',
  KPI_MANAGE:            'kpi.manage',
  POLICIES_MANAGE:       'policies.manage',
  PLATFORM_ROLES_MANAGE: 'platform_roles.manage',
}
```

- **Always import and reference via `PERMISSIONS.X`** — never hardcode the string `'users.manage'` etc.
- New permission keys MUST be added to this object (and kept in sync with the backend `Permissions` class) before being referenced in UI

### `useAccount()` — `src/contexts/account-context.tsx`

```tsx
const { accounts, selectedAccount, isLoading, selectAccount } = useAccount()

selectedAccount?.accountId   // the ID to pass into every account-scoped query
```

- `selectedAccount` is `undefined` while loading — queries MUST be gated with `enabled: !!selectedAccount?.accountId`
- The switcher is in the dark sidebar (`layout/sidebar.tsx`) and persists to `localStorage` under `gce:selectedAccountId`
- **On sign-out, clear this key** (see `topbar.tsx:108-110` for the pattern) — stale selections after user swap are a real bug

### `<PermissionGate>` — `src/components/shared/permission-gate.tsx`

```tsx
<PermissionGate permission={PERMISSIONS.ACCOUNTS_MANAGE}>
  <Button onClick={onCreate}>Create Account</Button>
</PermissionGate>

// With fallback (e.g. a disabled state or a "request access" link)
<PermissionGate permission={PERMISSIONS.USERS_MANAGE} fallback={<span>Contact admin</span>}>
  <EditUserButton userId={id} />
</PermissionGate>
```

- The canonical way to gate **write-oriented UI** (buttons, dialogs, dropdown items)
- Read-oriented gating (whole pages, tabs) goes in the route/page component using `can(...)` directly — see `users/page.tsx:14,22`

## The three levels of data scoping

Every list/data query in the admin app falls into exactly one of these buckets. Ambiguity
here is the root cause of the "All accounts gives all the data" bug.

### Level 1 — Account-scoped (the default)

The user is managing a single tenant. The query MUST be keyed by `selectedAccount.accountId`
and MUST NOT run until the account is loaded.

```tsx
const { selectedAccount } = useAccount()

const { data, isLoading } = useQuery({
  queryKey: ['accounts', selectedAccount?.accountId, 'users'],
  queryFn: () => api.accounts.users(selectedAccount!.accountId),
  enabled: !!selectedAccount?.accountId,
})
```

Rules:
- `queryKey` includes `selectedAccount?.accountId` so React Query **re-fetches on account switch**
- `enabled: !!selectedAccount?.accountId` — no fetch before the account is known
- Use the scoped endpoint (`api.accounts.users(id)`), **not** the unscoped one (`api.users.list()`)
- Mutations invalidate the full scoped key: `invalidateKeys={[['accounts', accountId, 'users']]}` — not the unscoped `[['users']]`

### Level 2 — Platform-wide (Super Admin only)

Aggregated views across tenants (All Accounts, All Users, platform roles, source mapping,
coverage, shared geography). These use the unscoped endpoints.

```tsx
const { isSuperAdmin } = usePermissions()

const { data, isLoading } = useQuery({
  queryKey: ['users'],                         // no accountId in the key — this is global
  queryFn: () => api.users.list(),
  enabled: isSuperAdmin,                       // do not fetch for non-super-admins
})

if (!isSuperAdmin) return <NotFound />         // or redirect, or render a "no access" card
```

Rules:
- Page-level guard with `isSuperAdmin` (or the appropriate `can(PERMISSIONS.X)` for a
  platform permission like `PLATFORM_ROLES_MANAGE`) MUST come before any unscoped `api.*.list()` call
- Sidebar entry MUST be gated (`permission: PERMISSIONS.X` on the `NAV_SECTIONS` item in `layout/sidebar.tsx`)
- If a super-admin wants to see one account's slice of a platform view, the filter must use
  the account dropdown, never the `useAccount()` selectedAccount — the sidebar switcher is
  for tenant-context work, not platform-context work

### Level 3 — User-self (the current signed-in user's own data)

My profile, my KPI submissions, my effective access. Keyed by `usePermissions().userId`.

```tsx
const { userId } = usePermissions()

const { data } = useQuery({
  queryKey: ['users', userId, 'effective-access'],
  queryFn: () => api.users.effectiveAccess(userId!),
  enabled: !!userId,
})
```

Rules:
- Never accept a `userId` from the URL or props when the page is meant to show "my" data —
  read it from the session via `usePermissions().userId` so the user can't impersonate
- URL-driven detail pages (`/users/[id]`) are Level 1 or Level 2 depending on the caller's permission

## Endpoint surface — which API to call

The `api` surface in `src/lib/api.ts` already encodes scoping at the URL level. The rule is:
**use the scoped endpoint whenever the user is tenant-context; use the unscoped endpoint
only when the user has the platform permission for that view.**

| Scoped endpoint (Level 1) | Unscoped endpoint (Level 2) |
|---|---|
| `api.accounts.users(accountId)` | `api.users.list()` |
| `api.roles.list({ accountId })` | `api.roles.list()` |
| `api.kpi.assignments.list({ accountId })` | `api.kpi.assignments.list()` |
| `api.kpi.monitoring.list({ accountId, periodId })` | — |
| `api.sites.list({ accountId })` | — |

**If you find yourself reaching for the unscoped variant in a page that a non-super-admin
can reach, that's the bug.** Either:
1. Switch to the scoped variant with `selectedAccount.accountId`, OR
2. Add a page-level `isSuperAdmin` gate (Level 2) and update the sidebar permission

## Sidebar visibility

`NAV_SECTIONS` in `src/components/layout/sidebar.tsx` is the source of truth for who can
see what. Every nav item that links to a platform-wide page MUST have a `permission` entry.

```tsx
{ label: 'Platform Roles', href: '/platform-roles', icon: ShieldCheck,
  permission: PERMISSIONS.SUPER_ADMIN },
```

Rules:
- Account-scoped pages (Level 1) may omit `permission` if every user of the selected
  account should see them — `Dashboard`, `Users`, `Org Structure`, `KPI Monitoring`
  follow this pattern
- Platform-scoped pages (Level 2) MUST set `permission` to a platform-level key —
  `SUPER_ADMIN`, `PLATFORM_ROLES_MANAGE`, etc.
- Visibility ≠ authorization. A hidden nav item is NOT a security control — the page
  itself MUST still refuse to render / refuse to fetch for users without permission

## Mutations and cache invalidation

Every mutation that changes scoped data MUST invalidate the scoped query keys, not just
the global ones. This is why `UserTableContent` in `users-table.tsx` accepts an
`invalidateKeys` prop — the same component is reused across a global listing and a
per-account listing, and each flavour needs its own keys invalidated.

```tsx
// Global listing (Super Admin only)
<UserTableContent queryKey={['users']} invalidateKeys={[['users']]} />

// Per-account listing
<UserTableContent
  queryKey={['accounts', accountId, 'users']}
  invalidateKeys={[['users'], ['accounts'], ['accounts', accountId], ['accounts', accountId, 'users']]}
/>
```

Rules:
- An account-scoped mutation invalidates: the scoped list key, the account's summary keys,
  and any global keys that could otherwise cache stale counts
- Sign-out MUST call `queryClient.clear()` (see `topbar.tsx:107`) — leaving cache across
  users is a privacy bug
- Account switch does NOT need `queryClient.clear()` because query keys already include
  `accountId` — but DO verify every account-scoped `useQuery` actually includes it in the key

## Review Checklist

### Page-level gating
- [ ] Account-scoped pages resolve `selectedAccount` from `useAccount()` and gate the initial render on `isLoading`
- [ ] Platform-wide pages check `isSuperAdmin` (or the platform permission) at the top of the component and early-return otherwise
- [ ] Detail routes (`/entity/[id]`) verify the user can see this entity — either via scoped endpoint that returns 404 for unauthorized, or an explicit `can(...)` check
- [ ] Routes that show "my" data (profile, my submissions) read `userId` from `usePermissions()`, never from URL params

### Queries (`useQuery`)
- [ ] Account-scoped queries include `selectedAccount?.accountId` in `queryKey`
- [ ] Account-scoped queries set `enabled: !!selectedAccount?.accountId`
- [ ] Account-scoped queries call `api.accounts.X(id)` or `api.X.list({ accountId })`, **not** `api.X.list()` without a filter
- [ ] Platform-wide queries set `enabled: isSuperAdmin` (or the relevant `can(...)` result) so non-super-admins never trigger the fetch
- [ ] User-self queries key on `userId` from `usePermissions()`, with `enabled: !!userId`
- [ ] No `useQuery` uses an unscoped endpoint on a page reachable by non-super-admins without an explicit `can(...)` gate

### Mutations
- [ ] Every mutation invalidates the **scoped** query keys, not only the global one
- [ ] Mutations that modify account-level entities invalidate `['accounts', accountId]` and `['accounts', accountId, <entity>]`
- [ ] Cross-account writes (Super Admin only) are gated with `<PermissionGate>` or `can(PERMISSIONS.X)` before the UI renders

### Action buttons & UI gating
- [ ] Create / Edit / Delete / Onboard buttons are wrapped in `<PermissionGate permission={PERMISSIONS.X}>` OR gated inline with `can(PERMISSIONS.X) ? ... : null` (see `users/page.tsx:22`)
- [ ] `<RowActions onToggle>` mutations are only rendered when the user can manage the entity
- [ ] Destructive actions inside `<ConfirmDialog>` still require a permission gate on the trigger — the dialog is not an authorization layer
- [ ] Hardcoded permission strings (`'users.manage'`) are replaced with `PERMISSIONS.USERS_MANAGE`
- [ ] `permissions.includes(...)` direct comparisons are replaced with `can(...)` so super-admins auto-pass

### Sidebar & navigation
- [ ] Nav items for platform-scoped pages have a `permission` entry in `NAV_SECTIONS`
- [ ] Nav item visibility changes are paired with a page-level `can(...)` / `isSuperAdmin` check — hiding alone is not enough
- [ ] Account switcher: no page reads `selectedAccount` for platform-scoped work (e.g. a super-admin filtering `/users` should use a page-level account filter, not the sidebar switcher)

### Session & cache hygiene
- [ ] Sign-out calls `queryClient.clear()` AND removes `gce:selectedAccountId` from `localStorage` (see `topbar.tsx:107-110`)
- [ ] No code persists entity IDs into `localStorage` without namespacing by user/account
- [ ] No code writes the user's permissions into `localStorage` — always read from the live session

### Endpoint choice
- [ ] List pages use the scoped endpoint variant whenever tenant-context is available
- [ ] Unscoped endpoints appear only in files gated behind a platform permission
- [ ] New endpoints added to `api.ts` that return multi-tenant data have both a scoped and an unscoped variant where appropriate (follow `api.roles.list({ accountId })` as the model)

## Common anti-patterns to grep for

When auditing, run these searches across `frontend/src/`:

| Pattern | Why it's a red flag |
|---|---|
| `api.users.list()` | Unscoped user list — only valid for Super Admin pages |
| `api.roles.list()` (no args) | Unscoped roles list — usually should be `api.roles.list({ accountId })` |
| `useQuery` without `selectedAccount` or `isSuperAdmin` in the same file | Likely missing scoping or platform gate |
| `permissions.includes(` | Raw check — use `can(...)` so super-admins auto-pass |
| `'users.manage'` / `'kpi.manage'` string literals | Hardcoded permission — use `PERMISSIONS.X` |
| `queryKey: ['users']` on a non-super-admin page | Global key on scoped data — cache leakage across accounts |
| `invalidateQueries({ queryKey: ['users'] })` with only this key on a scoped mutation | Missing scoped invalidations |

## Key file locations

| Resource | Path |
|---|---|
| Permission hook | `frontend/src/hooks/usePermissions.ts` |
| Permission enum | `frontend/src/types/api.ts` (top of file) |
| Account context | `frontend/src/contexts/account-context.tsx` |
| Permission gate component | `frontend/src/components/shared/permission-gate.tsx` |
| Sidebar (nav + permission gating) | `frontend/src/components/layout/sidebar.tsx` |
| Topbar (sign-out cache cleanup) | `frontend/src/components/layout/topbar.tsx` |
| API surface (scoped vs unscoped) | `frontend/src/lib/api.ts` |
| Canonical gated action button | `frontend/src/app/(admin)/users/page.tsx` |
| Canonical scoped-vs-global query reuse | `frontend/src/app/(admin)/users/users-table.tsx` (`UserTableContent`) |
