using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace GcePlatform.Api.Data;

/// <summary>
/// Design-time factory that lets <c>dotnet ef</c> tooling create a
/// <see cref="PlatformDbContext"/> without starting the full ASP.NET Core host.
/// Reads the connection string from appsettings.json / appsettings.Development.json
/// in the project directory.
/// </summary>
public sealed class PlatformDbContextFactory : IDesignTimeDbContextFactory<PlatformDbContext>
{
    public PlatformDbContext CreateDbContext(string[] args)
    {
        var configuration = new ConfigurationBuilder()
            .SetBasePath(Directory.GetCurrentDirectory())
            .AddJsonFile("appsettings.json", optional: true)
            .AddJsonFile("appsettings.Development.json", optional: true)
            .AddEnvironmentVariables()
            .Build();

        var connectionString = configuration.GetConnectionString("AzureSql")
            ?? throw new InvalidOperationException(
                "ConnectionStrings:AzureSql is missing. " +
                "Ensure appsettings.Development.json is present in the project directory.");

        var optionsBuilder = new DbContextOptionsBuilder<PlatformDbContext>();
        optionsBuilder.UseSqlServer(connectionString);

        return new PlatformDbContext(optionsBuilder.Options);
    }
}
