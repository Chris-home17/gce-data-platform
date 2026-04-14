using Microsoft.EntityFrameworkCore;

namespace GcePlatform.Api.Data;

/// <summary>
/// Minimal EF Core DbContext used exclusively for managing database migrations.
/// All runtime data access goes through Dapper via <see cref="DbConnectionFactory"/>.
/// This context deliberately has no DbSets — it only exists to give EF Core a target
/// for <c>dotnet ef migrations add</c> and <c>dotnet ef database update</c>.
/// </summary>
public class PlatformDbContext(DbContextOptions<PlatformDbContext> options) : DbContext(options)
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // No entity mappings — the schema is fully managed via raw SQL migrations.
    }
}
