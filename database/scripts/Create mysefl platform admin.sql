  -- Replace <your-web-app-name> with your Azure Web App name (not the object ID)                                                                                         
  -- Azure SQL resolves the identity by name from Entra ID                                                                                                                
                                                                                                                                                                          
  CREATE USER [<your-web-app-name>] FROM EXTERNAL PROVIDER;                                                                                                               
                                                                                                                                                                          
  ALTER ROLE db_datareader ADD MEMBER [<your-web-app-name>];                                                                                                              
  ALTER ROLE db_datawriter ADD MEMBER [<your-web-app-name>];
  EXEC sp_addrolemember 'db_ddladmin', '<your-web-app-name>';

  -- Grant EXECUTE on all App schema procedures to the web app identity                                                                                                   
  GRANT EXECUTE ON SCHEMA::App TO [app-gcplatform-web-weu-001];                                                                                          
  GRANT EXECUTE ON SCHEMA::KPI TO [app-gcplatform-web-weu-001];  


  
  DECLARE @UserId INT;                                                                                                                                                    
  DECLARE @RoleId INT;
                                                                                                                                                                          
  EXEC App.UpsertUser                                       
      @UPN         = 'christophe.dewals@securitas.com',
      @DisplayName = 'Christophe Dewals',                                                                                                                                        
      @UserType    = 'Internal',
      @UserId      = @UserId OUTPUT;                                                                                                                                      
                                                            
  EXEC App.usp_UpsertPlatformRole                                                                                                                                         
      @RoleCode       = 'SUPER-ADMIN',
      @RoleName       = 'Super Administrator',                                                                                                                            
      @Description    = 'Full platform access - all permissions granted.',
      @PlatformRoleId = @RoleId OUTPUT;
                                                                                                                                                                          
  EXEC App.usp_SetPlatformRolePermissions
      @PlatformRoleId     = @RoleId,                                                                                                                                      
      @PermissionCodesCsv = 'platform.super_admin,accounts.manage,users.manage,grants.manage,kpi.manage,policies.manage,platform_roles.manage';
                                                                                                                                                                          
  EXEC App.usp_AddPlatformRoleMember
      @RoleCode = 'SUPER-ADMIN',                                                                                                                                          
      @UserUPN  = 'christophe.dewals@securitas.com';