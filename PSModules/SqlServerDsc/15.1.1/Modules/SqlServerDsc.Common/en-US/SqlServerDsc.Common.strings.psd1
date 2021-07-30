# Localized resources for helper module SqlServerDsc.Common.

ConvertFrom-StringData @'
    RobocopyIsCopying = Robocopy is copying media from source '{0}' to destination '{1}'. (SQLCOMMON0008)
    RobocopyUsingUnbufferedIo = Robocopy is using unbuffered I/O. (SQLCOMMON0009)
    RobocopyNotUsingUnbufferedIo = Unbuffered I/O cannot be used due to incompatible version of Robocopy. (SQLCOMMON0010)
    RobocopyArguments = Robocopy is started with the following arguments: {0} (SQLCOMMON0011)
    RobocopyErrorCopying = Robocopy reported errors when copying files. Error code: {0}. (SQLCOMMON0012)
    RobocopyFailuresCopying = Robocopy reported that failures occurred when copying files. Error code: {0}. (SQLCOMMON0013)
    RobocopySuccessful = Robocopy copied files successfully. (SQLCOMMON0014)
    RobocopyRemovedExtraFilesAtDestination = Robocopy found files at the destination path that is not present at the source path, these extra files was remove at the destination path. (SQLCOMMON0015)
    RobocopyAllFilesPresent = Robocopy reported that all files already present. (SQLCOMMON0016)
    StartSetupProcess = Started the process with id {0} using the path '{1}', and with a timeout value of {2} seconds. (SQLCOMMON0017)
    ConnectedToDatabaseEngineInstance = Connected to SQL instance '{0}'. (SQLCOMMON0018)
    FailedToConnectToDatabaseEngineInstance = Failed to connect to SQL instance '{0}'. (SQLCOMMON0019)
    ConnectedToAnalysisServicesInstance = Connected to Analysis Services instance '{0}'. (SQLCOMMON0020)
    FailedToConnectToAnalysisServicesInstance = Failed to connected to Analysis Services instance '{0}'. (SQLCOMMON0021)
    SqlServerVersionIsInvalid = Could not get the SQL version for the instance '{0}'. (SQLCOMMON0022)
    PreferredModuleFound = Preferred module SqlServer found. (SQLCOMMON0023)
    PreferredModuleNotFound = Information: PowerShell module SqlServer not found, trying to use older SQLPS module. (SQLCOMMON0024)
    ImportedPowerShellModule = Importing PowerShell module '{0}' with version '{1}' from path '{2}'. (SQLCOMMON0025)
    PowerShellModuleAlreadyImported = Found PowerShell module {0} already imported in the session. (SQLCOMMON0026)
    ModuleForceRemoval = Forcibly removed the SQL PowerShell module from the session to import it fresh again. (SQLCOMMON0027)
    DebugMessagePushingLocation = SQLPS module changes CWD to SQLSERVER:\ when loading, pushing location to pop it when module is loaded. (SQLCOMMON0028)
    DebugMessagePoppingLocation = Popping location back to what it was before importing SQLPS module. (SQLCOMMON0029)
    PowerShellSqlModuleNotFound = Neither PowerShell module SqlServer or SQLPS was found. Unable to run SQL Server cmdlets. (SQLCOMMON0030)
    FailedToImportPowerShellSqlModule = Failed to import {0} module. (SQLCOMMON0031)
    GetSqlServerClusterResources = Getting cluster resource for SQL Server. (SQLCOMMON0032)
    GetSqlAgentClusterResource = Getting active cluster resource SQL Server Agent. (SQLCOMMON0033)
    BringClusterResourcesOffline = Bringing the SQL Server resources '{0}' offline. (SQLCOMMON0034)
    BringSqlServerClusterResourcesOnline = Bringing the SQL Server resource back online. (SQLCOMMON0035)
    BringSqlServerAgentClusterResourcesOnline = Bringing the SQL Server Agent resource online. (SQLCOMMON0036)
    GetServiceInformation = Getting information about service '{0}'. (SQLCOMMON0037)
    RestartService = '{0}' service is restarting. (SQLCOMMON0038)
    StoppingService = '{0}' service is stopping. (SQLCOMMON0039)
    StartingService = '{0}' service is starting. (SQLCOMMON0040)
    WaitServiceRestart = Waiting {0} seconds before starting service '{1}'. (SQLCOMMON0041)
    StartingDependentService = Starting service '{0}'. (SQLCOMMON0042)
    WaitingInstanceTimeout = Waiting for instance {0}\\{1} to report status online, with a timeout value of {2} seconds. (SQLCOMMON0043)
    FailedToConnectToInstanceTimeout = Failed to connect to the instance {0}\\{1} within the timeout period of {2} seconds. (SQLCOMMON0044)
    ExecuteQueryWithResultsFailed = Executing query with results failed on database '{0}'. (SQLCOMMON0045)
    ExecuteNonQueryFailed = Executing non-query failed on database '{0}'. (SQLCOMMON0046)
    AlterAvailabilityGroupReplicaFailed = Failed to alter the availability group replica '{0}'. (SQLCOMMON0047)
    GetEffectivePermissionForLogin = Getting the effective permissions for the login '{0}' on '{1}'. (SQLCOMMON0048)
    ClusterPermissionsMissing = The cluster does not have permissions to manage the Availability Group on '{0}\\{1}'. Grant 'Connect SQL', 'Alter Any Availability Group', and 'View Server State' to either 'NT SERVICE\\ClusSvc' or 'NT AUTHORITY\\SYSTEM'. (SQLCOMMON0049)
    ClusterLoginMissing = The login '{0}' is not present. {1} (SQLCOMMON0050)
    ClusterLoginMissingPermissions = The account '{0}' is missing one or more of the following permissions: {1} (SQLCOMMON0051)
    ClusterLoginMissingRecommendedPermissions = The recommended account '{0}' is missing one or more of the following permissions: {1} (SQLCOMMON0052)
    ClusterLoginPermissionsPresent = The cluster login '{0}' has the required permissions. (SQLCOMMON0053)
    ConnectingUsingIntegrated = Connecting as current user '{0}' using integrated security. (SQLCOMMON0054)
    ConnectingUsingImpersonation = Impersonate credential '{0}' with login type '{1}'. (SQLCOMMON0056)
    ExecuteQueryWithResults = Returning the results of the query `{0}`. (SQLCOMMON0057)
    ExecuteNonQuery = Executing the query `{0}`. (SQLCOMMON0058)
    ClusterResourceNotFoundOrOffline = The SQL Server cluster resource '{0}' was not found or the resource has been taken offline. (SQLCOMMON0066)
    NotOwnerOfClusterResource = The node '{0}' is not the owner of the cluster resource '{1}'. The owner is '{2}' so no restart is needed. (SQLCOMMON0067)
    LoadedAssembly = Loaded the assembly '{0}'. (SQLCOMMON0068)
    FailedToLoadAssembly = Failed to load the assembly '{0}'. (SQLCOMMON0069)
    FailedToObtainServerInstance = Failed to obtain a SQL Server instance with name '{0}' on server '{1}'. Ensure the SQL Server instance exists on the server and that the 'SQLServer' module references a version of the 'Microsoft.SqlServer.Management.Smo.Wmi' library that supports the version of the SQL Server instance. (SQLCOMMON0070)
'@
