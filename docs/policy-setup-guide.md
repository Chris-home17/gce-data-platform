# Policy Setup Guide

This document explains how to configure policies in the GCE Data Platform, what each policy type does, when to use it, and how to model common scenarios without creating unnecessary manual work.

This guide complements [rbac-policy-model.md](/Users/chrisdw/Documents/Developer/Claude Code/gce-data-platform/docs/rbac-policy-model.md).

## Purpose of Policies

Policies exist to automate repeated setup work.

Instead of manually creating the same grants and roles every time a new account or org-unit structure is added, you define reusable rules and let the platform materialize them.

In practice, policies help you:

- reduce manual account onboarding work
- keep account security models consistent
- avoid repetitive grant administration
- generate account-specific roles automatically

## The Three Policy Types

There are three policy families in the database:

1. `Sec.AccountAccessPolicy`
2. `Sec.AccountPackagePolicy`
3. `Sec.AccountRolePolicy`

Each solves a different problem.

## 1. Account Access Policy

### What it does

An `AccountAccessPolicy` grants account access to an existing principal.

The principal can be:

- a role
- a user

This policy controls where someone can go in the account structure.

It does not decide which package or reports they can access.

### Main fields

- `PolicyName`
- `PrincipalId`
- `ScopeType`
- `OrgUnitType`
- `OrgUnitCode`
- `IsActive`

### Scope options

#### `ScopeType = 'NONE'`

This means full account scope.

The principal gets access to the whole account.

Example:

- `SOC_GLOBAL` should see every site in every account

Example insert:

```sql
INSERT INTO Sec.AccountAccessPolicy
    (PolicyName, PrincipalId, ScopeType)
VALUES
    ('SOC Global Full Account', @SocGlobalRoleId, 'NONE');
```

#### `ScopeType = 'ORGUNIT'`

This means scoped account access.

The principal gets access only to a matching org unit and its descendant path.

Example:

- a country manager should see only Belgium

Example insert:

```sql
INSERT INTO Sec.AccountAccessPolicy
    (PolicyName, PrincipalId, ScopeType, OrgUnitType, OrgUnitCode)
VALUES
    ('BE Country Managers Country Scope', @CountryManagerRoleId, 'ORGUNIT', 'Country', 'BE');
```

### Good use cases

- global operational teams who need all sites in all accounts
- country or division managers
- central support teams that need access to account structure but not all packages

### Avoid using it for

- package/report access
- account-specific roles that should be created dynamically

## 2. Account Package Policy

### What it does

An `AccountPackagePolicy` grants package access to an existing principal.

This controls what application or reporting package someone can open.

It does not decide which sites or org units they can see.

### Main fields

- `PolicyName`
- `PrincipalId`
- `GrantScope`
- `PackageCode`
- `IsActive`

### Grant scope options

#### `GrantScope = 'ALL_PACKAGES'`

The principal gets every package.

Example:

- global executives should automatically receive all packages

Example insert:

```sql
INSERT INTO Sec.AccountPackagePolicy
    (PolicyName, PrincipalId, GrantScope)
VALUES
    ('Global Executives All Packages', @GlobalExecutiveRoleId, 'ALL_PACKAGES');
```

#### `GrantScope = 'PACKAGE'`

The principal gets one specific package.

Example:

- the SOC team should automatically receive the `SOC` package

Example insert:

```sql
INSERT INTO Sec.AccountPackagePolicy
    (PolicyName, PrincipalId, GrantScope, PackageCode)
VALUES
    ('SOC Global SOC Package', @SocGlobalRoleId, 'PACKAGE', 'SOC');
```

### Good use cases

- automatically assigning `SOC`, `FIN`, `KPI`, or `GUARD`
- giving a global function all packages
- separating package entitlements from scope entitlements

### Avoid using it for

- org-unit scoping
- dynamic per-account role generation

## 3. Account Role Policy

### What it does

An `AccountRolePolicy` creates per-account roles from templates.

It is the policy type used when every account should get a local role with the same pattern.

After materialization, that generated role can receive account-wide or org-unit-scoped access.

### Main fields

- `PolicyName`
- `RoleCodeTemplate`
- `RoleNameTemplate`
- `ScopeType`
- `OrgUnitType`
- `OrgUnitCode`
- `IsActive`

### Template tokens

Supported tokens:

- `{AccountCode}`
- `{AccountName}`

Examples:

- `RoleCodeTemplate = '{AccountCode}_OPS_LEAD'`
- `RoleNameTemplate = '{AccountName} Operations Lead'`

For account `DHL`, this becomes:

- `DHL_OPS_LEAD`
- `DHL Global Logistics Operations Lead`

### Scope options

#### `ScopeType = 'NONE'`

The generated role gets full access to the account.

Example:

```sql
INSERT INTO Sec.AccountRolePolicy
    (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType)
VALUES
    ('Per-account Global Account Director',
     '{AccountCode}_GAD',
     '{AccountName} Global Account Director',
     'NONE');
```

Result:

- `DHL_GAD`
- `UPS_GAD`
- `AMZN_GAD`

Each gets full access to its own account.

#### `ScopeType = 'ORGUNIT'`

The generated role gets access only to the matching org unit inside each account.

Example:

```sql
INSERT INTO Sec.AccountRolePolicy
    (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode)
VALUES
    ('Per-account Europe Division Manager',
     '{AccountCode}_EU_MANAGER',
     '{AccountName} Europe Division Manager',
     'ORGUNIT',
     'Division',
     'EU');
```

Result:

- `DHL_EU_MANAGER`
- `UPS_EU_MANAGER`
- `AMZN_EU_MANAGER`

Each gets access only to the `EU` division path in its own account, if that org unit exists.

### Good use cases

- account directors
- account operations leads
- account finance managers
- division-specific or country-specific leadership roles

### Avoid using it for

- one-off exceptions
- global roles that should already exist once and be reused

## How to Choose the Right Policy

Use this rule:

- if the principal already exists and needs scope access, use `AccountAccessPolicy`
- if the principal already exists and needs package access, use `AccountPackagePolicy`
- if the role should be created separately per account, use `AccountRolePolicy`

## Recommended Setup Patterns

## Pattern 1: Global Team

Goal:

- same team works across all accounts

Recommended setup:

- create one shared role such as `SOC_GLOBAL`
- use `AccountAccessPolicy` for scope
- use `AccountPackagePolicy` for package access
- assign people to that role

Example:

```sql
INSERT INTO Sec.AccountAccessPolicy
    (PolicyName, PrincipalId, ScopeType)
VALUES
    ('SOC Global Full Account', @SocGlobalRoleId, 'NONE');

INSERT INTO Sec.AccountPackagePolicy
    (PolicyName, PrincipalId, GrantScope, PackageCode)
VALUES
    ('SOC Global SOC Package', @SocGlobalRoleId, 'PACKAGE', 'SOC');
```

## Pattern 2: Local Account Leadership

Goal:

- every account should have its own director or lead role

Recommended setup:

- use `AccountRolePolicy`
- assign people to generated roles after materialization

Example:

```sql
INSERT INTO Sec.AccountRolePolicy
    (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType)
VALUES
    ('Per-account Operations Lead',
     '{AccountCode}_OPS_LEAD',
     '{AccountName} Operations Lead',
     'NONE');
```

## Pattern 3: Scoped Regional Leadership

Goal:

- every account should have a role for one specific division or country

Recommended setup:

- use `AccountRolePolicy` with `ScopeType = 'ORGUNIT'`

Example:

```sql
INSERT INTO Sec.AccountRolePolicy
    (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode)
VALUES
    ('Per-account Belgium Country Manager',
     '{AccountCode}_BE_MANAGER',
     '{AccountName} Belgium Country Manager',
     'ORGUNIT',
     'Country',
     'BE');
```

## Pattern 4: Exceptions

Goal:

- one user needs unusual access that should not become a reusable policy

Recommended setup:

- do not create a policy
- use a direct grant on the user

Example:

- one external consultant needs temporary access to one account

That is a direct grant case, not a policy case.

## Setup Examples by Scenario

## Scenario A: Global Executive

Need:

- all accounts
- all packages

Setup:

- shared role `GLOBAL_EXECUTIVE`
- `AccountAccessPolicy` with `ScopeType = 'NONE'`
- `AccountPackagePolicy` with `GrantScope = 'ALL_PACKAGES'`

## Scenario B: Belgium KPI Consumers

Need:

- Belgium only
- KPI package only

Setup:

- shared role `COUNTRY_MANAGER_BE`
- `AccountAccessPolicy` with `ScopeType = 'ORGUNIT'`, `OrgUnitType = 'Country'`, `OrgUnitCode = 'BE'`
- `AccountPackagePolicy` with `GrantScope = 'PACKAGE'`, `PackageCode = 'KPI'`

## Scenario C: Account Director

Need:

- a local director role in every account

Setup:

- `AccountRolePolicy`
- `RoleCodeTemplate = '{AccountCode}_GAD'`
- `RoleNameTemplate = '{AccountName} Global Account Director'`
- `ScopeType = 'NONE'`

## Scenario D: Europe Finance Manager Per Account

Need:

- one finance role per account
- only for the Europe division

Setup:

- `AccountRolePolicy`
- `RoleCodeTemplate = '{AccountCode}_EU_FIN'`
- `RoleNameTemplate = '{AccountName} Europe Finance Manager'`
- `ScopeType = 'ORGUNIT'`
- `OrgUnitType = 'Division'`
- `OrgUnitCode = 'EU'`

## When Policies Apply

Policies are applied when:

- a new account is created with policy application enabled
- org units are created through the admin flow with policy application enabled
- a policy is explicitly refreshed or applied

This means policy setup and policy materialization are separate ideas:

- defining a policy stores the rule
- applying or refreshing a policy materializes it into roles and grants

## Active vs Inactive Policies

When a policy is active:

- it can be materialized
- refresh/apply actions can create or reactivate its generated roles

When a policy is inactive:

- it is no longer used for new materialization
- generated roles created from that policy can be deactivated by the policy status flow

## Recommended Admin Workflow

When adding a new policy:

1. decide whether this is global, package-based, or account-generated
2. choose the correct policy type
3. use stable naming templates
4. prefer shared roles for cross-account teams
5. prefer account role policies for per-account responsibilities
6. only use direct grants for exceptions

## Naming Recommendations

Use predictable naming:

- shared roles:
  - `SOC_GLOBAL`
  - `FIN_GLOBAL`
  - `COUNTRY_MANAGER_BE`
- generated roles:
  - `{AccountCode}_GAD`
  - `{AccountCode}_OPS_LEAD`
  - `{AccountCode}_EU_MANAGER`

Keep templates:

- short
- readable
- stable over time

Avoid changing templates casually after policies are already materialized.

## Common Mistakes

Avoid:

- using `AccountRolePolicy` when a single shared role is enough
- creating policies for one-off exceptions
- mixing package intent and scope intent in the same mental model
- creating too many overlapping generated roles
- using inconsistent role naming templates

## Quick Decision Matrix

If you need:

- existing principal + account/org-unit scope:
  use `AccountAccessPolicy`

- existing principal + package access:
  use `AccountPackagePolicy`

- one generated role per account:
  use `AccountRolePolicy`

- one unusual temporary exception:
  use a direct grant instead of a policy

## Summary

The best policy setup is usually:

- shared roles for shared functions
- generated roles for local account ownership
- access policies for structure scope
- package policies for application/report scope
- direct grants only for exceptions

That gives you the lowest manual effort and the most scalable account onboarding model.
