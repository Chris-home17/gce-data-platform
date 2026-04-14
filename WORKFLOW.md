# Development & Deployment Workflow

## Repository Structure

```
gce-data-platform/
├── frontend/          # Next.js 14 SSR app (Azure Static Web Apps)
├── backend/           # ASP.NET Core 8 API (Azure App Service)
├── database/          # SQL DDL, DML seed scripts, migration scripts
└── .github/workflows/ # CI/CD pipelines
```

---

## Environments

| Environment | Frontend | Backend | Database |
|-------------|----------|---------|----------|
| **Local dev** | `http://localhost:3000` | `http://localhost:5062` | Your Azure SQL DEV db (via `az login`) |
| **Production** | `https://ambitious-stone-0a9d07003.7.azurestaticapps.net` | `https://app-gcplatform-web-weu-001-c2fyeebzh6hyhhf0.westeurope-01.azurewebsites.net` | `gce-db-dev` on `gce-sql-dev` |

---

## Local Development Setup

### Prerequisites
- Node.js 18+
- .NET 8 SDK
- Azure CLI (`az`) — for Managed Identity database auth locally
- Log in once: `az login`

### 1 — Backend

```bash
cd backend/GcePlatform.Api
dotnet run
# Runs on http://localhost:5062
```

The backend reads `appsettings.Development.json` automatically (ASPNETCORE_ENVIRONMENT defaults to Development locally).

**Connection string** lives in `appsettings.Development.json`:
```json
"ConnectionStrings": {
  "AzureSql": "Server=tcp:YOUR-SERVER.database.windows.net,1433;Database=YOUR-DB;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"
}
```

Update this value when you create a new DEV database. No password needed — `Authentication=Active Directory Default` uses your `az login` identity. This file is committed to git (no secrets, Managed Identity only).

### 2 — Frontend

Create `frontend/.env.local` (never committed — already in `.gitignore`):
```env
NEXT_PUBLIC_DEV_BYPASS=true
NEXT_PUBLIC_API_BASE_URL=http://localhost:5062
```

Then:
```bash
cd frontend
npm install
npm run dev
# Runs on http://localhost:3000
```

`NEXT_PUBLIC_DEV_BYPASS=true` skips Azure AD login entirely — one-click sign-in as a local dev user with all permissions granted. No Azure app registration needed locally.

---

## Git Workflow

### Branch strategy

```
main  ──────────────────────────────────────► production (auto-deploy)
         ▲           ▲
feature/xxx     feature/yyy
```

- `main` is always deployable and triggers production deploys automatically on push.
- Never commit directly to `main` for feature work — use feature branches.

### Starting a new feature

```bash
# Make sure you start from the latest main
git checkout main
git pull

# Create your feature branch
git checkout -b feature/my-feature-name
```

### During development

```bash
# Stage and commit as you go
git add <files>
git commit -m "describe what this commit does"

# Push your branch to GitHub (first time)
git push -u origin feature/my-feature-name

# Subsequent pushes
git push
```

### Merging to production

When the feature is stable and tested locally:

```bash
# Merge main into your branch first to resolve any conflicts
git checkout feature/my-feature-name
git pull origin main

# Fix any conflicts, then push
git push

# Switch to main and merge
git checkout main
git pull
git merge feature/my-feature-name
git push
```

Or open a Pull Request on GitHub for code review before merging.

---

## CI/CD — What Deploys When

### Frontend (Azure Static Web Apps)
- **Trigger**: any push to `main`
- **Pipeline**: `.github/workflows/azure-static-web-apps-ambitious-stone-0a9d07003.yml`
- **Duration**: ~3–5 minutes
- **Monitor**: GitHub → Actions tab

### Backend (Azure App Service)
- **Trigger**: push to `main` that changes files under `backend/`
- **Pipeline**: `.github/workflows/deploy-backend.yml`
- **Duration**: ~2–3 minutes
- **Monitor**: GitHub → Actions tab

> You can also trigger the backend deploy manually at any time:
> GitHub → Actions → "Deploy Backend" → Run workflow → main

---

## Database Migrations (EF Core)

The project uses EF Core exclusively for **migration management**. All runtime queries use Dapper. The EF context (`PlatformDbContext`) has no DbSets — it is a thin wrapper that gives `dotnet ef` a target.

### Migration inventory

| Migration ID | Description |
|---|---|
| `20260414000001_InitialCreate` | Full baseline DDL — use for empty-database restores |
| `20260414000002_AccountBranding` | Adds branding columns, updates `App.vAccounts`, adds `App.UpdateAccountBranding` |

### Common commands

Run from `backend/GcePlatform.Api/`:

```bash
# List migrations and their applied status
dotnet ef migrations list

# Apply all pending migrations (creates __EFMigrationsHistory if absent)
dotnet ef database update

# Roll back to a specific migration
dotnet ef database update 20260414000001_InitialCreate

# Add a new migration (generates the .cs files; write your SQL in the Up/Down methods)
dotnet ef migrations add MyNewChange
```

### Fresh database setup (empty DB)

```bash
# 1. Create the Azure SQL database
# 2. Grant your identity access (see below)
# 3. Update appsettings.Development.json with server/db name
# 4. Apply all migrations in one command:
dotnet ef database update
# 5. Optionally seed test data:
#    Run database/dml/seed_test_data.sql in SSMS / Azure Data Studio
```

### Production database (already populated, pre-branding)

The production DB was created before migrations were introduced. To adopt EF migrations without re-creating the database:

**Step 1** — Let EF create the `__EFMigrationsHistory` tracking table:

```sql
-- Run this in SSMS / Azure Data Studio against the production database
IF OBJECT_ID('__EFMigrationsHistory') IS NULL
CREATE TABLE [__EFMigrationsHistory] (
    [MigrationId]    NVARCHAR(150) NOT NULL,
    [ProductVersion] NVARCHAR(32)  NOT NULL,
    CONSTRAINT [PK___EFMigrationsHistory] PRIMARY KEY ([MigrationId])
);
```

**Step 2** — Mark the InitialCreate migration as already applied (the DB already has that schema):

```sql
INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES ('20260414000001_InitialCreate', '8.0.11');
```

**Step 3** — Apply only the pending migration(s):

```bash
# Authenticate with your Azure identity (device code flow works from any terminal)
az login --use-device-code

# Run from the API project directory, passing the production connection string
cd backend/GcePlatform.Api
dotnet ef database update --connection "Server=tcp:YOUR-PROD-SERVER.database.windows.net,1433;Database=YOUR-PROD-DB;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"
# Applies: 20260414000002_AccountBranding
```

Your `az login` identity must have `db_datareader`, `db_datawriter`, and `EXECUTE` permissions on the production database, plus `ALTER` rights to create tables and modify schema.

### Applying future migrations to production

Same two steps every time:

```bash
az login --use-device-code

cd backend/GcePlatform.Api
dotnet ef database update --connection "Server=tcp:YOUR-PROD-SERVER.database.windows.net,1433;Database=YOUR-PROD-DB;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"
```

EF checks `__EFMigrationsHistory` and only runs migrations that haven't been applied yet.

### Adding future migrations

1. Make your SQL changes in `baseline_create.sql` (keep the baseline current)
2. Run `dotnet ef migrations add YourMigrationName` — this creates empty migration files
3. In the generated `Up()` method, call `migrationBuilder.Sql("...", suppressTransaction: true)` with your DDL
4. Provide a matching `Down()` reversal
5. Test locally with `dotnet ef database update`
6. For production: `dotnet ef database update` (only the new migration runs — prior ones are already in `__EFMigrationsHistory`)

---

## Adding a New DEV Database

1. Create the Azure SQL database (Serverless recommended for dev cost)
2. Grant your identity access (see below)
3. Update `backend/GcePlatform.Api/appsettings.Development.json` with the new server/database name
4. Commit the updated `appsettings.Development.json`
5. Run migrations to create the schema:
   ```bash
   cd backend/GcePlatform.Api
   dotnet ef database update
   ```
6. Optionally seed test data by running `database/dml/seed_test_data.sql`

Grant your identity access (run in SSMS / Azure Data Studio):

```sql
CREATE USER [your-name@company.com] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [your-name@company.com];
ALTER ROLE db_datawriter ADD MEMBER [your-name@company.com];
GRANT EXECUTE TO [your-name@company.com];
```

---

## Updating Production Config

Production config lives in two places — prefer the file over the portal:

| Setting | Location |
|---------|----------|
| Connection string | `backend/GcePlatform.Api/appsettings.Production.json` (committed) |
| Allowed CORS origins | `backend/GcePlatform.Api/appsettings.Production.json` (committed) |
| Azure AD client/tenant IDs | Azure Portal → App Service → Environment variables |
| NextAuth secrets | Azure Portal → Static Web Apps → Configuration |
| Bootstrap super-admin UPN | Azure Portal → App Service → Environment variables (`PlatformSuperAdminUpn`) |

To update the connection string or CORS origins, edit `appsettings.Production.json`, commit, and push to `main`. The backend pipeline deploys automatically.

---

## Quick Reference

```bash
# Start local dev (both terminals)
cd backend/GcePlatform.Api && dotnet run
cd frontend && npm run dev

# New feature
git checkout main && git pull
git checkout -b feature/my-feature

# Deploy to production
git checkout main
git merge feature/my-feature
git push    # triggers CI/CD automatically

# Check production health
curl https://app-gcplatform-web-weu-001-c2fyeebzh6hyhhf0.westeurope-01.azurewebsites.net/health
```
