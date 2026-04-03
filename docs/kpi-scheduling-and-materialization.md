# KPI Scheduling And Materialization

This document explains the recurring KPI model that now sits behind the KPI `Periods` and `Assignments` admin screens.

The goal is to avoid repetitive manual setup while still supporting different cadences such as monthly, every two months, or quarterly.

Instead of:

- creating a new period every month
- creating the same KPI assignments every month

the platform now supports:

- cadence schedules
- schedule-linked KPI templates
- generated reporting periods
- materialized reporting assignment instances

It also reflects the current admin UI behavior:

- the `Periods` screen is split into `Period schedules` and `Generated periods`
- the `Assignments` screen is split into `Recurring templates` and `Generated assignment instances`
- the `Assignments` screen has shared `Account` and `Scope` page filters that apply to both tables
- the `Generated assignment instances` table keeps its own `Period` filter because period is only meaningful for operational instances

## The Model

There are now two layers:

1. Planning layer
- `KPI.PeriodSchedule`
- `KPI.AssignmentTemplate`

2. Operational layer
- `KPI.Period`
- `KPI.Assignment`

The planning layer defines what should exist over time.

The operational layer contains the actual month-by-month records that the rest of the system uses for:

- opening and closing submission windows
- submissions
- completion monitoring
- reminders
- escalation

## Core Terms

### Period Schedule

A period schedule defines the reporting cadence.

It answers:

- when reporting starts
- when reporting ends, if it ends
- how often reporting recurs
- which day of each generated period submissions open
- which day of each generated period submissions close
- how many future periods should be generated ahead

Example:

- Schedule name: `Monthly Operations Reporting`
- Frequency: `Monthly`
- Start date: `2026-01-01`
- End date: `2027-12-31`
- Submission open day: `1`
- Submission close day: `28`
- Generate months ahead: `6`

Meaning:

- create KPI periods from January 2026 onward
- use the selected cadence to decide which months appear
- each generated period opens on the 1st
- each generated period closes on the 28th
- keep generating future periods up to the defined horizon

### Generate

`Generate` means:

- take a `KPI.PeriodSchedule`
- create missing `KPI.Period` rows for each generated cadence occurrence in scope
- update existing `Draft` or `Open` periods if their generated dates should change
- do not overwrite `Closed` or `Distributed` periods

So generation affects periods only.

It does not directly create KPI assignments.

### Assignment Template

An assignment template defines a recurring KPI requirement and links it to a schedule.

It answers:

- which KPI should recur
- which schedule should drive that recurrence
- for which account
- optionally for which site
- whether it is required
- the thresholds and target values
- the submitter guidance

Example:

- KPI: `Q-001`
- Schedule: `Monthly Operations Reporting`
- Account: `DHL`
- Scope: account-wide
- Required: yes
- Target: `98.5`

Meaning:

- every generated period produced by that schedule should have a `Q-001` assignment for DHL

### Materialize

`Materialize` means:

- take one or more `KPI.AssignmentTemplate` rows
- look at the already existing `KPI.Period` rows that match the linked schedule cadence
- create or update matching `KPI.Assignment` rows for each generated occurrence

So materialization affects assignments only.

It does not create periods.

## How The Flow Works

### 1. Create a schedule

An admin creates a period schedule in the `Periods` screen.

That schedule does not itself collect submissions.

It is just the rule set used to generate monthly operational periods.

### 2. Generate periods

When the admin clicks `Generate` or chooses `Generate now` during schedule creation:

- the system creates the missing month-level rows in `KPI.Period`

Those generated rows are what the rest of the platform works against.

Example:

Schedule:

- frequency `Monthly`
- start `2026-01-01`
- end `2026-03-31`
- open day `1`
- close day `25`

Generated periods:

- `2026-01`
- `2026-02`
- `2026-03`

With approximate windows:

- `2026-01-01` to `2026-01-25`
- `2026-02-01` to `2026-02-25`
- `2026-03-01` to `2026-03-25`

Current UI note:

- `Generate missing periods` from the schedule row action only generates periods
- `Generate now` during schedule creation is a convenience workflow that can immediately create the missing periods and then materialize active recurring assignment templates

That convenience does not change the underlying model:

- generation still creates periods
- materialization still creates assignments

### 3. Create recurring assignment templates

An admin creates recurring assignment templates in the `Assignments` screen.

The template says:

- which KPI recurs
- where it applies
- which cadence schedule drives it

But the template itself is not the month-level assignment record used for submissions.

It is the rule that produces those month-level assignment records.

### 4. Materialize assignments

When the admin clicks `Materialize now` or chooses `Materialize now` during template creation:

- the system looks for existing `KPI.Period` rows in scope
- for every matching month, it creates or updates a `KPI.Assignment`

Example:

Template:

- KPI `F-001`
- Schedule `Quarterly Executive Review`
- Account `ACME`

Existing periods:

- `2026-01`
- `2026-04`

Materialized assignments created:

- `F-001 / ACME / 2026-01`
- `F-001 / ACME / 2026-04`

If later cadence periods are generated, materializing again will add the missing matching assignments.

## Generate vs Materialize

This is the most important distinction.

### Generate

`Generate` works on the calendar.

It creates:

- `KPI.Period`

It uses:

- `KPI.PeriodSchedule`

### Materialize

`Materialize` works on recurring KPI requirements.

It creates:

- `KPI.Assignment`

It uses:

- `KPI.AssignmentTemplate`
- existing `KPI.Period`

### Simple rule

- no periods: nothing to materialize into
- no templates: periods exist, but no recurring assignments are produced

## Why Both Concepts Exist

Because they solve different problems.

### The schedule answers:

- what reporting windows should exist?
- how often should they recur?

### The template answers:

- which KPI should recur in those months?

Separating them keeps the model scalable.

Examples:

- one schedule can serve many templates
- one account can have many templates under the same cadence
- new periods can be generated without redefining all KPI assignments
- new templates can be added without redesigning the reporting calendar

## Account-Wide vs Site-Specific Templates

Templates support two scopes.

### Account-wide

`OrgUnitId` is `NULL`

Meaning:

- one assignment per account per generated schedule period

Use this when the KPI is reported once at account level.

Example:

- monthly operating margin for the account
- monthly revenue for the account

### Site-specific

`OrgUnitId` points to a site

Meaning:

- one assignment per site per generated schedule period

Use this when each site submits separately.

Example:

- site-level injury rate
- site-level complaint rate
- site-level absenteeism

## What Happens On Re-Materialization

Materialization is designed to be repeatable.

If a matching assignment already exists for:

- KPI
- account or site scope
- month

then the system updates and reactivates it rather than creating a duplicate.

That means materializing again is safe when:

- a new month has been generated
- thresholds changed
- guidance changed
- a previously inactive assignment should come back

## What Happens When A Schedule Is Changed

If a schedule is edited and generated again:

- missing periods are created
- existing `Draft` or `Open` periods can be updated to match the schedule
- `Closed` or `Distributed` periods are not overwritten

This protects historical operational periods.

## What Happens When A Template Is Changed

If a template is edited and materialized again:

- existing matching assignments in the active monthly range are updated
- missing assignments are created
- inactive matching assignments are reactivated

This lets you evolve the recurring rule without manually touching every month.

## Recommended Admin Workflow

### Initial contract setup

1. Create the required schedules
2. Generate periods
3. Create schedule-linked assignment templates
4. Materialize assignments
5. Open the generated periods when submissions should begin

### Ongoing monthly operations

1. Generate future periods when needed
2. Materialize templates again if new periods were added
3. Open current month
4. Monitor submissions and completion
5. Close the month when complete

### Current UI workflow shortcut

In the current admin UI you will often use this shorter path:

1. Create or update a schedule and choose `Generate now`
2. Create recurring templates and leave `Materialize now` enabled
3. Use the `Assignments` page filters to verify both the template set and the generated instances for the same account or scope
4. Open the operational periods when submissions should start

This shortcut still maps to the same two-step model:

- periods are generated from schedules
- assignments are materialized from templates into those periods

## Typical Use Cases

### Use case 1: Open-ended contract

Schedule:

- start date set
- no end date
- horizon set to `6`

Behavior:

- keep generating six months ahead from “now”

Use when:

- the contract has no known end date

### Use case 2: Fixed-term contract

Schedule:

- start date set
- end date set

Behavior:

- generate only the months in that contractual range

Use when:

- reporting should stop automatically at contract end

### Use case 3: Standard recurring KPI set

Templates:

- `Q-001`
- `F-001`
- `H-001`

All account-wide for the same account.

Behavior:

- every generated monthly period gets the same recurring KPI set

Use when:

- the KPI pack is stable over the lifetime of the account

### Use case 4: Mixed account and site reporting

Templates:

- account-wide financial KPIs
- site-level safety KPIs

Behavior:

- finance submits once at account level
- operations submits once per site

Use when:

- the data collection model differs by KPI

## What This Does Not Replace

This model does not remove the operational month-level objects.

The platform still runs on:

- `KPI.Period`
- `KPI.Assignment`

because those are needed for:

- submissions
- locking
- reminders
- completion monitoring

The new model only automates how those rows get created.

## Practical Mental Model

Use this shorthand:

- Schedule = calendar rule
- Generate = create monthly periods from that rule
- Template = recurring KPI rule
- Materialize = create monthly assignments from that rule

If you remember that split, the full flow stays clear.

## Current UI Mapping

### Periods screen

Top section:

- `Period schedules`

Bottom section:

- `Generated periods`

### Assignments screen

Top section:

- `Recurring templates`

Bottom section:

- `Generated assignment instances`

Page-level filters:

- `Account`
- `Scope`

Table-level filter:

- `Period` on `Generated assignment instances`

That layout mirrors the model exactly:

- planning objects first
- operational objects second
