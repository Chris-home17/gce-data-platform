# Development & Deployment Workflow

## Repository Structure

```text
gce-data-platform/
├── frontend/          # Next.js 14 admin app
├── backend/           # ASP.NET Core 8 API
├── database/          # Baseline DDL, seed data, and SQL source files
└── .github/workflows/ # CI/CD pipelines
```

## Environments

| Environment | Frontend | Backend | Database |
|---|---|---|---|
| Local dev | `http://localhost:3000` | `http://localhost:5050` | Azure SQL, accessed with your Entra identity via `azd auth login` |
| Production | `https://ambitious-stone-0a9d07003.7.azurestaticapps.net` | `https://app-gcplatform-web-weu-001-c2fyeebzh6hyhhf0.westeurope-01.azurewebsites.net` | `gce-db-dev` on `gce-sql-dev` |

## Local Development Setup

### Prerequisites

- Node.js 18+
- .NET 8 SDK
- Azure Developer CLI (`azd`)
- SQL client for manual scripts when needed: Azure Data Studio, SSMS, or equivalent

### Authentication for local Azure SQL access

This repo uses Entra authentication for Azure SQL in development.

Because `az login` is blocked by IT restrictions, use:

```bash
azd auth login
```

Optional verification:

```bash
azd auth token --scope https://database.windows.net//.default
```

If token acquisition fails here, the backend will also fail to open Azure SQL connections.

### Backend

Run from the API project:

```bash
cd backend/GcePlatform.Api
dotnet run
```

Local launch profile runs on:

```text
http://localhost:5050
```

Development config is in [backend/GcePlatform.Api/appsettings.Development.json](/Users/chrisdw/Documents/Developer/Claude Code/gce-data-platform/backend/GcePlatform.Api/appsettings.Development.json:1).

Current development connection style:

```json
"ConnectionStrings": {
  "AzureSql": "Server=tcp:gce-sql-dev.database.windows.net,1433;Database=gce-db-dev;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"
}
```

Notes:

- `Authentication=Active Directory Default` means local SQL auth depends on a usable developer credential source.
- In this setup, the expected local credential source is `azd auth login`.
- No database password is stored in the repo.

### Frontend

Create `frontend/.env.local` if needed. Typical local dev setup:

```env
NEXT_PUBLIC_DEV_BYPASS=true
NEXT_PUBLIC_API_BASE_URL=http://localhost:5050
NEXTAUTH_URL=http://localhost:3000
NEXTAUTH_SECRET=replace-me
AZURE_AD_CLIENT_ID=
AZURE_AD_CLIENT_SECRET=
AZURE_AD_TENANT_ID=
```

Then start the frontend:

```bash
cd frontend
npm install
npm run dev
```

Behavior:

- `NEXT_PUBLIC_DEV_BYPASS=true`: skips Entra login in the frontend and uses the backend dev bypass user.
- `NEXT_PUBLIC_DEV_BYPASS=false`: enables the real Entra sign-in flow in the frontend.
- Frontend dev should point to `http://localhost:5050` unless you intentionally run the API elsewhere.

### Recommended local modes

#### Fast UI/API development

Use:

```env
NEXT_PUBLIC_DEV_BYPASS=true
```

This is the most reliable local mode when you do not need to test real Entra sign-in behavior in the browser.

#### Real auth testing

Use:

```env
NEXT_PUBLIC_DEV_BYPASS=false
```

Requirements:

- frontend Entra config populated in `.env.local`
- backend able to acquire Azure SQL token via `azd auth login`
- your Entra user allowed to access the Azure SQL database

If the backend cannot get a SQL token, authenticated frontend flows will still fail even if browser sign-in succeeds.

## Database Migrations

EF Core is used only for migration orchestration. Runtime data access uses Dapper and SQL objects.

### Migration inventory

| Migration ID | Description |
|---|---|
| `20260414000001_InitialCreate` | Full baseline DDL for a fresh database |
| `20260414000002_AccountBranding` | Account branding columns and related SQL changes |
| `20260418000001_TagsAndKpiPackages` | Tags, KPI tags, KPI packages, package assignment support |

### Where migration SQL lives

- Baseline database shape: `database/ddl/tables/baseline_create.sql`
- Incremental SQL migrations: `backend/GcePlatform.Api/Migrations/Scripts/*.sql`
- EF migration wrappers: `backend/GcePlatform.Api/Migrations/*.cs`

### Important rule for new migrations

For a migration to be discoverable by EF and included in `dotnet ef database update`, all of the following must exist:

- the migration `.cs` file
- the matching `.Designer.cs` file
- embedded SQL script references in [backend/GcePlatform.Api/GcePlatform.Api.csproj](/Users/chrisdw/Documents/Developer/Claude Code/gce-data-platform/backend/GcePlatform.Api/GcePlatform.Api.csproj:1) if the migration executes external `.sql` files

If a migration exists only as a hand-written `.cs` file without the generated metadata, `dotnet ef migrations list` may not show it.

### Common commands

Run from `backend/GcePlatform.Api/` unless noted otherwise.

```bash
dotnet ef migrations list
dotnet ef database update
dotnet ef database update 20260414000001_InitialCreate
dotnet ef migrations add MyNewChange
```

Equivalent from repo root:

```bash
dotnet ef migrations list --project backend/GcePlatform.Api --startup-project backend/GcePlatform.Api
dotnet ef database update --project backend/GcePlatform.Api --startup-project backend/GcePlatform.Api
dotnet ef migrations add MyNewChange --project backend/GcePlatform.Api --startup-project backend/GcePlatform.Api
```

Do not run repo-root relative paths from inside `backend/`, or you will end up with duplicated paths like `backend/backend/GcePlatform.Api`.

### Which appsettings file EF uses

When you run EF commands without `--connection`, the API startup and design-time config determine which connection string is used.

In practice for this repo:

- local development uses [backend/GcePlatform.Api/appsettings.Development.json](/Users/chrisdw/Documents/Developer/Claude Code/gce-data-platform/backend/GcePlatform.Api/appsettings.Development.json:1)
- base defaults live in [backend/GcePlatform.Api/appsettings.json](/Users/chrisdw/Documents/Developer/Claude Code/gce-data-platform/backend/GcePlatform.Api/appsettings.json:1)
- committed production defaults live in [backend/GcePlatform.Api/appsettings.Production.json](/Users/chrisdw/Documents/Developer/Claude Code/gce-data-platform/backend/GcePlatform.Api/appsettings.Production.json:1)

Rules to follow:

- for local dev DB updates, run EF locally and let it use the development settings
- for production or any non-local target DB, prefer passing an explicit `--connection` string
- do not rely on your local shell environment accidentally selecting the correct production settings

### Updating the development database

Development updates should target the connection string in [appsettings.Development.json](/Users/chrisdw/Documents/Developer/Claude Code/gce-data-platform/backend/GcePlatform.Api/appsettings.Development.json:1).

Current flow:

1. Ensure the development connection string points to the correct Azure SQL dev database.
2. Authenticate locally:

```bash
azd auth login
```

3. Run the update:

```bash
cd backend/GcePlatform.Api
dotnet ef database update
```

This uses the local development configuration and applies all pending migrations to the dev database configured there.

### Updating the production database

Production updates should not depend on your local `appsettings.Development.json`.

Use an explicit connection string when applying migrations to production:

```bash
azd auth login
cd backend/GcePlatform.Api
dotnet ef database update --connection "Server=tcp:YOUR-PROD-SERVER.database.windows.net,1433;Database=YOUR-PROD-DB;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"
```

Why this is preferred:

- it avoids accidentally targeting the dev database
- it makes the target database explicit
- it does not depend on local environment selection behavior

If you want the committed production defaults as a reference, they live in [appsettings.Production.json](/Users/chrisdw/Documents/Developer/Claude Code/gce-data-platform/backend/GcePlatform.Api/appsettings.Production.json:1), but for manual migration execution the safer approach is still to pass `--connection` explicitly.

### Fresh database setup

1. Create the Azure SQL database.
2. Ensure your Entra identity has database access.
3. Update [backend/GcePlatform.Api/appsettings.Development.json](/Users/chrisdw/Documents/Developer/Claude Code/gce-data-platform/backend/GcePlatform.Api/appsettings.Development.json:1) if server or database name changed.
4. Authenticate locally:

```bash
azd auth login
```

5. Apply schema:

```bash
cd backend/GcePlatform.Api
dotnet ef database update
```

6. Optionally seed data:

```text
database/dml/seed_test_data.sql
```

### Adopting migrations on an existing database

If the database already exists and was created before EF migration tracking was introduced:

1. Ensure `__EFMigrationsHistory` exists.
2. Insert the migration IDs that represent schema already present in that database.
3. Run `dotnet ef database update` to apply only later migrations.

Example bootstrap:

```sql
IF OBJECT_ID('__EFMigrationsHistory') IS NULL
CREATE TABLE [__EFMigrationsHistory] (
    [MigrationId]    NVARCHAR(150) NOT NULL,
    [ProductVersion] NVARCHAR(32)  NOT NULL,
    CONSTRAINT [PK___EFMigrationsHistory] PRIMARY KEY ([MigrationId])
);
```

If the existing database already matches the baseline but not later deltas, insert only the already-present migration IDs before running EF updates.

### Applying migrations against production or another explicit database

Authenticate first:

```bash
azd auth login
```

Then run:

```bash
cd backend/GcePlatform.Api
dotnet ef database update --connection "Server=tcp:YOUR-SERVER.database.windows.net,1433;Database=YOUR-DB;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"
```

### Creating future migrations

Recommended workflow:

1. Update `database/ddl/tables/baseline_create.sql` so the baseline stays current.
2. Add a new EF migration:

```bash
cd backend/GcePlatform.Api
dotnet ef migrations add YourMigrationName
```

3. If using external SQL scripts:
- add `Migrations/Scripts/YourMigrationName.Up.sql`
- add `Migrations/Scripts/YourMigrationName.Down.sql`
- reference them in `GcePlatform.Api.csproj` as embedded resources
- call them from the generated migration class

4. Confirm the migration is discoverable:

```bash
dotnet ef migrations list
```

5. Apply locally:

```bash
dotnet ef database update
```

### Permissions needed on the database

Your Entra identity must exist in the database and have enough rights for app usage and migrations.

Typical minimum for app usage:

```sql
CREATE USER [your-name@company.com] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [your-name@company.com];
ALTER ROLE db_datawriter ADD MEMBER [your-name@company.com];
GRANT EXECUTE TO [your-name@company.com];
```

Schema migrations also require rights to create and alter database objects.

## Git Workflow

### Branch strategy

```text
main  ─────────────────────────────► production
  ▲
  ├── feature/xxx
  └── feature/yyy
```

- `main` should stay deployable.
- Use feature branches for active work.

### Starting a feature

```bash
git checkout main
git pull
git checkout -b feature/my-feature-name
```

### During development

```bash
git add <files>
git commit -m "describe the change"
git push -u origin feature/my-feature-name
```

Subsequent pushes:

```bash
git push
```

### Merging

Either open a PR or merge manually after syncing with `main`:

```bash
git checkout main
git pull
git checkout feature/my-feature-name
git merge main
git push
```

Then merge to `main` and push.

## CI/CD

### Frontend

- Trigger: push to `main`
- Workflow: `.github/workflows/azure-static-web-apps-ambitious-stone-0a9d07003.yml`

### Backend

- Trigger: push to `main` with backend changes
- Workflow: `.github/workflows/deploy-backend.yml`

Monitor both in GitHub Actions.

## Production Config

| Setting | Location |
|---|---|
| Production API connection string | `backend/GcePlatform.Api/appsettings.Production.json` |
| Production CORS origins | `backend/GcePlatform.Api/appsettings.Production.json` |
| Backend Entra app settings | Azure App Service environment variables |
| NextAuth secrets | Azure Static Web Apps configuration |
| Bootstrap super-admin UPN | App Service environment variable `PlatformSuperAdminUpn` |

Prefer committed config for stable app settings and portal config for secrets.

## Quick Reference

### Start local dev

```bash
azd auth login
cd backend/GcePlatform.Api && dotnet run
cd frontend && npm run dev
```

### Frontend local env

```env
NEXT_PUBLIC_DEV_BYPASS=true
NEXT_PUBLIC_API_BASE_URL=http://localhost:5050
```

### Check migrations

```bash
cd backend/GcePlatform.Api
dotnet ef migrations list
dotnet ef database update
```

### Check production health

```bash
curl https://app-gcplatform-web-weu-001-c2fyeebzh6hyhhf0.westeurope-01.azurewebsites.net/health
```
