using Microsoft.Data.SqlClient;

namespace GcePlatform.Api.Data;

/// <summary>
/// Opens SqlConnections using the connection string from configuration.
/// Authentication=Active Directory Default in the connection string means
/// Microsoft.Data.SqlClient delegates to Azure.Identity DefaultAzureCredential,
/// which uses az login credentials locally and Managed Identity in Azure.
/// No passwords or secrets are stored anywhere.
/// </summary>
public sealed class DbConnectionFactory
{
    private readonly string _connectionString;

    public DbConnectionFactory(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("AzureSql");
        if (string.IsNullOrWhiteSpace(_connectionString))
            throw new InvalidOperationException("ConnectionStrings:AzureSql is not configured or is empty.");
    }

    public SqlConnection CreateConnection() => new SqlConnection(_connectionString);
}
