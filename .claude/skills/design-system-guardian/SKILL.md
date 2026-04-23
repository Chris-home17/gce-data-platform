---
name: design-system-guardian
description: >
  Design system reviewer and enforcer for the GCE Data Platform admin app.
  Trigger this skill whenever the user asks to review, audit, or check UI/frontend code for
  design consistency; when adding new components or pages; when reviewing PRs for visual
  regressions; or when the user asks "does this follow the design system?". Also trigger for:
  adding status badges, buttons, cards, dialogs, sheets (drawers), tables, empty states,
  loading states, filter selects, or any Tailwind class changes under `frontend/src/`.
  Provides the canonical token set, component specs, and a structured review checklist
  grounded in this project's shadcn/ui + Next.js App Router stack.
---

# Design System Guardian — GCE Data Platform

Use this skill to review new and modified frontend code for adherence to the design system of
the `frontend/` app. Work through the checklist below before approving any UI change.

This app is **shadcn/ui-based**. The rule of thumb is: **reach for the shared component first,
fall back to semantic Tailwind tokens second, and never hard-code hex values or `slate-*`
colours for primary UI chrome**. Status chips and the sidebar are the only whitelisted
exceptions; everything else flows through `hsl(var(--token))`.

## Quick Reference: Tokens

All colour tokens are HSL CSS variables defined in `src/app/globals.css` and exposed via
`tailwind.config.ts`. Both light and dark mode share the same Tailwind class names — the
variable swaps underneath.

| Category | Token / class |
|---|---|
| Page background | `bg-background` |
| Card surface | `bg-card text-card-foreground` |
| Muted surface | `bg-muted` · `text-muted-foreground` |
| Primary action | `bg-primary text-primary-foreground` |
| Secondary action | `bg-secondary text-secondary-foreground` |
| Destructive / error | `bg-destructive text-destructive-foreground` · `text-destructive` |
| Accent (hover surface) | `bg-accent text-accent-foreground` |
| Border (default) | `border` (resolves to `border-border`) · `border-input` for form fields |
| Brand | `bg-brand` · `text-brand-foreground` · `bg-brand-muted` |
| Focus ring | `focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2` |
| Radius scale | `rounded-sm` = calc(--radius − 4px) · `rounded-md` (DEFAULT form controls) = 0.5rem · `rounded-lg` = --radius · `rounded-xl` (cards) |

**Never hardcode** `bg-slate-*`, `text-slate-*`, `bg-blue-600`, `text-gray-900`, hex codes, or
`rgba(...)` outside of:
- The **sidebar** (`src/components/layout/sidebar.tsx`) — intentionally dark `bg-slate-900` with `text-slate-400/500/800/900` chrome
- Inline branding styles derived from data (e.g. a tenant-supplied accent)

## Status Colors (locked — use `<StatusBadge>`, never inline)

Use `<StatusBadge status="..." />` from `src/components/shared/status-badge.tsx` for every
entity status chip. The component owns the colour mapping; **do not** re-create it inline with
`bg-green-100` / `border-green-200` etc.

| Status string (case-insensitive) | Scheme |
|---|---|
| `Active` / `Open` / `Green` | green |
| `Inactive` / `Closed` / `Red` | red |
| `Draft` / `Amber` | amber |
| `Distributed` | blue |
| anything else | falls back to `secondary` |

If a new status enum is introduced, **extend `STATUS_STYLES` in `status-badge.tsx`** — never
inline the palette at the callsite.

For non-status badges (counts, categories, tag pills), use the shadcn `<Badge>` with its
`variant` prop (`default` / `secondary` / `destructive` / `outline`). Never inline
`rounded-full border px-2.5 py-0.5 text-xs font-semibold` markup.

## Button Spec

Always use `<Button>` from `@/components/ui/button`. Sizing and variants are canonical.

```tsx
// Size:
//   default → h-10 px-4 py-2  (DEFAULT — use this for page-level CTAs)
//   sm      → h-9 rounded-md px-3
//   lg      → h-11 rounded-md px-8
//   icon    → h-10 w-10
//
// Variant:
//   default     → bg-primary text-primary-foreground hover:bg-primary/90
//   destructive → bg-destructive text-destructive-foreground
//   outline     → border border-input bg-background hover:bg-accent
//   secondary   → bg-secondary text-secondary-foreground
//   ghost       → hover:bg-accent hover:text-accent-foreground
//   link        → text-primary underline-offset-4 hover:underline

<Button size="sm" onClick={...}>
  <UserPlus className="mr-1.5 h-4 w-4" />
  Onboard User
</Button>

// Destructive confirmation — prefer <ConfirmDialog>, which applies buttonVariants({ variant: 'destructive' })
```

**RULE: Buttons that appear side-by-side in the same toolbar or header row MUST share the same
size prop.** Mixing `size="default"` (h-10) with `size="sm"` (h-9) in a single `PageHeader`
`actions` slot is a bug. The established convention on this project is `size="sm"` for page
header actions (see `users/page.tsx`).

**Icon-only buttons** MUST use `size="icon"` AND include `aria-label` (or `<span className="sr-only">`).
See `DataTable` pagination buttons in `src/components/shared/data-table.tsx` for the pattern.

**Never** use raw `<button>` for primary interactions. The only acceptable raw `<button>`
usages in this codebase are:
- Inside the dark sidebar (`layout/sidebar.tsx`) because the dark palette doesn't fit any
  shared variant
- Inside a Radix trigger that uses `asChild` on a `<Button>` anyway

## Table Action Patterns (LOCKED — consistent across all admin tables)

Row actions are centralised in `<RowActions>` from `src/components/shared/row-actions.tsx`.

### 1. Enable / Disable / Toggle active state

```tsx
<RowActions
  isActive={row.original.isActive}
  onToggle={() => api.users.setActive(row.original.userId, !row.original.isActive)}
  invalidateKeys={[['users']]}
/>
```

- Renders a `MoreHorizontal` (`⋯`) kebab `<Button variant="ghost" size="sm" className="h-7 w-7 p-0">`
- Opens a `<DropdownMenu>` with a single `Activate` / `Deactivate` item
- Destructive (`Deactivate`) items use `text-destructive focus:text-destructive`
- Stops propagation so the row's `onClick` doesn't fire

**Do NOT** add per-row `EyeOff` / `Eye` icon buttons or inline `<DropdownMenu>` / `<Button>`
composites in page files — extend `<RowActions>` if more actions are needed.

### 2. Navigation to a detail page

Use `<DataTable onRowClick>` and `useRouter().push(...)` (see `users-table.tsx`). Do not add a
separate "View" button column — the whole row is the affordance.

### 3. Destructive confirmation (delete, reset, revoke)

Use `<ConfirmDialog>` from `src/components/shared/confirm-dialog.tsx`. The confirm button is
already styled with `buttonVariants({ variant: 'destructive' })` and handles the loading
spinner — never re-implement this.

### What to flag in review

- [ ] Raw `<button>` in a table action column → replace with `<RowActions>` or a `<Button>` variant
- [ ] Inline `<DropdownMenu>` / `<Button variant="ghost" size="icon">` kebab composites repeated in page files → move into `<RowActions>`
- [ ] Per-row "Activate" / "Deactivate" text buttons rendered outside the dropdown
- [ ] Icon-only action buttons without `aria-label` or `<span className="sr-only">`
- [ ] Destructive actions that call `window.confirm()` or a bespoke dialog instead of `<ConfirmDialog>`

## Input & Select Spec

All form controls share the shadcn default height of **h-10** (form fields) unless inside a
compact toolbar where **h-8 / h-9** is explicitly used (see below).

```tsx
// Text input — canonical
import { Input } from "@/components/ui/input"
<Input placeholder="Search by name, email or role…" className="max-w-sm" />

// Select — canonical (Radix-based, NOT a raw <select>)
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
<Select value={statusFilter} onValueChange={setStatusFilter}>
  <SelectTrigger>
    <SelectValue />
  </SelectTrigger>
  <SelectContent>
    <SelectItem value="all">All statuses</SelectItem>
    <SelectItem value="active">Active only</SelectItem>
  </SelectContent>
</Select>
```

**Never use a raw `<select>` element.** Radix `<Select>` is already styled, accessible, and
dark-mode aware.

### Filter toolbars (LOCKED pattern)

The established compact-filter pattern is shown in `kpi/definitions/definitions-table.tsx`:

```tsx
<div className="flex items-center gap-3 flex-wrap">
  <div className="flex items-center gap-2">
    <span className="text-sm text-muted-foreground">Category:</span>
    <Select value={categoryFilter} onValueChange={setCategoryFilter}>
      <SelectTrigger className="w-44 h-8 text-sm">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>…</SelectContent>
    </Select>
  </div>
  {/* additional filters with matching h-8 text-sm */}
</div>
```

Rules:
- All `<SelectTrigger>` instances inside the **same** filter toolbar share the same `h-*` class
  (typically `h-8`) and the same `text-sm`
- Filter label is a separate `<span className="text-sm text-muted-foreground">Label:</span>`
  outside the trigger — never embed it as a prefix icon inside the trigger
- Numeric option values (tag IDs, period IDs) are serialised with `String(id)` at the boundary
  and parsed back with `parseInt(...)` in the change handler — Radix Select values must be strings
- If filters are active, show an "N items" count next to them in `text-xs text-muted-foreground`

### What to flag in review

- [ ] Raw `<select>` element used anywhere in `src/app/` or `src/components/`
- [ ] `<SelectTrigger>` with inconsistent heights inside the same toolbar (e.g. one `h-8`, one `h-10`)
- [ ] A `<Filter>` icon from lucide-react stuffed inside a select wrapper as a prefix
- [ ] Numeric IDs passed to `<Select value={}>` without `String(...)` conversion (Radix will warn)
- [ ] Filter labels baked into the placeholder instead of rendered as sibling `<span>`s

## Typography Rules

| Use | Class |
|---|---|
| Page title (`<PageHeader title>`) | `text-2xl font-semibold tracking-tight` (already applied) |
| Section heading | `text-lg font-semibold leading-none tracking-tight` (matches `<DialogTitle>` / `<CardTitle>`) |
| ALL-CAPS labels / section dividers | `text-xs font-semibold uppercase tracking-widest text-muted-foreground` |
| Body | `text-sm` + default `text-foreground` |
| Secondary / help text | `text-sm text-muted-foreground` |
| Micro / sublabel | `text-xs text-muted-foreground` |
| Tabular numeric data | add `tabular-nums` (see `users-table.tsx` count columns) |
| Mono / codes | `font-mono` + `text-xs` or `text-sm` depending on size |

**Never** use arbitrary `tracking-[0.2em]`, `text-[13px]`, or `text-slate-700`-style overrides.
Use the token scale. If the design genuinely needs something the scale doesn't cover, extend
the scale (via tailwind config or a shared component) rather than a one-off utility.

## Layout Rules

Admin pages are already wrapped by `AdminShell` in `src/app/(admin)/admin-shell.tsx`, which
applies `mx-auto max-w-7xl space-y-6 p-6`. This means:

- **Page roots should be `<div className="space-y-6">`** — never re-add `p-6` or `max-w-*`
  constraints per page (see `users/page.tsx`, `kpi/definitions/page.tsx` for the canonical pattern)
- Use `<PageHeader>` from `src/components/shared/page-header.tsx` — it applies the `h1`,
  description, and right-aligned `actions` slot with correct spacing. Never hand-roll a page
  heading.
- Cards use `<Card>` (`rounded-xl border bg-card shadow`) with `<CardHeader>`, `<CardContent>`,
  `<CardFooter>` sub-components
- Stat cards (dashboard / monitoring) use `rounded-lg border bg-card p-4 shadow-sm` — see
  `kpi/monitoring/monitoring-view.tsx` `StatCard`
- Tables use `<DataTable>` from `src/components/shared/data-table.tsx` — it owns skeleton
  loading, pagination, and empty state. Pass `ColumnDef[]` with `meta.className` /
  `meta.headerClassName` for custom cell alignment
- Modals use `<Dialog>` (shadcn) for form-heavy flows; `<AlertDialog>` (via `<ConfirmDialog>`)
  for destructive confirmations; `<Sheet>` for side-panel detail / create flows
- Sheet width convention: default (`max-w-sm` from Radix) for simple, `className="sm:max-w-md"`
  standard, `sm:max-w-xl` wide, `sm:max-w-2xl` complex — check existing sheets before choosing

### The sidebar exception

`src/components/layout/sidebar.tsx` is intentionally dark and uses `bg-slate-900`,
`text-slate-400`, `text-white`, etc. **Do not flag sidebar files for slate/white colour use** —
but DO flag copy-paste of sidebar styles into admin page content.

## Accessibility Baseline

- Every icon-only button MUST have `aria-label` or `<span className="sr-only">` (see pagination
  buttons in `data-table.tsx`, `MoreHorizontal` trigger in `row-actions.tsx`)
- Every form input MUST have a `<Label>` (from `@/components/ui/label`) — visible or via
  `htmlFor` + `sr-only`
- Form validation MUST flow through `<Form>` (shadcn) when using react-hook-form — don't emit
  ad-hoc red text below inputs
- `<DropdownMenu>` items that navigate MUST wrap `<Link>` with `asChild` on the item — never
  put `onClick={() => router.push(...)}` on a DropdownMenuItem (breaks middle-click / keyboard)
- Focus ring removal (`focus:outline-none` without a `focus-visible:ring-*` replacement) is a bug
- Colour MUST NOT be the sole differentiator for status — `<StatusBadge>` always includes the
  text label; don't replace it with a coloured dot alone

## Dark Mode

The app ships with `.dark` CSS variables in `globals.css`. Every colour class used in admin
content MUST resolve correctly in dark mode:

- ✅ `text-muted-foreground`, `bg-card`, `border-input` — token-based, works in dark
- ❌ `text-slate-700`, `bg-white`, `border-slate-200` — hardcoded, breaks dark mode

When reviewing a change, mentally flip to dark mode: if the component would read as
black-on-black or white-on-white, the colour class is wrong. The fix is almost always to
replace a `slate-*` / `white` / `black` class with the semantic token.

## Review Checklist

### Tokens & colours
- [ ] No hardcoded `bg-slate-*` / `text-slate-*` / `bg-gray-*` in admin content (sidebar exempt)
- [ ] No hex codes or `rgb(...)` outside tenant branding contexts
- [ ] Status chips use `<StatusBadge>`; any new status value extends `STATUS_STYLES`
- [ ] Non-status badges use `<Badge>` with a `variant` prop — no inline `rounded-full px-2.5 py-0.5`
- [ ] Colours used also resolve correctly in dark mode (i.e. use `hsl(var(--...))` tokens)

### Buttons
- [ ] All interactive buttons use `<Button>` (or `<DropdownMenuTrigger asChild><Button>...`); no raw `<button>` for primary UI
- [ ] Page header actions consistently use `size="sm"` and share the same variant family
- [ ] Buttons in the same toolbar row share the same `size`
- [ ] Destructive actions use `variant="destructive"` (directly or via `<ConfirmDialog>`)
- [ ] Icon-only buttons use `size="icon"` AND have `aria-label` or `<span className="sr-only">`
- [ ] Loading state uses the `disabled` prop + inline `<Loader2 className="animate-spin" />`, not bespoke spinners

### Tables & row actions
- [ ] Tables use `<DataTable>` — no hand-rolled `<table>` markup outside `data-table.tsx` itself
- [ ] Row enable/disable uses `<RowActions>` — no inline kebab / dropdown re-implementations
- [ ] Destructive row confirmations go through `<ConfirmDialog>`
- [ ] Row `onClick` handlers that navigate use `onRowClick` on `<DataTable>` (not per-row `<Link>` wrappers)
- [ ] Cell-level action buttons (inside rows) stop propagation (`onClick={(e) => e.stopPropagation()}`) if the row itself is clickable

### Form controls
- [ ] No raw `<select>` — always `<Select>` from `@/components/ui/select`
- [ ] No raw `<input>` — always `<Input>`, `<Textarea>`, or `<Switch>` from `@/components/ui/*`
- [ ] Filter toolbars: all `<SelectTrigger>` instances share the same height class (`h-8` on filters, `h-10` on forms)
- [ ] Numeric Select values are wrapped with `String(...)` / parsed with `parseInt(...)` at the boundary
- [ ] Form flows use `<Form>` + react-hook-form, not ad-hoc state + manual error text

### Page layout
- [ ] Admin page root is `<div className="space-y-6">` — no re-applied `p-6` / `max-w-7xl` wrappers
- [ ] `<PageHeader>` is used for every admin page heading (no hand-rolled `<h1>` + description markup)
- [ ] Cards use `<Card>` / `<CardHeader>` / `<CardContent>` — no raw `rounded-xl border bg-card` divs for content cards
- [ ] Modals route through `<Dialog>` (forms) or `<AlertDialog>` (confirmations via `<ConfirmDialog>`)
- [ ] Side panels use `<Sheet>` with consistent `sm:max-w-*` width class

### Accessibility
- [ ] Every icon-only button has `aria-label` or `<span className="sr-only">`
- [ ] Every form field has a `<Label>` (visible or sr-only)
- [ ] `focus:outline-none` is only used alongside a replacement `focus-visible:ring-*`
- [ ] Status / severity is never communicated by colour alone (always paired with a text label)

### Data fetching & state (related to UI)
- [ ] Loading uses `<Skeleton>` / `<DataTable isLoading>` — no spinner-in-a-box placeholders on tables
- [ ] Error states match the `rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center` pattern in `users-table.tsx` / `definitions-table.tsx`
- [ ] Empty tables show "No results found." via `<DataTable>` default — don't re-implement
- [ ] Success / failure feedback uses `toast` from `sonner` (see `monitoring-view.tsx`), not `alert()`

## Key File Locations

| Resource | Path |
|---|---|
| Tailwind config | `frontend/tailwind.config.ts` |
| CSS variables / globals | `frontend/src/app/globals.css` |
| Admin layout shell | `frontend/src/app/(admin)/layout.tsx` · `admin-shell.tsx` |
| Sidebar (dark — exception) | `frontend/src/components/layout/sidebar.tsx` |
| Topbar / breadcrumbs | `frontend/src/components/layout/topbar.tsx` |
| `<Button>` | `frontend/src/components/ui/button.tsx` |
| `<Badge>` | `frontend/src/components/ui/badge.tsx` |
| `<StatusBadge>` | `frontend/src/components/shared/status-badge.tsx` |
| `<Input>` / `<Select>` | `frontend/src/components/ui/input.tsx` · `select.tsx` |
| `<Card>` / `<Dialog>` / `<AlertDialog>` / `<Sheet>` | `frontend/src/components/ui/` |
| `<PageHeader>` | `frontend/src/components/shared/page-header.tsx` |
| `<DataTable>` | `frontend/src/components/shared/data-table.tsx` |
| `<RowActions>` | `frontend/src/components/shared/row-actions.tsx` |
| `<ConfirmDialog>` | `frontend/src/components/shared/confirm-dialog.tsx` |
| Canonical page example | `frontend/src/app/(admin)/users/page.tsx` · `users-table.tsx` |
| Canonical filter toolbar example | `frontend/src/app/(admin)/kpi/definitions/definitions-table.tsx` |
