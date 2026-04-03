# RBAC Policy Model

This document explains how users, roles, grants, delegations, and policies work together in the GCE Data Platform, and how to configure them in a scalable way.

## Overview

Think of the model as three layers:

1. `Users`
   Real people. Users can receive direct access grants, direct package grants, delegations, and inherited access through roles.

2. `Roles`
   Reusable bundles of responsibility. Roles can hold access grants and package grants, and users become members through `Sec.RoleMembership`.

3. `Policies`
   Automation rules. Policies do not give access by themselves. They materialize roles and grants when accounts or org units are created, or when policies are explicitly applied.

## How Access Is Determined

A user gets effective access from:

- direct grants on the user
- grants on roles the user belongs to
- delegations
- policy-generated roles and grants that have already been materialized into the database

In practice, the usual flow is:

1. define reusable roles
2. assign users to those roles
3. define policies so new accounts and org units automatically receive the correct roles and grants
4. let the system materialize those policies with `App.ApplyAccountPolicies`

## Policy Types

### `AccountAccessPolicy`

This gives an existing principal account access for every account when policies are applied.

The principal can be either a role or a user.

Common examples:

- full account access
- division-scoped access
- country-scoped access
- site-scoped access

Example:

- policy: `SOC Global Full Account`
- principal: role `SOC_GLOBAL`
- scope: `NONE`

Result when applied to `DHL`:

- role `SOC_GLOBAL` receives account access to `DHL`

### `AccountPackagePolicy`

This gives an existing principal package access when policies are applied.

The principal can be either a role or a user.

Common examples:

- all packages
- one specific package such as `SOC`, `FIN`, or `KPI`

Example:

- policy: `SOC Global SOC Package`
- principal: role `SOC_GLOBAL`
- package: `SOC`

Result:

- role `SOC_GLOBAL` receives access to package `SOC`

### `AccountRolePolicy`

This creates per-account roles dynamically from templates, and can optionally grant those generated roles account-wide or org-unit-scoped access.

This is the best fit for account-specific responsibilities.

Example:

- role code template: `{AccountCode}_OPS_LEAD`
- role name template: `{AccountName} Operations Lead`
- scope: `NONE`

When applied to `DHL`:

- role `DHL_OPS_LEAD` is created
- that role receives account-wide access to `DHL`

## Recommended Scalable Model

The scalable pattern is:

- use roles for stable business responsibilities
- use policies for repeatable account onboarding
- use direct user grants only for real exceptions

Good target structure:

- global shared roles for central teams
- per-account generated roles for local ownership
- user membership into those roles
- policies to automate new account and org-unit rollout

## Recommended Configuration Approach

### 1. Global Functional Roles

Examples:

- `SOC_GLOBAL`
- `FIN_GLOBAL`
- `KPI_ADMIN`

Use these when the same function applies across many accounts.

### 2. Per-Account Generated Roles via `AccountRolePolicy`

Examples:

- `{AccountCode}_OPS_LEAD`
- `{AccountCode}_FIN_MANAGER`
- `{AccountCode}_EU_MANAGER`

Use these when each account needs its own local lead or manager role and you want account onboarding to be automatic.

### 3. User Membership into Roles

Examples:

- Bruno is a member of `DHL_EU_MANAGER`
- Hassan is a member of `SOC_GLOBAL`

Use this when people change more frequently than the role structure.

This keeps administration low-maintenance.

## Concrete Use Cases

### Use Case 1: Global SOC Team

Configuration:

- create role `SOC_GLOBAL`
- add `AccountAccessPolicy` for full account scope
- add `AccountPackagePolicy` for package `SOC`
- add users to `SOC_GLOBAL`

Result:

- every SOC user automatically gets SOC package access and account coverage everywhere

### Use Case 2: Account Operations Lead Per Customer

Configuration:

- create `AccountRolePolicy`
- role code template: `{AccountCode}_OPS_LEAD`
- role name template: `{AccountName} Operations Lead`
- scope: `NONE`

Result:

- when `DHL` is created, role `DHL_OPS_LEAD` is generated automatically
- the admin only needs to assign the correct user to that role

### Use Case 3: Europe-Only Manager Per Account

Configuration:

- create `AccountRolePolicy`
- role code template: `{AccountCode}_EU_MANAGER`
- role name template: `{AccountName} Europe Division Manager`
- scope: `ORGUNIT`
- `OrgUnitType = 'Division'`
- `OrgUnitCode = 'EU'`

Result:

- each account gets a role such as `UPS_EU_MANAGER`
- that role receives access only to the EU division of that account

### Use Case 4: Country-Specific KPI Consumers

Configuration:

- create role `COUNTRY_MANAGER_BE`
- add `AccountAccessPolicy` scoped to `Country = BE`
- add `AccountPackagePolicy` for `KPI`
- assign Belgian country managers to that role

Result:

- users get KPI access only where they need it

### Use Case 5: One-Off Exception

Configuration:

- give a direct user grant to `victor.lee@...` for `ACME`
- do not create a reusable role unless the pattern becomes recurring

Result:

- the exception is handled quickly without polluting the role model

## What To Avoid

Avoid:

- granting everything directly to users
- creating one role per person
- creating too many ad hoc roles with overlapping meaning
- relying on manual rework for every new account

These patterns do not scale.

## Simple Decision Rule

Use:

- direct user grants for rare exceptions
- shared roles for common business functions
- `AccountRolePolicy` for repeatable per-account responsibilities
- `AccountAccessPolicy` and `AccountPackagePolicy` to automate grants during account and org-unit onboarding

## Good Target State

For a new account, the ideal flow is:

1. account is created
2. policies auto-apply
3. generated account roles appear automatically
4. the admin assigns users to the right roles
5. exceptions are handled separately

This is the scalable model:

- automate structure
- minimize manual grants
- keep exceptions exceptional

## Operational Guidance

When configuring the platform:

- prefer roles over direct user grants
- prefer policies over manual per-account setup
- reserve direct grants for exceptions
- let account creation and org-unit creation trigger policy application
- use policy refresh when a new policy must be backfilled to existing accounts

## Summary

The core principle is:

- users represent people
- roles represent responsibilities
- policies automate how those responsibilities are materialized across accounts

If the structure is designed well, onboarding a new account should mostly be automatic and administrators should mainly be assigning people to roles rather than creating grants by hand.
