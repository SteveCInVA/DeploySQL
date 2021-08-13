function Connect-DbaInstance {
    <#
    .SYNOPSIS
        Creates a robust, reusable SQL Server object.

    .DESCRIPTION
        This command creates a robust, reusable sql server object.

        It is robust because it initializes properties that do not cause enumeration by default. It also supports both Windows and SQL Server authentication methods, and detects which to use based upon the provided credentials.

        By default, this command also sets the connection's ApplicationName property  to "dbatools PowerShell module - dbatools.io - custom connection". If you're doing anything that requires profiling, you can look for this client name.

        Alternatively, you can pass in whichever client name you'd like using the -ClientName parameter. There are a ton of other parameters for you to explore as well.

        See https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnectionstringbuilder.aspx,
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.aspx

        To execute SQL commands, you can use $server.ConnectionContext.ExecuteReader($sql) or $server.Databases['master'].ExecuteNonQuery($sql)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server.

    .PARAMETER AppendConnectionString
        Appends to the current connection string. Note that you cannot pass authentication information using this method. Use -SqlInstance and optionally -SqlCredential to set authentication information.

    .PARAMETER ApplicationIntent
        Declares the application workload type when connecting to a server.

        Valid values are "ReadOnly" and "ReadWrite".

    .PARAMETER BatchSeparator
        A string to separate groups of SQL statements being executed. By default, this is "GO".

    .PARAMETER ClientName
        By default, this command sets the client's ApplicationName property to "dbatools PowerShell module - dbatools.io". If you're doing anything that requires profiling, you can look for this client name. Using -ClientName allows you to set your own custom client application name.

    .PARAMETER ConnectTimeout
        The length of time (in seconds) to wait for a connection to the server before terminating the attempt and generating an error.

        Valid values are integers between 0 and 2147483647.

        When opening a connection to a Azure SQL Database, set the connection timeout to 30 seconds.

    .PARAMETER EncryptConnection
        If this switch is enabled, SQL Server uses SSL encryption for all data sent between the client and server if the server has a certificate installed.

        For more information, see Connection String Syntax. https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/connection-string-syntax

        Beginning in .NET Framework 4.5, when TrustServerCertificate is false and Encrypt is true, the server name (or IP address) in a SQL Server SSL certificate must exactly match the server name (or IP address) specified in the connection string. Otherwise, the connection attempt will fail. For information about support for certificates whose subject starts with a wildcard character (*), see Accepted wildcards used by server certificates for server authentication. https://support.microsoft.com/en-us/help/258858/accepted-wildcards-used-by-server-certificates-for-server-authenticati

    .PARAMETER FailoverPartner
        The name of the failover partner server where database mirroring is configured.

        If the value of this key is "" (an empty string), then Initial Catalog must be present in the connection string, and its value must not be "".

        The server name can be 128 characters or less.

        If you specify a failover partner but the failover partner server is not configured for database mirroring and the primary server (specified with the Server keyword) is not available, then the connection will fail.

        If you specify a failover partner and the primary server is not configured for database mirroring, the connection to the primary server (specified with the Server keyword) will succeed if the primary server is available.

    .PARAMETER LockTimeout
        Sets the time in seconds required for the connection to time out when the current transaction is locked.

    .PARAMETER MaxPoolSize
        Sets the maximum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MinPoolSize
        Sets the minimum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MultipleActiveResultSets
        If this switch is enabled, an application can maintain multiple active result sets (MARS).

        If this switch is not enabled, an application must process or cancel all result sets from one batch before it can execute any other batch on that connection.

    .PARAMETER MultiSubnetFailover
        If this switch is enabled, and your application is connecting to an AlwaysOn availability group (AG) on different subnets, detection of and connection to the currently active server will be faster. For more information about SqlClient support for Always On Availability Groups, see https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/sql/sqlclient-support-for-high-availability-disaster-recovery

    .PARAMETER NetworkProtocol
        Explicitly sets the network protocol used to connect to the server.

        Valid values are "TcpIp","NamedPipes","Multiprotocol","AppleTalk","BanyanVines","Via","SharedMemory" and "NWLinkIpxSpx"

    .PARAMETER NonPooledConnection
        If this switch is enabled, a non-pooled connection will be requested.

    .PARAMETER PacketSize
        Sets the size in bytes of the network packets used to communicate with an instance of SQL Server. Must match at server.

    .PARAMETER PooledConnectionLifetime
        When a connection is returned to the pool, its creation time is compared with the current time and the connection is destroyed if that time span (in seconds) exceeds the value specified by Connection Lifetime. This is useful in clustered configurations to force load balancing between a running server and a server just brought online.

        A value of zero (0) causes pooled connections to have the maximum connection timeout.

    .PARAMETER SqlExecutionModes
        The SqlExecutionModes enumeration contains values that are used to specify whether the commands sent to the referenced connection to the server are executed immediately or saved in a buffer.

        Valid values include "CaptureSql", "ExecuteAndCaptureSql" and "ExecuteSql".

    .PARAMETER StatementTimeout
        Sets the number of seconds a statement is given to run before failing with a timeout error.

        The default is read from the configuration 'sql.execution.timeout' that is currently set to 0 (unlimited).
        If you want to change this to 10 minutes, use: Set-DbatoolsConfig -FullName 'sql.execution.timeout' -Value 600

    .PARAMETER TrustServerCertificate
        When this switch is enabled, the channel will be encrypted while bypassing walking the certificate chain to validate trust.

    .PARAMETER WorkstationId
        Sets the name of the workstation connecting to SQL Server.

    .PARAMETER SqlConnectionOnly
        Instead of returning a rich SMO server object, this command will only return a SqlConnection object when setting this switch.

    .PARAMETER AzureUnsupported
        Terminate if Azure is detected but not supported

    .PARAMETER AzureDomain
        By default, this is set to database.windows.net

        In the event your AzureSqlDb is not on a database.windows.net domain, you can set a custom domain using the AzureDomain parameter.
        This tells Connect-DbaInstance to login to the database using the method that works best with Azure.

    .PARAMETER MinimumVersion
        Terminate if the target SQL Server instance version does not meet version requirements

    .PARAMETER AuthenticationType
        Not used in the current version.

    .PARAMETER Tenant
        The TenantId for an Azure Instance

    .PARAMETER Thumbprint
        Not used in the current version.

    .PARAMETER Store
        Not used in the current version.

    .PARAMETER AccessToken
        Connect to an Azure SQL Database or an Azure SQL Managed Instance with an AccessToken, that has to be generated with Get-AzAccessToken.
        Note that the token is valid for only one hour and cannot be renewed automatically.

    .PARAMETER DedicatedAdminConnection
        Connects using "ADMIN:" to create a dedicated admin connection (DAC) as a non-pooled connection.
        If the instance is on a remote server, the remote access has to be enabled via "Set-DbaSpConfigure -Name RemoteDacConnectionsEnabled -Value $true" or "sp_configure 'remote admin connections', 1".
        The connection will not be closed if the variable holding the Server SMO is going out of scope, so it is very important to call .ConnectionContext.Disconnect() to close the connection. See example.

    .PARAMETER DisableException
        By default in most of our commands, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This command, however, gifts you  with "sea of red" exceptions, by default, because it is useful for advanced scripting.

        Using this switch turns our "nice by default" feature on which makes errors into pretty warnings.

    .NOTES
        Tags: Connect, Connection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Connect-DbaInstance

    .EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance sql2014

        Creates an SMO Server object that connects using Windows Authentication

    .EXAMPLE
        PS C:\> $wincred = Get-Credential ad\sqladmin
        PS C:\> Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $wincred

        Creates an SMO Server object that connects using alternative Windows credentials

    .EXAMPLE
        PS C:\> $sqlcred = Get-Credential sqladmin
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $sqlcred

        Login to sql2014 as SQL login sqladmin.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -ClientName "my connection"

        Creates an SMO Server object that connects using Windows Authentication and uses the client name "my connection".
        So when you open up profiler or use extended events, you can search for "my connection".

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -AppendConnectionString "Packet Size=4096;AttachDbFilename=C:\MyFolder\MyDataFile.mdf;User Instance=true;"

        Creates an SMO Server object that connects to sql2014 using Windows Authentication, then it sets the packet size (this can also be done via -PacketSize) and other connection attributes.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -NetworkProtocol TcpIp -MultiSubnetFailover

        Creates an SMO Server object that connects using Windows Authentication that uses TCP/IP and has MultiSubnetFailover enabled.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance sql2016 -ApplicationIntent ReadOnly

        Connects with ReadOnly ApplicationIntent.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL DB using AAD / Azure Active Directory, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database dbatools -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL DB using AAD Integrated Auth, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance "myserver.public.cust123.database.windows.net,3342" -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL Managed instance using AAD / Azure Active Directory, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance db.mycustomazure.com -Database mydb -AzureDomain mycustomazure.com -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        In the event your AzureSqlDb is not on a database.windows.net domain, you can set a custom domain using the AzureDomain parameter.
        This tells Connect-DbaInstance to login to the database using the method that works best with Azure.

    .EXAMPLE
        PS C:\> $connstring = "Data Source=TCP:mydb.database.windows.net,1433;User ID=sqladmin;Password=adfasdf;Connect Timeout=30;"
        PS C:\> $server = Connect-DbaInstance -ConnectionString $connstring
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure using a preconstructed connstring, then performs a sample query.
        ConnectionString is an alias of SqlInstance, so you can use -SqlInstance $connstring as well.

    .EXAMPLE
        PS C:\> $cred = Get-Credential guid-app-id-here # appid for username, clientsecret for password
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database abc -SqCredential $cred -Tenant guidheremaybename
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        When connecting from a non-Azure workstation, logs into Azure using Universal with MFA Support with a username and password, then performs a sample query.

        Note that generating access tokens is not supported on Core, so when using Tenant on Core, we rewrite the connection string with Active Directory Service Principal authentication instead.

    .EXAMPLE
        PS C:\> $cred = Get-Credential guid-app-id-here # appid for username, clientsecret for password
        PS C:\> Set-DbatoolsConfig -FullName azure.tenantid -Value 'guidheremaybename' -Passthru | Register-DbatoolsConfig
        PS C:\> Set-DbatoolsConfig -FullName azure.appid -Value $cred.Username -Passthru | Register-DbatoolsConfig
        PS C:\> Set-DbatoolsConfig -FullName azure.clientsecret -Value $cred.Password -Passthru | Register-DbatoolsConfig # requires securestring
        PS C:\> Set-DbatoolsConfig -FullName sql.connection.database -Value abc -Passthru | Register-DbatoolsConfig
        PS C:\> Connect-DbaInstance -SqlInstance psdbatools.database.windows.net

        Permanently sets some app id config values. To set them temporarily (just for a session), remove -Passthru | Register-DbatoolsConfig
        When connecting from a non-Azure workstation or an Azure VM without .NET 4.7.2 and higher, logs into Azure using Universal with MFA Support, then performs a sample query.

    .EXAMPLE
        PS C:\> $azureCredential = Get-Credential -Message 'Azure Credential'
        PS C:\> $azureAccount = Connect-AzAccount -Credential $azureCredential
        PS C:\> $azureToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token
        PS C:\> $azureInstance = "YOURSERVER.database.windows.net"
        PS C:\> $azureDatabase = "MYDATABASE"
        PS C:\> $server = Connect-DbaInstance -SqlInstance $azureInstance -Database $azureDatabase -AccessToken $azureToken
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Connect to an Azure SQL Database or an Azure SQL Managed Instance with an AccessToken.
        Note that the token is valid for only one hour and cannot be renewed automatically.

    .EXAMPLE
        PS C:\> $token = (New-DbaAzAccessToken -Type RenewableServicePrincipal -Subtype AzureSqlDb -Tenant $tenantid -Credential $cred).GetAccessToken()
        PS C:\> Connect-DbaInstance -SqlInstance sample.database.windows.net -Accesstoken $token

        Uses dbatools to generate the access token for an Azure SQL Database, then logs in using that AccessToken.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance srv1 -DedicatedAdminConnection
        PS C:\> $dbaProcess = Get-DbaProcess -SqlInstance $server -ExcludeSystemSpids
        PS C:\> $killedProcess = $dbaProcess | Out-GridView -OutputMode Multiple | Stop-DbaProcess
        PS C:\> $server | Disconnect-DbaInstance

        Creates a dedicated admin connection (DAC) to the default instance on server srv1.
        Receives all non-system processes from the instance using the DAC.
        Opens a grid view to let the user select processes to be stopped.
        Closes the connection.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("Connstring", "ConnectionString")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database = (Get-DbatoolsConfigValue -FullName 'sql.connection.database'),
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$ApplicationIntent,
        [switch]$AzureUnsupported,
        [string]$BatchSeparator,
        [string]$ClientName = (Get-DbatoolsConfigValue -FullName 'sql.connection.clientname'),
        [int]$ConnectTimeout = ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout),
        [switch]$EncryptConnection = (Get-DbatoolsConfigValue -FullName 'sql.connection.encrypt'),
        [string]$FailoverPartner,
        [int]$LockTimeout,
        [int]$MaxPoolSize,
        [int]$MinPoolSize,
        [int]$MinimumVersion,
        [switch]$MultipleActiveResultSets,
        [switch]$MultiSubnetFailover = (Get-DbatoolsConfigValue -FullName 'sql.connection.multisubnetfailover'),
        [ValidateSet('TcpIp', 'NamedPipes', 'Multiprotocol', 'AppleTalk', 'BanyanVines', 'Via', 'SharedMemory', 'NWLinkIpxSpx')]
        [string]$NetworkProtocol = (Get-DbatoolsConfigValue -FullName 'sql.connection.protocol'),
        [switch]$NonPooledConnection,
        [int]$PacketSize = (Get-DbatoolsConfigValue -FullName 'sql.connection.packetsize'),
        [int]$PooledConnectionLifetime,
        [ValidateSet('CaptureSql', 'ExecuteAndCaptureSql', 'ExecuteSql')]
        [string]$SqlExecutionModes,
        [int]$StatementTimeout = (Get-DbatoolsConfigValue -FullName 'sql.execution.timeout'),
        [switch]$TrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.trustcert'),
        [string]$WorkstationId,
        [string]$AppendConnectionString,
        [switch]$SqlConnectionOnly,
        [string]$AzureDomain = "database.windows.net",
        #[ValidateSet('Auto', 'Windows Authentication', 'SQL Server Authentication', 'AD Universal with MFA Support', 'AD - Password', 'AD - Integrated')]
        [ValidateSet('Auto', 'AD Universal with MFA Support')]
        [string]$AuthenticationType = "Auto",
        [string]$Tenant = (Get-DbatoolsConfigValue -FullName 'azure.tenantid'),
        [string]$Thumbprint = (Get-DbatoolsConfigValue -FullName 'azure.certificate.thumbprint'),
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Store = (Get-DbatoolsConfigValue -FullName 'azure.certificate.store'),
        [string]$AccessToken,
        [switch]$DedicatedAdminConnection,
        [switch]$DisableException
    )
    begin {
        $azurevm = Get-DbatoolsConfigValue -FullName azure.vm
        #region Utility functions
        if ($Tenant -or $AuthenticationType -in 'AD Universal with MFA Support', 'AD - Password', 'AD - Integrated' -and ($null -eq $azurevm)) {
            Write-Message -Level Verbose -Message "Determining if current workstation is an Azure VM"
            # Do an Azure check - this will occur just once
            try {
                $azurevmcheck = Invoke-RestMethod -Headers @{"Metadata" = "true" } -Uri http://169.254.169.254/metadata/instance?api-version=2018-10-01 -Method GET -TimeoutSec 2 -ErrorAction Stop
                if ($azurevmcheck.compute.azEnvironment) {
                    $azurevm = $true
                    $null = Set-DbatoolsConfig -FullName azure.vm -Value $true -PassThru | Register-DbatoolsConfig
                } else {
                    $null = Set-DbatoolsConfig -FullName azure.vm -Value $false -PassThru | Register-DbatoolsConfig
                }
            } catch {
                $null = Set-DbatoolsConfig -FullName azure.vm -Value $false -PassThru | Register-DbatoolsConfig
            }
        }
        function Test-Azure {
            Param (
                [DbaInstanceParameter]$SqlInstance
            )
            if ($SqlInstance.ComputerName -match $AzureDomain -or $instance.InputObject.ComputerName -match $AzureDomain) {
                Write-Message -Level Debug -Message "Test for Azure is positive"
                return $true
            } else {
                Write-Message -Level Debug -Message "Test for Azure is negative"
                return $false
            }
        }
        function Invoke-TEPPCacheUpdate {
            [CmdletBinding()]
            param (
                [System.Management.Automation.ScriptBlock]$ScriptBlock
            )

            try {
                [ScriptBlock]::Create($scriptBlock).Invoke()
            } catch {
                # If the SQL Server version doesn't support the feature, we ignore it and silently continue
                if ($_.Exception.InnerException.InnerException.GetType().FullName -eq "Microsoft.SqlServer.Management.Sdk.Sfc.InvalidVersionEnumeratorException") {
                    return
                }

                if ($ENV:APPVEYOR_BUILD_FOLDER -or ([Sqlcollaborative.Dbatools.Message.MEssageHost]::DeveloperMode)) { Stop-Function -Message }
                else {
                    Write-Message -Level Warning -Message "Failed TEPP Caching: $($scriptBlock.ToString() | Select-String '"(.*?)"' | ForEach-Object { $_.Matches[0].Groups[1].Value })" -ErrorRecord $_ 3>$null
                }
            }
        }
        #endregion Utility functions

        #region Ensure Credential integrity
        <#
        Usually, the parameter type should have been not object but off the PSCredential type.
        When binding null to a PSCredential type parameter on PS3-4, it'd then show a prompt, asking for username and password.

        In order to avoid that and having to refactor lots of functions (and to avoid making regular scripts harder to read), we created this workaround.
        #>
        if ($SqlCredential) {
            if ($SqlCredential.GetType() -ne [System.Management.Automation.PSCredential]) {
                Stop-Function -Message "The credential parameter was of a non-supported type. Only specify PSCredentials such as generated from Get-Credential. Input was of type $($SqlCredential.GetType().FullName)"
                return
            }
        }
        #endregion Ensure Credential integrity

        # In an unusual move, Connect-DbaInstance goes the exact opposite way of all commands when it comes to exceptions
        # this means that by default it Stop-Function -Messages, but do not be tempted to Stop-Function -Message
        if ($DisableException) {
            $EnableException = $false
        } else {
            $EnableException = $true
        }

        $loadedSmoVersion = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
            $_.Fullname -like "Microsoft.SqlServer.SMO,*"
        }

        if ($loadedSmoVersion) {
            $loadedSmoVersion = $loadedSmoVersion | ForEach-Object {
                if ($_.Location -match "__") {
                    ((Split-Path (Split-Path $_.Location) -Leaf) -split "__")[0]
                } else {
                    ((Get-ChildItem -Path $_.Location).VersionInfo.ProductVersion)
                }
            }
        }

        #'PrimaryFilePath' seems the culprit for slow SMO on databases
        $Fields2000_Db = 'Collation', 'CompatibilityLevel', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsSystemObject', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'ReadOnly', 'RecoveryModel', 'ReplicationOptions', 'Status', 'Version'
        $Fields200x_Db = $Fields2000_Db + @('BrokerEnabled', 'DatabaseSnapshotBaseName', 'IsMirroringEnabled', 'Trustworthy')
        $Fields201x_Db = $Fields200x_Db + @('ActiveConnections', 'AvailabilityDatabaseSynchronizationState', 'AvailabilityGroupName', 'ContainmentType', 'EncryptionEnabled')

        $Fields2000_Login = 'CreateDate', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'Name', 'Sid', 'WindowsLoginAccessType'
        $Fields200x_Login = $Fields2000_Login + @('AsymmetricKey', 'Certificate', 'Credential', 'ID', 'IsDisabled', 'IsLocked', 'IsPasswordExpired', 'MustChangePassword', 'PasswordExpirationEnabled', 'PasswordPolicyEnforced')
        $Fields201x_Login = $Fields200x_Login + @('PasswordHashAlgorithm')
        if ($AzureDomain) { $AzureDomain = [regex]::escape($AzureDomain) }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        # if tenant is specified with a GUID username such as 21f5633f-6776-4bab-b878-bbd5e3e5ed72 (for clientid)
        if ($Tenant -and -not $AccessToken -and $SqlCredential.UserName -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {

            try {
                if ($PSVersionTable.PSEdition -eq "Core") {
                    Write-Message -Level Verbose "Generating access tokens is not supported on Core. Will try connection string with Active Directory Service Principal instead. See https://github.com/sqlcollaborative/dbatools/pull/7610 for more information."
                    $tryconnstring = $true
                } else {
                    Write-Message -Level Verbose "Tenant detected, getting access token"
                    $AccessToken = (New-DbaAzAccessToken -Type RenewableServicePrincipal -Subtype AzureSqlDb -Tenant $Tenant -Credential $SqlCredential -ErrorAction Stop).GetAccessToken()
                    $PSBoundParameters.Tenant = $Tenant = $null
                    $PSBoundParameters.SqlCredential = $SqlCredential = $null
                    $PSBoundParameters.AccessToken = $AccessToken
                }

            } catch {
                $errormessage = Get-ErrorMessage -Record $_
                Stop-Function -Message "Failed to get access token for Azure SQL DB ($errormessage)"
                return
            }
        }

        Write-Message -Level Debug -Message "Starting process block"
        foreach ($instance in $SqlInstance) {
            if ($tryconnstring) {
                $azureserver = $instance.InputObject
                if ($Database) {
                    $instance = [DbaInstanceParameter]"Server=$azureserver; Authentication=Active Directory Service Principal; Database=$Database; User Id=$($SqlCredential.UserName); Password=$($SqlCredential.GetNetworkCredential().Password)"
                } else {
                    $instance = [DbaInstanceParameter]"Server=$azureserver; Authentication=Active Directory Service Principal; User Id=$($SqlCredential.UserName); Password=$($SqlCredential.GetNetworkCredential().Password)"
                }
            }

            Write-Message -Level Debug -Message "Immediately checking for Azure"
            if ((Test-Azure -SqlInstance $instance)) {
                Write-Message -Level Verbose -Message "Azure detected"
                $IsAzure = $true
            } else {
                $IsAzure = $false
            }
            Write-Message -Level Debug -Message "Starting loop for '$instance': ComputerName = '$($instance.ComputerName)', InstanceName = '$($instance.InstanceName)', IsLocalHost = '$($instance.IsLocalHost)', Type = '$($instance.Type)'"

            <#
            The new code path (formerly known as experimental) is now the default.
            To have a quick way to switch back in case any problems occur, the switch "legacy" is introduced: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true
            #>

            if (-not (Get-DbatoolsConfigValue -FullName sql.connection.legacy)) {
                <#
                Best practice:
                * Create a smo server object by submitting the name of the instance as a string to SqlInstance and additional parameters to configure the connection
                * Reuse the smo server object in all following calls as SqlInstance
                * When reusing the smo server object, only the following additional parameters are allowed with Connect-DbaInstance:
                  - Database, ApplicationIntent, NonPooledConnection, StatementTimeout (command clones ConnectionContext and returns new smo server object)
                  - AzureUnsupported (command fails if target is Azure)
                  - MinimumVersion (command fails if target version is too old)
                  - SqlConnectionOnly (command returns only the ConnectionContext.SqlConnectionObject)
                Commands that use these parameters:
                * ApplicationIntent
                  - Invoke-DbaQuery
                * NonPooledConnection
                  - Install-DbaFirstResponderKit
                * StatementTimeout (sometimes not as a parameter, they should changed to do so)
                  - Backup-DbaDatabase
                  - Restore-DbaDatabase
                  - Get-DbaTopResourceUsage
                  - Import-DbaCsv
                  - Invoke-DbaDbLogShipping
                  - Invoke-DbaDbShrink
                  - Invoke-DbaDbUpgrade
                  - Set-DbaDbCompression
                  - Test-DbaDbCompression
                  - Start-DbccCheck
                * AzureUnsupported
                  - Backup-DbaDatabase
                  - Copy-DbaLogin
                  - Get-DbaLogin
                  - Set-DbaLogin
                  - Get-DbaDefaultPath
                  - Get-DbaUserPermissions
                  - Get-DbaXESession
                  - New-DbaCustomError
                  - Remove-DbaCustomError
                Additional possibilities as input to SqlInstance:
                * A smo connection object [Microsoft.Data.SqlClient.SqlConnection] (InputObject is used to build smo server object)
                * A smo registered server object [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer] (FullSmoName und InputObject.ConnectionString are used to build smo server object)
                * A connections string [String] (FullSmoName und InputObject are used to build smo server object)
                Limitations of these additional possibilities:
                * All additional parameters are ignored, a warning is displayed if they are used
                * Currently, connection pooling does not work with connections that are build from connection strings
                * All parameters that configure the connection and where they can be set (here just for documentation and future development):
                  - AppendConnectionString      SqlConnectionInfo.AdditionalParameters
                  - ApplicationIntent           SqlConnectionInfo.ApplicationIntent          SqlConnectionStringBuilder['ApplicationIntent']
                  - AuthenticationType          SqlConnectionInfo.Authentication             SqlConnectionStringBuilder['Authentication']
                  - BatchSeparator                                                                                                                     ConnectionContext.BatchSeparator
                  - ClientName                  SqlConnectionInfo.ApplicationName            SqlConnectionStringBuilder['Application Name']
                  - ConnectTimeout              SqlConnectionInfo.ConnectionTimeout          SqlConnectionStringBuilder['Connect Timeout']
                  - Database                    SqlConnectionInfo.DatabaseName               SqlConnectionStringBuilder['Initial Catalog']
                  - EncryptConnection           SqlConnectionInfo.EncryptConnection          SqlConnectionStringBuilder['Encrypt']
                  - FailoverPartner             SqlConnectionInfo.AdditionalParameters       SqlConnectionStringBuilder['Failover Partner']
                  - LockTimeout                                                                                                                        ConnectionContext.LockTimeout
                  - MaxPoolSize                 SqlConnectionInfo.MaxPoolSize                SqlConnectionStringBuilder['Max Pool Size']
                  - MinPoolSize                 SqlConnectionInfo.MinPoolSize                SqlConnectionStringBuilder['Min Pool Size']
                  - MultipleActiveResultSets                                                 SqlConnectionStringBuilder['MultipleActiveResultSets']    ConnectionContext.MultipleActiveResultSets
                  - MultiSubnetFailover         SqlConnectionInfo.AdditionalParameters       SqlConnectionStringBuilder['MultiSubnetFailover']
                  - NetworkProtocol             SqlConnectionInfo.ConnectionProtocol
                  - NonPooledConnection         SqlConnectionInfo.Pooled                     SqlConnectionStringBuilder['Pooling']
                  - PacketSize                  SqlConnectionInfo.PacketSize                 SqlConnectionStringBuilder['Packet Size']
                  - PooledConnectionLifetime    SqlConnectionInfo.PoolConnectionLifeTime     SqlConnectionStringBuilder['Load Balance Timeout']
                  - SqlInstance                 SqlConnectionInfo.ServerName                 SqlConnectionStringBuilder['Data Source']
                  - SqlCredential               SqlConnectionInfo.SecurePassword             SqlConnectionStringBuilder['Password']
                                                SqlConnectionInfo.UserName                   SqlConnectionStringBuilder['User ID']
                                                SqlConnectionInfo.UseIntegratedSecurity      SqlConnectionStringBuilder['Integrated Security']
                  - SqlExecutionModes                                                                                                                  ConnectionContext.SqlExecutionModes
                  - StatementTimeout            (SqlConnectionInfo.QueryTimeout?)                                                                      ConnectionContext.StatementTimeout
                  - TrustServerCertificate      SqlConnectionInfo.TrustServerCertificate     SqlConnectionStringBuilder['TrustServerCertificate']
                  - WorkstationId               SqlConnectionInfo.WorkstationId              SqlConnectionStringBuilder['Workstation Id']

                Some additional tests:
                * Is $AzureUnsupported set? Test for Azure.
                * Is $MinimumVersion set? Test for that.
                * Is $SqlConnectionOnly set? Then return $server.ConnectionContext.SqlConnectionObject.
                * Does the server object have the additional properties? Add them when necessary.

                Some general decisions:
                * We try to treat connections to Azure as normal connections.
                * Not every edge case will be covered at the beginning.
                * We copy as less code from the existing code paths as possible.
                #>

                # Analyse input object and extract necessary parts
                if ($instance.Type -like 'Server') {
                    Write-Message -Level Verbose -Message "Server object passed in, will do some checks and then return the original object"
                    $inputObjectType = 'Server'
                    $inputObject = $instance.InputObject
                } elseif ($instance.Type -like 'SqlConnection') {
                    Write-Message -Level Verbose -Message "SqlConnection object passed in, will build server object from instance.InputObject, do some checks and then return the server object"
                    $inputObjectType = 'SqlConnection'
                    $inputObject = $instance.InputObject
                } elseif ($instance.Type -like 'RegisteredServer') {
                    Write-Message -Level Verbose -Message "RegisteredServer object passed in, will build empty server object, set connection string from instance.InputObject.ConnectionString, do some checks and then return the server object"
                    $inputObjectType = 'RegisteredServer'
                    $inputObject = $instance.InputObject
                    $serverName = $instance.FullSmoName
                    $connectionString = $instance.InputObject.ConnectionString
                } elseif ($instance.IsConnectionString) {
                    Write-Message -Level Verbose -Message "Connection string is passed in, will build empty server object, set connection string from instance.InputObject, do some checks and then return the server object"
                    $inputObjectType = 'ConnectionString'
                    $serverName = $instance.FullSmoName
                    $connectionString = $instance.InputObject
                } else {
                    Write-Message -Level Verbose -Message "String is passed in, will build server object from instance object and other parameters, do some checks and then return the server object"
                    $inputObjectType = 'String'
                    $serverName = $instance.FullSmoName
                }

                # Check for ignored parameters
                # We do not check for SqlCredential as this parameter is widly used even if a server SMO is passed in and we don't want to outout a message for that
                $ignoredParameters = 'BatchSeparator', 'ClientName', 'ConnectTimeout', 'EncryptConnection', 'LockTimeout', 'MaxPoolSize', 'MinPoolSize', 'NetworkProtocol', 'PacketSize', 'PooledConnectionLifetime', 'SqlExecutionModes', 'TrustServerCertificate', 'WorkstationId', 'AuthenticationType', 'FailoverPartner', 'MultipleActiveResultSets', 'MultiSubnetFailover', 'AppendConnectionString', 'AccessToken'
                if ($inputObjectType -eq 'Server') {
                    if (Test-Bound -ParameterName $ignoredParameters) {
                        Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                    }
                } elseif ($inputObjectType -in 'RegisteredServer', 'ConnectionString' ) {
                    if (Test-Bound -ParameterName $ignoredParameters, 'ApplicationIntent', 'StatementTimeout') {
                        Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                    }
                } elseif ($inputObjectType -in 'SqlConnection' ) {
                    if (Test-Bound -ParameterName $ignoredParameters, 'ApplicationIntent', 'StatementTimeout', 'DedicatedAdminConnection') {
                        Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                    }
                }

                if ($DedicatedAdminConnection -and $serverName) {
                    Write-Message -Level Debug -Message "Parameter DedicatedAdminConnection is used, so serverName will be changed and NonPooledConnection will be set."
                    $serverName = 'ADMIN:' + $serverName
                    $NonPooledConnection = $true
                }

                # Create smo server object
                if ($inputObjectType -eq 'Server') {
                    # Test if we have to copy the connection context
                    # Currently only if we have a different Database or have to swith to a NonPooledConnection or using a specific StatementTimeout or using ApplicationIntent
                    # We do not test for SqlCredential as this would change the behavior compared to the legacy code path
                    $copyContext = $false
                    if ($Database -and $inputObject.ConnectionContext.CurrentDatabase -ne $Database) {
                        Write-Message -Level Verbose -Message "Database provided. Does not match ConnectionContext.CurrentDatabase, copying ConnectionContext and setting the CurrentDatabase"
                        $copyContext = $true
                    }
                    if ($ApplicationIntent -and $inputObject.ConnectionContext.ApplicationIntent -ne $ApplicationIntent) {
                        Write-Message -Level Verbose -Message "ApplicationIntent provided. Does not match ConnectionContext.ApplicationIntent, copying ConnectionContext and setting the ApplicationIntent"
                        $copyContext = $true
                    }
                    if ($NonPooledConnection -and -not $inputObject.ConnectionContext.NonPooledConnection) {
                        Write-Message -Level Verbose -Message "NonPooledConnection provided. Does not match ConnectionContext.NonPooledConnection, copying ConnectionContext and setting NonPooledConnection"
                        $copyContext = $true
                    }
                    if (Test-Bound -Parameter StatementTimeout -and $inputObject.ConnectionContext.StatementTimeout -ne $StatementTimeout) {
                        Write-Message -Level Verbose -Message "StatementTimeout provided. Does not match ConnectionContext.StatementTimeout, copying ConnectionContext and setting the StatementTimeout"
                        $copyContext = $true
                    }
                    if ($DedicatedAdminConnection -and $inputObject.ConnectionContext.ServerInstance -notmatch '^ADMIN:') {
                        Write-Message -Level Verbose -Message "DedicatedAdminConnection provided. Does not match ConnectionContext.ServerInstance, copying ConnectionContext and setting the ServerInstance"
                        $copyContext = $true
                    }
                    if ($copyContext) {
                        $connContext = $inputObject.ConnectionContext.Copy()
                        if ($ApplicationIntent) {
                            $connContext.ApplicationIntent = $ApplicationIntent
                        }
                        if ($NonPooledConnection) {
                            $connContext.NonPooledConnection = $true
                        }
                        if (Test-Bound -Parameter StatementTimeout) {
                            $connContext.StatementTimeout = $StatementTimeout
                        }
                        if ($DedicatedAdminConnection -and $inputObject.ConnectionContext.ServerInstance -notmatch '^ADMIN:') {
                            $connContext.ServerInstance = 'ADMIN:' + $connContext.ServerInstance
                            $connContext.NonPooledConnection = $true
                        }
                        if ($Database) {
                            $connContext = $connContext.GetDatabaseConnection($Database)
                        }
                        $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $connContext
                    } else {
                        $server = $inputObject
                    }
                } elseif ($inputObjectType -eq 'SqlConnection') {
                    $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $inputObject
                } elseif ($inputObjectType -in 'RegisteredServer', 'ConnectionString') {
                    $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $serverName
                    $server.ConnectionContext.ConnectionString = $connectionString
                } elseif ($inputObjectType -eq 'String') {
                    # Test for unsupported parameters
                    # TODO: Thumbprint and Store are not used in legacy code path and should be removed.
                    if ($Thumbprint) {
                        Stop-Function -Target $instance -Message "Parameter Thumbprint is not supported at this time."
                        return
                    }
                    if ($Store) {
                        Stop-Function -Target $instance -Message "Parameter Store is not supported at this time."
                        return
                    }

                    # Identify authentication method
                    if ($AuthenticationType -ne 'Auto') {
                        Stop-Function -Target $instance -Message 'AuthenticationType "AD Universal with MFA Support" is only supported in the legacy code path. Run "Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true" to deactivate the new code path and use the legacy code path.'
                        return
                    } else {
                        if (Test-Azure -SqlInstance $instance) {
                            $authType = 'azure '
                        } else {
                            $authType = 'local '
                        }
                        if ($SqlCredential) {
                            # support both ad\username and username@ad
                            $username = ($SqlCredential.UserName).TrimStart("\")
                            if ($username -like "*\*") {
                                $domain, $login = $username.Split("\")
                                $username = "$login@$domain"
                            }
                            if ($username -like '*@*') {
                                $authType += 'ad'
                            } else {
                                $authType += 'sql'
                            }
                        } elseif ($AccessToken) {
                            $authType += 'token'
                        } else {
                            $authType += 'integrated'
                        }
                    }
                    Write-Message -Level Verbose -Message "authentication method is '$authType'"

                    # Best way to get connection pooling to work is to use SqlConnectionInfo -> ServerConnection -> Server
                    $sqlConnectionInfo = New-Object -TypeName Microsoft.SqlServer.Management.Common.SqlConnectionInfo -ArgumentList $serverName

                    # But if we have an AccessToken, we need ConnectionString -> SqlConnection -> ServerConnection -> Server
                    # We will get the ConnectionString from the SqlConnectionInfo, so let's move on

                    # I will list all properties of SqlConnectionInfo and set them if value is provided

                    #AccessToken            Property   Microsoft.SqlServer.Management.Common.IRenewableToken AccessToken {get;set;}
                    # This parameter needs an IRenewableToken and we currently support only a non renewable token

                    #AdditionalParameters   Property   string AdditionalParameters {get;set;}
                    if ($AppendConnectionString) {
                        Write-Message -Level Debug -Message "AdditionalParameters will be appended by '$AppendConnectionString;'"
                        $sqlConnectionInfo.AdditionalParameters += "$AppendConnectionString;"
                    }
                    if ($FailoverPartner) {
                        Write-Message -Level Debug -Message "AdditionalParameters will be appended by 'FailoverPartner=$FailoverPartner;'"
                        $sqlConnectionInfo.AdditionalParameters += "FailoverPartner=$FailoverPartner;"
                    }
                    if ($MultiSubnetFailover) {
                        Write-Message -Level Debug -Message "AdditionalParameters will be appended by 'MultiSubnetFailover=True;'"
                        $sqlConnectionInfo.AdditionalParameters += 'MultiSubnetFailover=True;'
                    }

                    #ApplicationIntent      Property   string ApplicationIntent {get;set;}
                    if ($ApplicationIntent) {
                        Write-Message -Level Debug -Message "ApplicationIntent will be set to '$ApplicationIntent'"
                        $sqlConnectionInfo.ApplicationIntent = $ApplicationIntent
                    }

                    #ApplicationName        Property   string ApplicationName {get;set;}
                    if ($ClientName) {
                        Write-Message -Level Debug -Message "ApplicationName will be set to '$ClientName'"
                        $sqlConnectionInfo.ApplicationName = $ClientName
                    }

                    #Authentication         Property   Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod Authentication {get;set;}
                    #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryIntegrated
                    #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryInteractive
                    #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
                    #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::NotSpecified
                    #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::SqlPassword
                    if ($authType -eq 'azure integrated') {
                        # Azure AD integrated security
                        # TODO: This is not tested / How can we test that?
                        Write-Message -Level Debug -Message "Authentication will be set to 'ActiveDirectoryIntegrated'"
                        $sqlConnectionInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryIntegrated
                    } elseif ($authType -eq 'azure ad') {
                        # Azure AD account with password
                        Write-Message -Level Debug -Message "Authentication will be set to 'ActiveDirectoryPassword'"
                        $sqlConnectionInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
                    }

                    #ConnectionProtocol     Property   Microsoft.SqlServer.Management.Common.NetworkProtocol ConnectionProtocol {get;set;}
                    if ($NetworkProtocol) {
                        Write-Message -Level Debug -Message "ConnectionProtocol will be set to '$NetworkProtocol'"
                        $sqlConnectionInfo.ConnectionProtocol = $NetworkProtocol
                    }

                    #ConnectionString       Property   string ConnectionString {get;}
                    # Only a getter, not a setter - so don't touch

                    #ConnectionTimeout      Property   int ConnectionTimeout {get;set;}
                    if ($ConnectTimeout) {
                        Write-Message -Level Debug -Message "ConnectionTimeout will be set to '$ConnectTimeout'"
                        $sqlConnectionInfo.ConnectionTimeout = $ConnectTimeout
                    }

                    #DatabaseName           Property   string DatabaseName {get;set;}
                    if ($Database) {
                        Write-Message -Level Debug -Message "Database will be set to '$Database'"
                        $sqlConnectionInfo.DatabaseName = $Database
                    }

                    #EncryptConnection      Property   bool EncryptConnection {get;set;}
                    if ($EncryptConnection) {
                        Write-Message -Level Debug -Message "EncryptConnection will be set to '$EncryptConnection'"
                        $sqlConnectionInfo.EncryptConnection = $EncryptConnection
                    }

                    #MaxPoolSize            Property   int MaxPoolSize {get;set;}
                    if ($MaxPoolSize) {
                        Write-Message -Level Debug -Message "MaxPoolSize will be set to '$MaxPoolSize'"
                        $sqlConnectionInfo.MaxPoolSize = $MaxPoolSize
                    }

                    #MinPoolSize            Property   int MinPoolSize {get;set;}
                    if ($MinPoolSize) {
                        Write-Message -Level Debug -Message "MinPoolSize will be set to '$MinPoolSize'"
                        $sqlConnectionInfo.MinPoolSize = $MinPoolSize
                    }

                    #PacketSize             Property   int PacketSize {get;set;}
                    if ($PacketSize) {
                        Write-Message -Level Debug -Message "PacketSize will be set to '$PacketSize'"
                        $sqlConnectionInfo.PacketSize = $PacketSize
                    }

                    #Password               Property   string Password {get;set;}
                    # We will use SecurePassword

                    #PoolConnectionLifeTime Property   int PoolConnectionLifeTime {get;set;}
                    if ($PooledConnectionLifetime) {
                        Write-Message -Level Debug -Message "PoolConnectionLifeTime will be set to '$PooledConnectionLifetime'"
                        $sqlConnectionInfo.PoolConnectionLifeTime = $PooledConnectionLifetime
                    }

                    #Pooled                 Property   System.Data.SqlTypes.SqlBoolean Pooled {get;set;}
                    # TODO: Do we need or want the else path or is it the default and we better don't touch it?
                    if ($NonPooledConnection) {
                        Write-Message -Level Debug -Message "Pooled will be set to '$false'"
                        $sqlConnectionInfo.Pooled = $false
                    } else {
                        Write-Message -Level Debug -Message "Pooled will be set to '$true'"
                        $sqlConnectionInfo.Pooled = $true
                    }

                    #QueryTimeout           Property   int QueryTimeout {get;set;}
                    # We use ConnectionContext.StatementTimeout instead

                    #SecurePassword         Property   securestring SecurePassword {get;set;}
                    if ($authType -in 'azure ad', 'azure sql', 'local sql') {
                        Write-Message -Level Debug -Message "SecurePassword will be set"
                        $sqlConnectionInfo.SecurePassword = $SqlCredential.Password
                    }

                    #ServerCaseSensitivity  Property   Microsoft.SqlServer.Management.Common.ServerCaseSensitivity ServerCaseSensitivity {get;set;}

                    #ServerName             Property   string ServerName {get;set;}
                    # Was already set by the constructor.

                    #ServerType             Property   Microsoft.SqlServer.Management.Common.ConnectionType ServerType {get;}
                    # Only a getter, not a setter - so don't touch

                    #ServerVersion          Property   Microsoft.SqlServer.Management.Common.ServerVersion ServerVersion {get;set;}
                    # We can set that? No, we don't want to...

                    #TrustServerCertificate Property   bool TrustServerCertificate {get;set;}
                    if ($TrustServerCertificate) {
                        Write-Message -Level Debug -Message "TrustServerCertificate will be set to '$TrustServerCertificate'"
                        $sqlConnectionInfo.TrustServerCertificate = $TrustServerCertificate
                    }

                    #UseIntegratedSecurity  Property   bool UseIntegratedSecurity {get;set;}
                    # $true is the default and it is automatically set to $false if we set a UserName, so we don't touch

                    #UserName               Property   string UserName {get;set;}
                    if ($authType -in 'azure ad', 'azure sql', 'local sql') {
                        Write-Message -Level Debug -Message "UserName will be set to '$username'"
                        $sqlConnectionInfo.UserName = $username
                    }

                    #WorkstationId          Property   string WorkstationId {get;set;}
                    if ($WorkstationId) {
                        Write-Message -Level Debug -Message "WorkstationId will be set to '$WorkstationId'"
                        $sqlConnectionInfo.WorkstationId = $WorkstationId
                    }

                    # If we have an AccessToken, we will build a SqlConnection
                    if ($AccessToken) {
                        Write-Message -Level Debug -Message "We have an AccessToken and build a SqlConnection with that token"
                        Write-Message -Level Debug -Message "But we remove 'Integrated Security=True;'"
                        # TODO: How do we get a ConnectionString without this?
                        Write-Message -Level Debug -Message "Building SqlConnection from SqlConnectionInfo.ConnectionString"
                        $connectionString = $sqlConnectionInfo.ConnectionString -replace 'Integrated Security=True;', ''
                        $sqlConnection = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnection -ArgumentList $connectionString
                        Write-Message -Level Debug -Message "SqlConnection was built"
                        $sqlConnection.AccessToken = $AccessToken
                        Write-Message -Level Debug -Message "Building ServerConnection from SqlConnection"
                        $serverConnection = New-Object -TypeName Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $sqlConnection
                        Write-Message -Level Debug -Message "ServerConnection was built"
                    } else {
                        Write-Message -Level Debug -Message "Building ServerConnection from SqlConnectionInfo"
                        $serverConnection = New-Object -TypeName Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $sqlConnectionInfo
                        Write-Message -Level Debug -Message "ServerConnection was built"
                    }

                    if ($authType -eq 'local ad') {
                        if ($IsLinux -or $IsMacOS) {
                            Stop-Function -Target $instance -Message "Cannot use Windows credentials to connect when host is Linux or OS X. Use kinit instead. See https://github.com/sqlcollaborative/dbatools/issues/7602 for more info."
                            return
                        }
                        Write-Message -Level Debug -Message "ConnectAsUser will be set to '$true'"
                        $serverConnection.ConnectAsUser = $true

                        Write-Message -Level Debug -Message "ConnectAsUserName will be set to '$username'"
                        $serverConnection.ConnectAsUserName = $username

                        Write-Message -Level Debug -Message "ConnectAsUserPassword will be set"
                        $serverConnection.ConnectAsUserPassword = $SqlCredential.GetNetworkCredential().Password
                    }

                    Write-Message -Level Debug -Message "Building Server from ServerConnection"
                    $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $serverConnection
                    Write-Message -Level Debug -Message "Server was built"

                    # Set properties of ConnectionContext that are not part of SqlConnectionInfo
                    if (Test-Bound -ParameterName 'BatchSeparator') {
                        Write-Message -Level Debug -Message "Setting ConnectionContext.BatchSeparator to '$BatchSeparator'"
                        $server.ConnectionContext.BatchSeparator = $BatchSeparator
                    }
                    if (Test-Bound -ParameterName 'LockTimeout') {
                        Write-Message -Level Debug -Message "Setting ConnectionContext.LockTimeout to '$LockTimeout'"
                        $server.ConnectionContext.LockTimeout = $LockTimeout
                    }
                    if ($MultipleActiveResultSets) {
                        Write-Message -Level Debug -Message "Setting ConnectionContext.MultipleActiveResultSets to 'True'"
                        $server.ConnectionContext.MultipleActiveResultSets = $true
                    }
                    if (Test-Bound -ParameterName 'SqlExecutionModes') {
                        Write-Message -Level Debug -Message "Setting ConnectionContext.SqlExecutionModes to '$SqlExecutionModes'"
                        $server.ConnectionContext.SqlExecutionModes = $SqlExecutionModes
                    }
                    Write-Message -Level Debug -Message "Setting ConnectionContext.StatementTimeout to '$StatementTimeout'"
                    $server.ConnectionContext.StatementTimeout = $StatementTimeout
                }

                $maskedConnString = Hide-ConnectionString $server.ConnectionContext.ConnectionString
                Write-Message -Level Debug -Message "The masked server.ConnectionContext.ConnectionString is $maskedConnString"

                # It doesn't matter which input we have, we pass this line and have a server SMO in $server to work with
                # It might be a brand new one or an already used one.
                # "Pooled connections are always closed directly after an operation" (so .IsOpen does not tell us anything):
                # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.common.connectionmanager.isopen?view=sql-smo-160#Microsoft_SqlServer_Management_Common_ConnectionManager_IsOpen
                # We could use .ConnectionContext.SqlConnectionObject.Open(), but we would have to check ConnectionContext.IsOpen first because it is not allowed on open connections
                # But ConnectionContext.IsOpen does not tell the truth if the instance was just shut down
                # And we don't use $server.ConnectionContext.Connect() as this would create a non pooled connection
                # Instead we run a real T-SQL command and just SELECT something to be sure we have a valid connection and let the SMO handle the connection
                Write-Message -Level Debug -Message "We connect to the instance by running SELECT 'dbatools is opening a new connection'"
                try {
                    $null = $server.ConnectionContext.ExecuteWithResults("SELECT 'dbatools is opening a new connection'")
                } catch {
                    if ($DedicatedAdminConnection) {
                        Write-Message -Level Warning -Message "Failed to open dedicated admin connection (DAC) to $instance. Only one DAC connection is allowed, so maybe another DAC is still open."
                    }
                    Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Continue
                }
                Write-Message -Level Debug -Message "We have a connected server object"

                if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                    Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue
                }

                if ($MinimumVersion -and $server.VersionMajor) {
                    if ($server.VersionMajor -lt $MinimumVersion) {
                        Stop-Function -Target $instance -Message "SQL Server version $MinimumVersion required - $server not supported." -Continue
                    }
                }

                if ($SqlConnectionOnly) {
                    $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server.ConnectionContext.SqlConnectionObject
                    Write-Message -Level Debug -Message "We return only SqlConnection in server.ConnectionContext.SqlConnectionObject"
                    $server.ConnectionContext.SqlConnectionObject
                    continue
                }

                if (-not $server.ComputerName) {
                    # To set the source of ComputerName to something else than the default use this config parameter:
                    # Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'server.ComputerNamePhysicalNetBIOS'
                    # Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
                    # If the config parameter is not used, then there a different ways to handle the new property ComputerName
                    # Rules in legacy code: Use $server.NetName, but if $server.NetName is empty or we are on Azure or Linux, use $instance.ComputerName
                    $computerName = $null
                    $computerNameSource = Get-DbatoolsConfigValue -FullName commands.connect-dbainstance.smo.computername.source
                    if ($computerNameSource) {
                        Write-Message -Level Debug -Message "Setting ComputerName based on $computerNameSource"
                        $object, $property = $computerNameSource -split '\.'
                        $value = (Get-Variable -Name $object).Value.$property
                        if ($value) {
                            $computerName = $value
                            Write-Message -Level Debug -Message "ComputerName will be set to $computerName"
                        } else {
                            Write-Message -Level Debug -Message "No value found for ComputerName, so will use the default"
                        }
                    }
                    if (-not $computerName) {
                        if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                            Write-Message -Level Debug -Message "We are on Azure, so server.ComputerName will be set to instance.ComputerName"
                            $computerName = $instance.ComputerName
                        } elseif ($server.HostPlatform -eq 'Linux') {
                            Write-Message -Level Debug -Message "We are on Linux what is often on docker and the internal name is not useful, so server.ComputerName will be set to instance.ComputerName"
                            $computerName = $instance.ComputerName
                        } elseif ($server.NetName) {
                            Write-Message -Level Debug -Message "We will set server.ComputerName to server.NetName"
                            $computerName = $server.NetName
                        } else {
                            Write-Message -Level Debug -Message "We will set server.ComputerName to instance.ComputerName as server.NetName is empty"
                            $computerName = $instance.ComputerName
                        }
                        Write-Message -Level Debug -Message "ComputerName will be set to $computerName"
                    }
                    Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $computerName -Force
                }

                if (-not $server.IsAzure) {
                    Add-Member -InputObject $server -NotePropertyName IsAzure -NotePropertyValue (Test-Azure -SqlInstance $instance) -Force
                    Add-Member -InputObject $server -NotePropertyName DbaInstanceName -NotePropertyValue $instance.InstanceName -Force
                    Add-Member -InputObject $server -NotePropertyName NetPort -NotePropertyValue $instance.Port -Force
                    Add-Member -InputObject $server -NotePropertyName ConnectedAs -NotePropertyValue $server.ConnectionContext.TrueLogin -Force
                    Write-Message -Level Debug -Message "We added IsAzure = '$($server.IsAzure)', DbaInstanceName = instance.InstanceName = '$($server.DbaInstanceName)', SqlInstance = server.DomainInstanceName = '$($server.SqlInstance)', NetPort = instance.Port = '$($server.NetPort)', ConnectedAs = server.ConnectionContext.TrueLogin = '$($server.ConnectedAs)'"
                }

                Write-Message -Level Debug -Message "We return the server object"
                $server

                # Register the connected instance, so that the TEPP updater knows it's been connected to and starts building the cache
                [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($instance.FullSmoName.ToLowerInvariant(), $server.ConnectionContext.Copy(), ($server.ConnectionContext.FixedServerRoles -match "SysAdmin"))

                # Update cache for instance names
                if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance.FullSmoName.ToLowerInvariant()) {
                    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance.FullSmoName.ToLowerInvariant()
                }

                # Update lots of registered stuff
                # Default for [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled is $true, so will not run by default
                # Must be explicitly activated with [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled = $false to run
                if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled) {
                    # Variable $FullSmoName is used inside the script blocks, so we have to set
                    $FullSmoName = $instance.FullSmoName.ToLowerInvariant()
                    Write-Message -Level Debug -Message "Will run Invoke-TEPPCacheUpdate for FullSmoName = $FullSmoName"
                    foreach ($scriptBlock in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
                        Invoke-TEPPCacheUpdate -ScriptBlock $scriptBlock
                    }
                }

                # By default, SMO initializes several properties. We push it to the limit and gather a bit more
                # this slows down the connect a smidge but drastically improves overall performance
                # especially when dealing with a multitude of servers
                if ($loadedSmoVersion -ge 11 -and -not $isAzure) {
                    try {
                        Write-Message -Level Debug -Message "SetDefaultInitFields will be used"
                        $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                        $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                        if ($server.VersionMajor -eq 8) {
                            # 2000
                            [void]$initFieldsDb.AddRange($Fields2000_Db)
                            [void]$initFieldsLogin.AddRange($Fields2000_Login)
                        } elseif ($server.VersionMajor -eq 9 -or $server.VersionMajor -eq 10) {
                            # 2005 and 2008
                            [void]$initFieldsDb.AddRange($Fields200x_Db)
                            [void]$initFieldsLogin.AddRange($Fields200x_Login)
                        } else {
                            # 2012 and above
                            [void]$initFieldsDb.AddRange($Fields201x_Db)
                            [void]$initFieldsLogin.AddRange($Fields201x_Login)
                        }
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
                    } catch {
                        Write-Message -Level Debug -Message "SetDefaultInitFields failed with $_"
                        # perhaps a DLL issue, continue going
                    }
                }

                $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server
                Write-Message -Level Debug -Message "We are finished with this instance"
                continue
            }
            <#
            This is the end of the new default code path.
            All session with the configuration "sql.connection.legacy" set to $true will run through the following code.
            To use the legacy code path: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true
            #>

            Write-Message -Level Debug -Message "sql.connection.legacy is used"

            if ($AccessToken) {
                Stop-Function -Target $instance -Message 'AccessToken is only supported in the new default code path. Use the new default code path by executing: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $false -Passthru | Register-DbatoolsConfig'
                return
            }

            $connstring = ''
            $isConnectionString = $false
            if ($instance.IsConnectionString) {
                $connstring = $instance.InputObject
                $isConnectionString = $true
            }
            if ($instance.Type -eq 'RegisteredServer' -and $instance.InputObject.ConnectionString) {
                $connstring = $instance.InputObject.ConnectionString
                $isConnectionString = $true
            }

            if ($isConnectionString) {
                try {
                    # ensure it's in the proper format
                    if ($Database -or $NonPooledConnection) {
                        $connstring = ($connstring | New-DbaConnectionStringBuilder -Database $Database -NonPooledConnection:$NonPooledConnection).ToString()
                    }
                    $sb = New-Object System.Data.Common.DbConnectionStringBuilder
                    $sb.ConnectionString = $connstring
                } catch {
                    $isConnectionString = $false
                }
            }

            # Gracefully handle Azure connections
            if ($isAzure) {
                Write-Message -Level Debug -Message "We are about to connect to Azure"

                # Test for AzureUnsupported, moved here from Connect-SqlInstance
                if ($instance.InputObject.GetType().Name -eq 'Server') {
                    if ($AzureUnsupported -and $instance.InputObject.DatabaseEngineType -eq "SqlAzureDatabase") {
                        Stop-Function -Target $instance -Message "Azure SQL Database is not supported by this command."
                        continue
                    }
                }

                # so far, this is not evaluating
                if ($instance.InputObject.ConnectionContext.IsOpen) {
                    Write-Message -Level Debug -Message "Connection is already open, test if database has to be changed"
                    if ('' -eq $Database) {
                        Write-Message -Level Debug -Message "No database specified, so return instance.InputObject"
                        $instance.InputObject
                        continue
                    }
                    $currentdb = $instance.InputObject.ConnectionContext.ExecuteScalar("select db_name()")
                    if ($currentdb -eq $Database) {
                        Write-Message -Level Debug -Message "Same database specified, so return instance.InputObject"
                        $instance.InputObject
                        continue
                    } else {
                        Write-Message -Level Debug -Message "Different databases: Database = '$Database', currentdb = '$currentdb', so we build a new connection"
                    }
                }

                # Use available command to build the proper connection string
                # but first, clean up passed params so that they match
                $boundparams = $PSBoundParameters
                [object[]]$connstringcmd = (Get-Command New-DbaConnectionString).Parameters.Keys
                [object[]]$connectcmd = (Get-Command Connect-DbaInstance).Parameters.Keys

                foreach ($key in $connectcmd) {
                    if ($key -notin $connstringcmd -and $key -ne "SqlCredential") {
                        $null = $boundparams.Remove($key)
                    }
                }
                # Build connection string
                if ($connstring) {
                    Write-Message -Level Debug -Message "We have a connect string so we use it"
                    $azureconnstring = $connstring
                } else {
                    if ($Tenant) {
                        Write-Message -Level Debug -Message "We have a Tenant and build the connect string"
                        $azureconnstring = New-DbaConnectionString -SqlInstance $instance -AccessToken None -Database $Database
                    } else {
                        Write-Message -Level Debug -Message "We have to build a connect string, using these parameters: $($boundparams.Keys)"
                        $azureconnstring = New-DbaConnectionString @boundparams
                    }
                }

                if ($Tenant -or $AuthenticationType -eq "AD Universal with MFA Support") {
                    if ($Thumbprint) {
                        Stop-Function -Target $instance -Message "Thumbprint is unsupported at this time. Sorry, some DLLs were all messed up."
                        return
                    }

                    $appid = Get-DbatoolsConfigValue -FullName 'azure.appid'
                    $clientsecret = Get-DbatoolsConfigValue -FullName 'azure.clientsecret'

                    if (($appid -and $clientsecret) -and -not $SqlCredential) {
                        $SqlCredential = New-Object System.Management.Automation.PSCredential ($appid, $clientsecret)
                    }

                    if (-not $azurevm -and (-not $SqlCredential -and $Tenant)) {
                        Stop-Function -Target $instance -Message "When using Tenant, SqlCredential must be specified."
                        return
                    }

                    if (-not $Database) {
                        Stop-Function -Target $instance -Message "When using AD Universal with MFA Support, database must be specified."
                        return
                    }

                    if (-not $SqlCredential) {
                        Stop-Function -Target $instance -Message "When using Tenant, SqlCredential must be specified."
                        return
                    }
                    Write-Message -Level Verbose -Message "Creating renewable token"
                    $accesstoken = (New-DbaAzAccessToken -Type RenewableServicePrincipal -Subtype AzureSqlDb -Tenant $Tenant -Credential $SqlCredential)
                }

                try {
                    # this is the way, as recommended by Microsoft
                    # https://docs.microsoft.com/en-us/sql/relational-databases/security/encryption/configure-always-encrypted-using-powershell?view=sql-server-2017
                    $maskedConnString = Hide-ConnectionString $azureconnstring
                    Write-Message -Level Verbose -Message "Connecting to $maskedConnString"
                    try {
                        $sqlconn = New-Object Microsoft.Data.SqlClient.SqlConnection $azureconnstring
                    } catch {
                        Write-Message -Level Warning "Connection to $instance not supported yet. Please use MFA instead."
                        continue
                    }
                    # assign this twice, not sure why but hey it works better
                    if ($accesstoken) {
                        $sqlconn.AccessToken = $accesstoken
                    }
                    $serverconn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $sqlconn
                    Write-Message -Level Verbose -Message "Connecting to Azure: $instance"
                    # assign it twice, not sure why but hey it works better
                    if ($accesstoken) {
                        $serverconn.AccessToken = $accesstoken
                    }
                    $null = $serverconn.Connect()
                    Write-Message -Level Debug -Message "will build server with [Microsoft.SqlServer.Management.Common.ServerConnection]serverconn (serverconn.ServerInstance = '$($serverconn.ServerInstance)')"
                    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $serverconn
                    Write-Message -Level Debug -Message "server was built with server.Name = '$($server.Name)'"

                    # Test for AzureUnsupported
                    if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        Stop-Function -Target $instance -Message "Azure SQL Database is not supported by this command."
                        continue
                    }

                    # Make ComputerName easily available in the server object
                    Add-Member -InputObject $server -NotePropertyName IsAzure -NotePropertyValue $true -Force
                    Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $instance.ComputerName -Force
                    Add-Member -InputObject $server -NotePropertyName DbaInstanceName -NotePropertyValue $instance.InstanceName -Force
                    Add-Member -InputObject $server -NotePropertyName NetPort -NotePropertyValue $instance.Port -Force
                    Add-Member -InputObject $server -NotePropertyName ConnectedAs -NotePropertyValue $server.ConnectionContext.TrueLogin -Force
                    # Azure has a really hard time with $server.Databases, which we rely on heavily. Fix that.
                    <# Fixing that changed the db context back to master so we're SOL here until we can figure out another way.
                    # $currentdb = $server.Databases[$Database] | Where-Object Name -eq $server.ConnectionContext.CurrentDatabase | Select-Object -First 1
                    if ($currentdb) {
                        Add-Member -InputObject $server -NotePropertyName Databases -NotePropertyValue @{ $currentdb.Name = $currentdb } -Force
                    }#>
                    $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server
                    $server
                    continue
                } catch {
                    Stop-Function -Target $instance -Message "Failure" -ErrorRecord $_ -Continue
                }
            }

            #region Input Object was a server object
            if ($instance.Type -like "Server" -or ($isAzure -and $instance.InputObject.ConnectionContext.IsOpen)) {
                Write-Message -Level Debug -Message "instance.Type -like Server (or Azure) - so we have already the full smo"
                if ($instance.InputObject.ConnectionContext.IsOpen -eq $false) {
                    Write-Message -Level Debug -Message "We connect to the instance with instance.InputObject.ConnectionContext.Connect()"
                    $instance.InputObject.ConnectionContext.Connect()
                }
                if ($SqlConnectionOnly) {
                    $null = Add-ConnectionHashValue -Key $instance.InputObject.ConnectionContext.ConnectionString -Value $instance.InputObject.ConnectionContext.SqlConnectionObject
                    $instance.InputObject.ConnectionContext.SqlConnectionObject
                    continue
                } else {
                    Write-Message -Level Debug -Message "We return the instance object with: ComputerName = '$($instance.InputObject.ComputerName)', NetName = '$($instance.InputObject.NetName)', Name = '$($instance.InputObject.Name)'"
                    $instance.InputObject
                    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($instance.FullSmoName.ToLowerInvariant(), $instance.InputObject.ConnectionContext.Copy(), ($instance.InputObject.ConnectionContext.FixedServerRoles -match "SysAdmin"))

                    # Update cache for instance names
                    if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance.FullSmoName.ToLowerInvariant()) {
                        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance.FullSmoName.ToLowerInvariant()
                    }
                    continue
                }
            }
            #endregion Input Object was a server object

            #region Input Object was anything else
            Write-Message -Level Debug -Message "Input Object was anything else, so not full smo and we have to go on and build one"
            if ($instance.Type -like "SqlConnection") {
                Write-Message -Level Debug -Message "instance.Type -like SqlConnection"
                Write-Message -Level Debug -Message "will build server with [Microsoft.Data.SqlClient.SqlConnection]instance.InputObject (instance.InputObject.DataSource = '$($instance.InputObject.DataSource)')   "
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server($instance.InputObject)
                $server.ConnectionContext.ConnectionString = $instance.InputObject.ConnectionString
                Write-Message -Level Debug -Message "server was built with server.Name = '$($server.Name)'"

                if ($server.ConnectionContext.IsOpen -eq $false) {
                    Write-Message -Level Debug -Message "We connect to the server with server.ConnectionContext.Connect()"
                    $server.ConnectionContext.Connect()
                }
                if ($SqlConnectionOnly) {
                    Write-Message -Level Debug -Message "We have SqlConnectionOnly"
                    if ($MinimumVersion -and $server.VersionMajor) {
                        Write-Message -Level Debug -Message "We test MinimumVersion"
                        if ($server.versionMajor -lt $MinimumVersion) {
                            Stop-Function -Target $instance -Message "SQL Server version $MinimumVersion required - $server not supported." -Continue
                        }
                    }

                    if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue
                    }
                    $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server.ConnectionContext.SqlConnectionObject

                    Write-Message -Level Debug -Message "We return server.ConnectionContext.SqlConnectionObject"
                    $server.ConnectionContext.SqlConnectionObject
                    continue
                } else {
                    Write-Message -Level Debug -Message "We don't have SqlConnectionOnly"
                    if (-not $server.ComputerName) {
                        Write-Message -Level Debug -Message "We don't have ComputerName, so adding IsAzure = '$false', ComputerName = instance.ComputerName = '$($instance.ComputerName)', DbaInstanceName = instance.InstanceName = '$($instance.InstanceName)', NetPort = instance.Port = '$($instance.Port)', ConnectedAs = server.ConnectionContext.TrueLogin = '$($server.ConnectionContext.TrueLogin)'"
                        Add-Member -InputObject $server -NotePropertyName IsAzure -NotePropertyValue $false -Force
                        Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $instance.ComputerName -Force
                        Add-Member -InputObject $server -NotePropertyName DbaInstanceName -NotePropertyValue $instance.InstanceName -Force
                        Add-Member -InputObject $server -NotePropertyName NetPort -NotePropertyValue $instance.Port -Force
                        Add-Member -InputObject $server -NotePropertyName ConnectedAs -NotePropertyValue $server.ConnectionContext.TrueLogin -Force
                    }
                    if ($MinimumVersion -and $server.VersionMajor) {
                        Write-Message -Level Debug -Message "We test MinimumVersion"
                        if ($server.versionMajor -lt $MinimumVersion) {
                            Stop-Function -Target $instance -Message "SQL Server version $MinimumVersion required - $server not supported." -Continue
                        }
                    }

                    if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue
                    }

                    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($instance.FullSmoName.ToLowerInvariant(), $server.ConnectionContext.Copy(), ($server.ConnectionContext.FixedServerRoles -match "SysAdmin"))
                    # Update cache for instance names
                    if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance.FullSmoName.ToLowerInvariant()) {
                        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance.FullSmoName.ToLowerInvariant()
                    }
                    $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server
                    Write-Message -Level Debug -Message "We return server with server.Name = '$($server.Name)'"
                    $server
                    continue
                }
            }

            if ($isConnectionString) {
                Write-Message -Level Debug -Message "isConnectionString is true"
                # this is the way, as recommended by Microsoft
                # https://docs.microsoft.com/en-us/sql/relational-databases/security/encryption/configure-always-encrypted-using-powershell?view=sql-server-2017
                $sqlconn = New-Object Microsoft.Data.SqlClient.SqlConnection $connstring
                $serverconn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $sqlconn
                $null = $serverconn.Connect()
                Write-Message -Level Debug -Message "will build server with [Microsoft.SqlServer.Management.Common.ServerConnection]serverconn (serverconn.ServerInstance = '$($serverconn.ServerInstance)')"
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server $serverconn
                Write-Message -Level Debug -Message "server was built with server.Name = '$($server.Name)'"
            } elseif (-not $isAzure) {
                Write-Message -Level Debug -Message "isConnectionString is false"
                Write-Message -Level Debug -Message "will build server with instance.FullSmoName = '$($instance.FullSmoName)'"
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server($instance.FullSmoName)
                Write-Message -Level Debug -Message "server was built with server.Name = '$($server.Name)'"
            }

            if ($AppendConnectionString) {
                Write-Message -Level Debug -Message "AppendConnectionString was set"
                $connstring = $server.ConnectionContext.ConnectionString
                $server.ConnectionContext.ConnectionString = "$connstring;$appendconnectionstring"
                $server.ConnectionContext.Connect()
            } elseif (-not $isAzure -and -not $isConnectionString) {
                Write-Message -Level Debug -Message "AppendConnectionString was not set"
                # It's okay to skip Azure because this is addressed above with New-DbaConnectionString
                $server.ConnectionContext.ApplicationName = $ClientName

                if (Test-Bound -ParameterName 'BatchSeparator') {
                    $server.ConnectionContext.BatchSeparator = $BatchSeparator
                }
                if (Test-Bound -ParameterName 'ConnectTimeout') {
                    $server.ConnectionContext.ConnectTimeout = $ConnectTimeout
                }
                if (Test-Bound -ParameterName 'Database') {
                    $server.ConnectionContext.DatabaseName = $Database
                }
                if (Test-Bound -ParameterName 'EncryptConnection') {
                    $server.ConnectionContext.EncryptConnection = $true
                }
                if (Test-Bound -ParameterName 'LockTimeout') {
                    $server.ConnectionContext.LockTimeout = $LockTimeout
                }
                if (Test-Bound -ParameterName 'MaxPoolSize') {
                    $server.ConnectionContext.MaxPoolSize = $MaxPoolSize
                }
                if (Test-Bound -ParameterName 'MinPoolSize') {
                    $server.ConnectionContext.MinPoolSize = $MinPoolSize
                }
                if (Test-Bound -ParameterName 'MultipleActiveResultSets') {
                    $server.ConnectionContext.MultipleActiveResultSets = $true
                }
                if (Test-Bound -ParameterName 'NetworkProtocol') {
                    $server.ConnectionContext.NetworkProtocol = $NetworkProtocol
                }
                if (Test-Bound -ParameterName 'NonPooledConnection') {
                    $server.ConnectionContext.NonPooledConnection = $true
                }
                if (Test-Bound -ParameterName 'PacketSize') {
                    $server.ConnectionContext.PacketSize = $PacketSize
                }
                if (Test-Bound -ParameterName 'PooledConnectionLifetime') {
                    $server.ConnectionContext.PooledConnectionLifetime = $PooledConnectionLifetime
                }
                if (Test-Bound -ParameterName 'StatementTimeout') {
                    $server.ConnectionContext.StatementTimeout = $StatementTimeout
                }
                if (Test-Bound -ParameterName 'SqlExecutionModes') {
                    $server.ConnectionContext.SqlExecutionModes = $SqlExecutionModes
                }
                if (Test-Bound -ParameterName 'TrustServerCertificate') {
                    $server.ConnectionContext.TrustServerCertificate = $TrustServerCertificate
                }
                if (Test-Bound -ParameterName 'WorkstationId') {
                    $server.ConnectionContext.WorkstationId = $WorkstationId
                }
                if (Test-Bound -ParameterName 'ApplicationIntent') {
                    $server.ConnectionContext.ApplicationIntent = $ApplicationIntent
                }

                $connstring = $server.ConnectionContext.ConnectionString
                if (Test-Bound -ParameterName 'MultiSubnetFailover') {
                    $connstring = "$connstring;MultiSubnetFailover=True"
                }
                if (Test-Bound -ParameterName 'FailoverPartner') {
                    $connstring = "$connstring;Failover Partner=$FailoverPartner"
                }

                if ($connstring -ne $server.ConnectionContext.ConnectionString) {
                    $server.ConnectionContext.ConnectionString = $connstring
                }

                Write-Message -Level Debug -Message "We try to connect"
                try {
                    # parse out sql credential to figure out if it's Windows or SQL Login
                    if ($null -ne $SqlCredential.UserName -and -not $isAzure) {
                        $username = ($SqlCredential.UserName).TrimStart("\")

                        # support both ad\username and username@ad
                        if ($username -like "*\*" -or $username -like "*@*") {
                            if ($username -like "*\*") {
                                $domain, $login = $username.Split("\")
                                $authtype = "Windows Authentication with Credential"
                                if ($domain) {
                                    $formatteduser = "$login@$domain"
                                } else {
                                    $formatteduser = $username.Split("\")[1]
                                }
                            } else {
                                $formatteduser = $SqlCredential.UserName
                            }

                            $server.ConnectionContext.LoginSecure = $true
                            $server.ConnectionContext.ConnectAsUser = $true
                            $server.ConnectionContext.ConnectAsUserName = $formatteduser
                            $server.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
                        } else {
                            $authtype = "SQL Authentication"
                            $server.ConnectionContext.LoginSecure = $false
                            $server.ConnectionContext.set_Login($username)
                            $server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
                        }
                    }

                    if ($NonPooled) {
                        # When the Connect method is called, the connection is not automatically released.
                        # The Disconnect method must be called explicitly to release the connection to the connection pool.
                        # https://docs.microsoft.com/en-us/sql/relational-databases/server-management-objects-smo/create-program/disconnecting-from-an-instance-of-sql-server
                        Write-Message -Level Debug -Message "We try nonpooled connection with server.ConnectionContext.Connect()"
                        $server.ConnectionContext.Connect()
                    } elseif ($authtype -eq "Windows Authentication with Credential") {
                        Write-Message -Level Debug -Message "We have authtype -eq Windows Authentication with Credential"
                        # Make it connect in a natural way, hard to explain.
                        # See https://docs.microsoft.com/en-us/sql/relational-databases/server-management-objects-smo/create-program/connecting-to-an-instance-of-sql-server
                        $null = $server.Information.Version
                        if ($server.ConnectionContext.IsOpen -eq $false) {
                            # Sometimes, however, the above may not connect as promised. Force it.
                            # See https://github.com/sqlcollaborative/dbatools/pull/4426
                            Write-Message -Level Debug -Message "We try connection with server.ConnectionContext.Connect()"
                            $server.ConnectionContext.Connect()
                        }
                    } else {
                        if (-not $isAzure) {
                            # SqlConnectionObject.Open() enables connection pooling does not support
                            # alternative Windows Credentials and passes default credentials
                            # See https://github.com/sqlcollaborative/dbatools/pull/3809
                            Write-Message -Level Debug -Message "We try connection with server.ConnectionContext.SqlConnectionObject.Open()"
                            $server.ConnectionContext.SqlConnectionObject.Open()
                        }
                    }
                    Write-Message -Level Debug -Message "Connect was successful"
                } catch {
                    Write-Message -Level Debug -Message "Connect was not successful"
                    $originalException = $_.Exception
                    try {
                        $message = $originalException.InnerException.InnerException.ToString()
                    } catch {
                        $message = $originalException.ToString()
                    }
                    $message = ($message -Split '-->')[0]
                    $message = ($message -Split 'at Microsoft.Data.SqlClient')[0]
                    $message = ($message -Split 'at System.Data.ProviderBase')[0]

                    Stop-Function -Target $instance -Message "Can't connect to $instance" -ErrorRecord $_ -Continue
                }
            }

            # Register the connected instance, so that the TEPP updater knows it's been connected to and starts building the cache
            [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($instance.FullSmoName.ToLowerInvariant(), $server.ConnectionContext.Copy(), ($server.ConnectionContext.FixedServerRoles -match "SysAdmin"))

            # Update cache for instance names
            if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance.FullSmoName.ToLowerInvariant()) {
                [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance.FullSmoName.ToLowerInvariant()
            }

            # Update lots of registered stuff
            if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled) {
                foreach ($scriptBlock in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
                    Invoke-TEPPCacheUpdate -ScriptBlock $scriptBlock
                }
            }

            # By default, SMO initializes several properties. We push it to the limit and gather a bit more
            # this slows down the connect a smidge but drastically improves overall performance
            # especially when dealing with a multitude of servers
            if ($loadedSmoVersion -ge 11 -and -not $isAzure) {
                try {
                    if ($server.VersionMajor -eq 8) {
                        # 2000
                        $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                        [void]$initFieldsDb.AddRange($Fields2000_Db)
                        $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                        [void]$initFieldsLogin.AddRange($Fields2000_Login)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
                    } elseif ($server.VersionMajor -eq 9 -or $server.VersionMajor -eq 10) {
                        # 2005 and 2008
                        $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                        [void]$initFieldsDb.AddRange($Fields200x_Db)
                        $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                        [void]$initFieldsLogin.AddRange($Fields200x_Login)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
                    } else {
                        # 2012 and above
                        $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                        [void]$initFieldsDb.AddRange($Fields201x_Db)
                        $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                        [void]$initFieldsLogin.AddRange($Fields201x_Login)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
                    }
                } catch {
                    # perhaps a DLL issue, continue going
                }
            }

            if ($SqlConnectionOnly) {
                $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server.ConnectionContext.SqlConnectionObject
                Write-Message -Level Debug -Message "SqlConnectionOnly, so returning server.ConnectionContext.SqlConnectionObject"
                $server.ConnectionContext.SqlConnectionObject
                continue
            } else {
                Write-Message -Level Debug -Message "no SqlConnectionOnly, so we go on"
                if (-not $server.ComputerName) {
                    Write-Message -Level Debug -Message "we don't have server.ComputerName"
                    Write-Message -Level Debug -Message "but we would have instance.ComputerName = '$($instance.ComputerName)'"
                    # Not every environment supports .NetName
                    if ($server.DatabaseEngineType -ne "SqlAzureDatabase") {
                        try {
                            Write-Message -Level Debug -Message "we try to use server.NetName for computername"
                            $computername = $server.NetName
                        } catch {
                            Write-Message -Level Debug -Message "Ups, failed so we use instance.ComputerName"
                            $computername = $instance.ComputerName
                        }
                        Write-Message -Level Debug -Message "Ok, computername = server.NetName = '$computername'"
                    }
                    # SQL on Linux is often on docker and the internal name is not useful
                    if (-not $computername -or $server.HostPlatform -eq "Linux") {
                        Write-Message -Level Debug -Message "SQL on Linux is often on docker and the internal name is not useful - we use instance.ComputerName as computername"
                        $computername = $instance.ComputerName
                        Write-Message -Level Debug -Message "Ok, computername is now '$computername'"
                    }
                    Write-Message -Level Debug -Message "We add IsAzure = '$false', ComputerName = computername = '$computername', DbaInstanceName = instance.InstanceName = '$($instance.InstanceName)', NetPort = instance.Port = '$($instance.Port)', ConnectedAs = server.ConnectionContext.TrueLogin = '$($server.ConnectionContext.TrueLogin)'"
                    Add-Member -InputObject $server -NotePropertyName IsAzure -NotePropertyValue $false -Force
                    Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $computername -Force
                    Add-Member -InputObject $server -NotePropertyName DbaInstanceName -NotePropertyValue $instance.InstanceName -Force
                    Add-Member -InputObject $server -NotePropertyName NetPort -NotePropertyValue $instance.Port -Force
                    Add-Member -InputObject $server -NotePropertyName ConnectedAs -NotePropertyValue $server.ConnectionContext.TrueLogin -Force
                }
            }

            if ($MinimumVersion -and $server.VersionMajor) {
                if ($server.versionMajor -lt $MinimumVersion) {
                    Stop-Function -Target $instance -Message "SQL Server version $MinimumVersion required - $server not supported." -Continue
                }
            }

            if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue
            }

            $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server
            Write-Message -Level Debug -Message "We return server with server.Name = '$($server.Name)'"
            $server
            continue
        }
        #endregion Input Object was anything else
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUotNxqyCX2gWOAktVLSMmK977
# ZzOgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgVGltZXN0YW1waW5nIENBMB4XDTIxMDEwMTAwMDAwMFoXDTMxMDEw
# NjAwMDAwMFowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMTCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAMLmYYRnxYr1DQikRcpja1HXOhFCvQp1dU2UtAxQ
# tSYQ/h3Ib5FrDJbnGlxI70Tlv5thzRWRYlq4/2cLnGP9NmqB+in43Stwhd4CGPN4
# bbx9+cdtCT2+anaH6Yq9+IRdHnbJ5MZ2djpT0dHTWjaPxqPhLxs6t2HWc+xObTOK
# fF1FLUuxUOZBOjdWhtyTI433UCXoZObd048vV7WHIOsOjizVI9r0TXhG4wODMSlK
# XAwxikqMiMX3MFr5FK8VX2xDSQn9JiNT9o1j6BqrW7EdMMKbaYK02/xWVLwfoYer
# vnpbCiAvSwnJlaeNsvrWY4tOpXIc7p96AXP4Gdb+DUmEvQECAwEAAaOCAbgwggG0
# MA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsG
# AQUFBwMIMEEGA1UdIAQ6MDgwNgYJYIZIAYb9bAcBMCkwJwYIKwYBBQUHAgEWG2h0
# dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAfBgNVHSMEGDAWgBT0tuEgHf4prtLk
# YaWyoiWyyBc1bjAdBgNVHQ4EFgQUNkSGjqS6sGa+vCgtHUQ23eNqerwwcQYDVR0f
# BGowaDAyoDCgLoYsaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJl
# ZC10cy5jcmwwMqAwoC6GLGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFz
# c3VyZWQtdHMuY3JsMIGFBggrBgEFBQcBAQR5MHcwJAYIKwYBBQUHMAGGGGh0dHA6
# Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBPBggrBgEFBQcwAoZDaHR0cDovL2NhY2VydHMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJRFRpbWVzdGFtcGluZ0NB
# LmNydDANBgkqhkiG9w0BAQsFAAOCAQEASBzctemaI7znGucgDo5nRv1CclF0CiNH
# o6uS0iXEcFm+FKDlJ4GlTRQVGQd58NEEw4bZO73+RAJmTe1ppA/2uHDPYuj1UUp4
# eTZ6J7fz51Kfk6ftQ55757TdQSKJ+4eiRgNO/PT+t2R3Y18jUmmDgvoaU+2QzI2h
# F3MN9PNlOXBL85zWenvaDLw9MtAby/Vh/HUIAHa8gQ74wOFcz8QRcucbZEnYIpp1
# FUL1LTI4gdr0YKK6tFL7XOBhJCVPst/JKahzQ1HavWPWH1ub9y4bTxMd90oNcX6X
# t/Q/hOvB46NJofrOp79Wz7pZdmGJX36ntI5nePk2mOHLKNpbh6aKLzCCBRowggQC
# oAMCAQICEAMFu4YhsKFjX7/erhIE520wDQYJKoZIhvcNAQELBQAwcjELMAkGA1UE
# BhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2lj
# ZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUg
# U2lnbmluZyBDQTAeFw0yMDA1MTIwMDAwMDBaFw0yMzA2MDgxMjAwMDBaMFcxCzAJ
# BgNVBAYTAlVTMREwDwYDVQQIEwhWaXJnaW5pYTEPMA0GA1UEBxMGVmllbm5hMREw
# DwYDVQQKEwhkYmF0b29sczERMA8GA1UEAxMIZGJhdG9vbHMwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQC8v2N7q+O/vggBtpjmteofFo140k73JXQ5sOD6
# QLzjgija+scoYPxTmFSImnqtjfZFWmucAWsDiMVVro/6yGjsXmJJUA7oD5BlMdAK
# fuiq4558YBOjjc0Bp3NbY5ZGujdCmsw9lqHRAVil6P1ZpAv3D/TyVVq6AjDsJY+x
# rRL9iMc8YpD5tiAj+SsRSuT5qwPuW83ByRHqkaJ5YDJ/R82ZKh69AFNXoJ3xCJR+
# P7+pa8tbdSgRf25w4ZfYPy9InEvsnIRVZMeDjjuGvqr0/Mar73UI79z0NYW80yN/
# 7VzlrvV8RnniHWY2ib9ehZligp5aEqdV2/XFVPV4SKaJs8R9AgMBAAGjggHFMIIB
# wTAfBgNVHSMEGDAWgBRaxLl7KgqjpepxA8Bg+S32ZXUOWDAdBgNVHQ4EFgQU8MCg
# +7YDgENO+wnX3d96scvjniIwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsG
# AQUFBwMDMHcGA1UdHwRwMG4wNaAzoDGGL2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMDWgM6Axhi9odHRwOi8vY3JsNC5kaWdp
# Y2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcxLmNybDBMBgNVHSAERTBDMDcGCWCG
# SAGG/WwDATAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20v
# Q1BTMAgGBmeBDAEEATCBhAYIKwYBBQUHAQEEeDB2MCQGCCsGAQUFBzABhhhodHRw
# Oi8vb2NzcC5kaWdpY2VydC5jb20wTgYIKwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJBc3N1cmVkSURDb2RlU2lnbmluZ0NB
# LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IBAQCPzflwlQwf1jak
# EqymPOc0nBxiY7F4FwcmL7IrTLhub6Pjg4ZYfiC79Akz5aNlqO+TJ0kqglkfnOsc
# jfKQzzDwcZthLVZl83igzCLnWMo8Zk/D2d4ZLY9esFwqPNvuuVDrHvgh7H6DJ/zP
# Vm5EOK0sljT0UQ6HQEwtouH5S8nrqCGZ8jKM/+DeJlm+rCAGGf7TV85uqsAn5JqD
# En/bXE1AlyG1Q5YiXFGS5Sf0qS4Nisw7vRrZ6Qc4NwBty4cAYjzDPDixorWI8+FV
# OUWKMdL7tV8i393/XykwsccCstBCp7VnSZN+4vgzjEJQql5uQfysjcW9rrb/qixp
# csPTKYRHMIIFMDCCBBigAwIBAgIQBAkYG1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0B
# AQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIwMDAwWhcNMjgxMDIyMTIwMDAwWjByMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQg
# Q29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# +NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrbRPV/5aid2zLXcep2nQUut4/6kkPApfmJ
# 1DcZ17aq8JyGpdglrA55KDp+6dFn08b7KSfH03sjlOSRI5aQd4L5oYQjZhJUM1B0
# sSgmuyRpwsJS8hRniolF1C2ho+mILCCVrhxKhwjfDPXiTWAYvqrEsq5wMWYzcT6s
# cKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXpdOYr/mzLfnQ5Ng2Q7+S1TqSp6moKq4Tz
# rGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWOD8Gi6CxR93O8vYWxYoNzQYIH5DiLanMg
# 0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IBzTCCAckwEgYDVR0TAQH/BAgwBgEB/wIB
# ADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwMweQYIKwYBBQUH
# AQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYI
# KwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFz
# c3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmw0
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaG
# NGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcmwwTwYDVR0gBEgwRjA4BgpghkgBhv1sAAIEMCowKAYIKwYBBQUHAgEWHGh0
# dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCgYIYIZIAYb9bAMwHQYDVR0OBBYE
# FFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6en
# IZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IBAQA+7A1aJLPzItEVyCx8JSl2qB1dHC06
# GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew4fbRknUPUbRupY5a4l4kgU4QpO4/cY5j
# DhNLrddfRHnzNhQGivecRk5c/5CxGwcOkRX7uq+1UcKNJK4kxscnKqEpKBo6cSgC
# PC6Ro8AlEeKcFEehemhor5unXCBc2XGxDI+7qPjFEmifz0DLQESlE/DmZAwlCEIy
# sjaKJAL+L3J+HNdJRZboWR3p+nRka7LrZkPas7CM1ekN3fYBIM6ZMWM9CBoYs4Gb
# T8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiFLpKR6mhsRDKyZqHnGKSaZFHvMIIFMTCC
# BBmgAwIBAgIQCqEl1tYyG35B5AXaNpfCFTANBgkqhkiG9w0BAQsFADBlMQswCQYD
# VQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGln
# aWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0Ew
# HhcNMTYwMTA3MTIwMDAwWhcNMzEwMTA3MTIwMDAwWjByMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5n
# IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvdAy7kvNj3/dqbqC
# mcU5VChXtiNKxA4HRTNREH3Q+X1NaH7ntqD0jbOI5Je/YyGQmL8TvFfTw+F+CNZq
# FAA49y4eO+7MpvYyWf5fZT/gm+vjRkcGGlV+Cyd+wKL1oODeIj8O/36V+/OjuiI+
# GKwR5PCZA207hXwJ0+5dyJoLVOOoCXFr4M8iEA91z3FyTgqt30A6XLdR4aF5FMZN
# JCMwXbzsPGBqrC8HzP3w6kfZiFBe/WZuVmEnKYmEUeaC50ZQ/ZQqLKfkdT66mA+E
# f58xFNat1fJky3seBdCEGXIX8RcG7z3N1k3vBkL9olMqT4UdxB08r8/arBD13ays
# 6Vb/kwIDAQABo4IBzjCCAcowHQYDVR0OBBYEFPS24SAd/imu0uRhpbKiJbLIFzVu
# MB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHkGCCsG
# AQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# MEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRBc3N1cmVkSURSb290Q0EuY3J0MIGBBgNVHR8EejB4MDqgOKA2hjRodHRwOi8v
# Y3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMDqg
# OKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURS
# b290Q0EuY3JsMFAGA1UdIARJMEcwOAYKYIZIAYb9bAACBDAqMCgGCCsGAQUFBwIB
# FhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAsGCWCGSAGG/WwHATANBgkq
# hkiG9w0BAQsFAAOCAQEAcZUS6VGHVmnN793afKpjerN4zwY3QITvS4S/ys8DAv3F
# p8MOIEIsr3fzKx8MIVoqtwU0HWqumfgnoma/Capg33akOpMP+LLR2HwZYuhegiUe
# xLoceywh4tZbLBQ1QwRostt1AuByx5jWPGTlH0gQGF+JOGFNYkYkh2OMkVIsrymJ
# 5Xgf1gsUpYDXEkdws3XVk4WTfraSZ/tTYYmo9WuWwPRYaQ18yAGxuSh1t5ljhSKM
# Ycp5lH5Z/IwP42+1ASa2bKXuh1Eh5Fhgm7oMLSttosR+u8QlK0cCCHxJrhO24XxC
# QijGGFbPQTS2Zl22dHv1VjMiLyI2skuiSpXY9aaOUjGCBFwwggRYAgEBMIGGMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBDb2RlIFNpZ25pbmcgQ0ECEAMFu4YhsKFjX7/erhIE520wCQYFKw4DAhoFAKB4
# MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQB
# gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkE
# MRYEFL+AnIx1KZQ0dN+TSn2y01bELB9UMA0GCSqGSIb3DQEBAQUABIIBAJYswbxg
# 0DiEhxiGx6777N8LzhZrIpjT4ORCnJtgTMKzUfAvgjd08FJBet84F/3HrJqtanbz
# idF21TRaUybq/EDCg524dwpsjZns9Lv3oF4KjVSwGlWgMpUJXRrmZI89RzZk3Mj2
# Jr8RUl2n0KOw6zArLEZ9cKuAgwbjORKXvIFElfYftE7W/nhOg0MazIx8gWzuP0wp
# tucNzFuKSDTzWeVK8PV1F5ucbGvxjxzw5+z/zLZztxNLJeXLRon2doNXoFf/ZYsk
# hanJjFCyyNS4wcurmktJDlRGQCdu56Jg9QCA/0OhZU5QpU55BJKlNs7CzU6VD32M
# wCU6SBegG7mLHA6hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjQ1N1owLwYJKoZIhvcNAQkEMSIEIAhCgecvzd9AuN2g+2NcGm0A1MeI
# XnYJ+W0CJWzvfH8fMA0GCSqGSIb3DQEBAQUABIIBALFzb+rakL4i2QK7QZjnSGfU
# WL+x2QGoSFhQOVzIGRjcF6gp0KV2UlkV/KIEm+R+/LuicfVTRsuXNbEJX7blHJ4I
# tlOT8l90lG853QFZtOslj6frimXa0pMPFlRFlCyWBIECdVXnSC8WOmT097RroJ3z
# Y4+Zru+49nTf+rPxdfGO0mhB/OU2MHHeySrcXvskecpS4uO/wUHb8TDveBRyXM1z
# ctvuvNUGt2GcDCdwIS3bgkFQOdY2qDcOTltAw3FK1FSrSJqKAU90aZ+a6l2AJxQr
# hnzuSRW1VNnR/2X2MxE0j1BbVcU61JrdpDX05ZQ6KW2mWnSFG7WI1XOmSUCVzNI=
# SIG # End signature block
