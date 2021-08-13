function New-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Automates the creation of availability groups.

    .DESCRIPTION
        Automates the creation of availability groups.

        * Checks prerequisites
        * Creates Availability Group and adds primary replica
        * Grants cluster permissions if necessary
        * Adds secondary replica if supplied
        * Adds databases if supplied
            * Performs backup/restore if seeding mode is manual
            * Performs backup to NUL if seeding mode is automatic
        * Adds listener to primary if supplied
        * Joins secondaries to availability group
        * Grants endpoint connect permissions to service accounts
        * Grants CreateAnyDatabase permissions if seeding mode is automatic
        * Returns Availability Group object from primary

        NOTES:
        - If a backup / restore is performed, the backups will be left intact on the network share.
        - If you're using SQL Server on Linux and a fully qualified domain name is required, please use the FQDN to create a proper Endpoint

        PLEASE NOTE THE CHANGED DEFAULTS:
        Starting with version 1.1.x we changed the defaults of the following parameters to have the same defaults
        as the T-SQL command "CREATE AVAILABILITY GROUP" and the wizard in SQL Server Management Studio:
        * ClusterType from External to Wsfc (Windows Server Failover Cluster).
        * FailureConditionLevel from OnServerDown (Level 1) to OnCriticalServerErrors (Level 3).
        * ConnectionModeInSecondaryRole from AllowAllConnections (ALL) to AllowNoConnections (NO).
        To change these defaults we have introduced configuration parameters for all of them, see documentation of the parameters for details.

        Thanks for this, Thomas Stringer! https://blogs.technet.microsoft.com/heyscriptingguy/2013/04/29/set-up-an-alwayson-availability-group-with-powershell/

    .PARAMETER Primary
        The primary SQL Server instance. Server version must be SQL Server version 2012 or higher.

    .PARAMETER PrimarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Secondary
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The name of the Availability Group.

    .PARAMETER DtcSupport
        Indicates whether the DtcSupport is enabled

    .PARAMETER ClusterType
        Cluster type of the Availability Group. Only supported in SQL Server 2017 and above.
        Options include: Wsfc, External or None.

        Defaults to Wsfc (Windows Server Failover Cluster).

        The default can be changed with:
        Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.ClusterType' -Value '...' -Passthru | Register-DbatoolsConfig

    .PARAMETER AutomatedBackupPreference
        Specifies how replicas in the primary role are treated in the evaluation to pick the desired replica to perform a backup.

    .PARAMETER FailureConditionLevel
        Specifies the different conditions that can trigger an automatic failover in Availability Group.

        Defaults to OnCriticalServerErrors (Level 3).

        From https://docs.microsoft.com/en-us/sql/t-sql/statements/create-availability-group-transact-sql:
            Level 1 = OnServerDown
            Level 2 = OnServerUnresponsive
            Level 3 = OnCriticalServerErrors (the default in CREATE AVAILABILITY GROUP and in this command)
            Level 4 = OnModerateServerErrors
            Level 5 = OnAnyQualifiedFailureCondition

        The default can be changed with:
        Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.FailureConditionLevel' -Value 'On...' -Passthru | Register-DbatoolsConfig

    .PARAMETER HealthCheckTimeout
        This setting used to specify the length of time, in milliseconds, that the SQL Server resource DLL should wait for information returned by the sp_server_diagnostics stored procedure before reporting the Always On Failover Cluster Instance (FCI) as unresponsive.

        Changes that are made to the timeout settings are effective immediately and do not require a restart of the SQL Server resource.

        Defaults to 30000 (30 seconds).

    .PARAMETER Basic
        Indicates whether the availability group is basic. Basic availability groups like pumpkin spice and uggs.

        https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/basic-availability-groups-always-on-availability-groups

    .PARAMETER DatabaseHealthTrigger
        Indicates whether the availability group triggers the database health.

    .PARAMETER Passthru
        Don't create the availability group, just pass thru an object that can be further customized before creation.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER SharedPath
        The network share where the backups will be backed up and restored from.

        Each SQL Server service account must have access to this share.

        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.

    .PARAMETER UseLastBackup
        Use the last full and log backup of database. A log backup must be the last backup.

    .PARAMETER Force
        Drop and recreate the database on remote servers using fresh backup.

    .PARAMETER AvailabilityMode
        Sets the availability mode of the availability group replica. Options are: AsynchronousCommit and SynchronousCommit. SynchronousCommit is default.

    .PARAMETER FailoverMode
        Sets the failover mode of the availability group replica. Options are Automatic, Manual and External. Automatic is default.

    .PARAMETER BackupPriority
        Sets the backup priority availability group replica. Default is 50.

    .PARAMETER Endpoint
        By default, this command will attempt to find a DatabaseMirror endpoint. If one does not exist, it will create it.

        If an endpoint must be created, the name "hadr_endpoint" will be used. If an alternative is preferred, use Endpoint.

    .PARAMETER EndpointUrl
        By default, the property Fqdn of Get-DbaEndpoint is used as EndpointUrl.

        Use EndpointUrl if different URLs are required due to special network configurations.
        EndpointUrl has to be an array of strings in format 'TCP://system-address:port', one entry for every instance.
        First entry for the primary instance, following entries for secondary instances in the order they show up in Secondary.
        See details regarding the format at: https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/specify-endpoint-url-adding-or-modifying-availability-replica

    .PARAMETER ConnectionModeInPrimaryRole
        Specifies the connection intent modes of an Availability Replica in primary role. AllowAllConnections by default.

    .PARAMETER ConnectionModeInSecondaryRole
        Specifies the connection modes of an Availability Replica in secondary role.
        Options include: AllowNoConnections (Alias: No), AllowReadIntentConnectionsOnly (Alias: Read-intent only),  AllowAllConnections (Alias: Yes)

        Defaults to AllowNoConnections.

        The default can be changed with:
        Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.ConnectionModeInSecondaryRole' -Value '...' -Passthru | Register-DbatoolsConfig

    .PARAMETER ReadonlyRoutingConnectionUrl
        Sets the read only routing connection url for the availability replica.

    .PARAMETER SeedingMode
        Specifies how the secondary replica will be initially seeded.

        Automatic enables direct seeding. This method will seed the secondary replica over the network. This method does not require you to backup and restore a copy of the primary database on the replica.

        Manual requires you to create a backup of the database on the primary replica and manually restore that backup on the secondary replica.

    .PARAMETER Certificate
        Specifies that the endpoint is to authenticate the connection using the certificate specified by certificate_name to establish identity for authorization.

        The far endpoint must have a certificate with the public key matching the private key of the specified certificate.

    .PARAMETER ConfigureXESession
        Configure the AlwaysOn_health extended events session to start automatically on every replica as the SSMS wizard would do.
        https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-extended-events#BKMK_alwayson_health

    .PARAMETER IPAddress
        Sets the IP address of the availability group listener.

    .PARAMETER SubnetMask
        Sets the subnet IP mask of the availability group listener.

    .PARAMETER Port
        Sets the number of the port used to communicate with the availability group.

    .PARAMETER Dhcp
        Indicates whether the object is DHCP.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016a -Name SharePoint

        Creates a new availability group on sql2016a named SharePoint

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016a -Name SharePoint -Secondary sql2016b

        Creates a new availability group on sql2016a named SharePoint with a secondary replica, sql2016b

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016std -Name BAG1 -Basic -Confirm:$false

        Creates a basic availability group named BAG1 on sql2016std and does not confirm when setting up

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016b -Name AG1 -Dhcp -Database db1 -UseLastBackup

        Creates an availability group on sql2016b with the name ag1. Uses the last backups available to add the database db1 to the AG.

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2017 -Name SharePoint -ClusterType None -FailoverMode Manual

        Creates a new availability group on sql2017 named SharePoint with a cluster type of none and a failover mode of manual

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql1 -Secondary sql2 -Name ag1 -Database pubs -ClusterType None -SeedingMode Automatic -FailoverMode Manual

        Creates a new availability group with a primary replica on sql1 and a secondary on sql2. Automatically adds the database pubs.

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql1 -Secondary sql2 -Name ag1 -Database pubs -EndpointUrl 'TCP://sql1.specialnet.local:5022', 'TCP://sql2.specialnet.local:5022'

        Creates a new availability group with a primary replica on sql1 and a secondary on sql2 with custom endpoint urls. Automatically adds the database pubs.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> $params = @{
        >> Primary = "sql1"
        >> PrimarySqlCredential = $cred
        >> Secondary = "sql2"
        >> SecondarySqlCredential = $cred
        >> Name = "test-ag"
        >> Database = "pubs"
        >> ClusterType = "None"
        >> SeedingMode = "Automatic"
        >> FailoverMode = "Manual"
        >> Confirm = $false
        >> }
        PS C:\> New-DbaAvailabilityGroup @params

        This exact command was used to create an availability group on docker!
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
        # AG

        [parameter(Mandatory)]
        [string]$Name,
        [switch]$DtcSupport,
        [ValidateSet('Wsfc', 'External', 'None')]
        [string]$ClusterType = (Get-DbatoolsConfigValue -FullName 'AvailabilityGroups.Default.ClusterType' -Fallback 'Wsfc'),
        [ValidateSet('None', 'Primary', 'Secondary', 'SecondaryOnly')]
        [string]$AutomatedBackupPreference = 'Secondary',
        [ValidateSet('OnAnyQualifiedFailureCondition', 'OnCriticalServerErrors', 'OnModerateServerErrors', 'OnServerDown', 'OnServerUnresponsive')]
        [string]$FailureConditionLevel = (Get-DbatoolsConfigValue -FullName 'AvailabilityGroups.Default.FailureConditionLevel' -Fallback 'OnCriticalServerErrors'),
        [int]$HealthCheckTimeout = 30000,
        [switch]$Basic,
        [switch]$DatabaseHealthTrigger,
        [switch]$Passthru,
        # database

        [string[]]$Database,
        [string]$SharedPath,
        [switch]$UseLastBackup,
        [switch]$Force,
        # replica

        [ValidateSet('AsynchronousCommit', 'SynchronousCommit')]
        [string]$AvailabilityMode = "SynchronousCommit",
        [ValidateSet('Automatic', 'Manual', 'External')]
        [string]$FailoverMode = "Automatic",
        [int]$BackupPriority = 50,
        [ValidateSet('AllowAllConnections', 'AllowReadWriteConnections')]
        [string]$ConnectionModeInPrimaryRole = 'AllowAllConnections',
        [ValidateSet('AllowNoConnections', 'AllowReadIntentConnectionsOnly', 'AllowAllConnections', 'No', 'Read-intent only', 'Yes')]
        [string]$ConnectionModeInSecondaryRole = (Get-DbatoolsConfigValue -FullName 'AvailabilityGroups.Default.ConnectionModeInSecondaryRole' -Fallback 'AllowNoConnections'),
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode = 'Manual',
        [string]$Endpoint,
        [string[]]$EndpointUrl,
        [string]$ReadonlyRoutingConnectionUrl,
        [string]$Certificate,
        [switch]$ConfigureXESession,
        # network

        [ipaddress[]]$IPAddress,
        [ipaddress]$SubnetMask = "255.255.255.0",
        [int]$Port = 1433,
        [switch]$Dhcp,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        $stepCounter = $wait = 0

        if ($Force -and $Secondary -and (-not $SharedPath -and -not $UseLastBackup) -and ($SeedingMode -ne 'Automatic')) {
            Stop-Function -Message "SharedPath or UseLastBackup is required when Force is used"
            return
        }

        if ($EndpointUrl) {
            if ($EndpointUrl.Count -ne (1 + $Secondary.Count)) {
                Stop-Function -Message "The number of elements in EndpointUrl is not correct"
                return
            }
            foreach ($epUrl in $EndpointUrl) {
                if ($epUrl -notmatch 'TCP://.+:\d+') {
                    Stop-Function -Message "EndpointUrl '$epUrl' not in correct format 'TCP://system-address:port'"
                    return
                }
            }
        }

        if ($ConnectionModeInSecondaryRole) {
            $ConnectionModeInSecondaryRole =
            switch ($ConnectionModeInSecondaryRole) {
                "No" { "AllowNoConnections" }
                "Read-intent only" { "AllowReadIntentConnectionsOnly" }
                "Yes" { "AllowAllConnections" }
                default { $ConnectionModeInSecondaryRole }
            }
        }

        if ($IPAddress -and $Dhcp) {
            Stop-Function -Message "You cannot specify both an IP address and the Dhcp switch for the listener."
            return
        }

        try {
            $server = Connect-SqlInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Primary" -Category ConnectionError -ErrorRecord $_ -Target $Primary
            return
        }

        if ($SeedingMode -eq 'Automatic' -and $server.VersionMajor -lt 13) {
            Stop-Function -Message "Automatic seeding mode only supported in SQL Server 2016 and above" -Target $Primary
            return
        }

        if ($Basic -and $server.VersionMajor -lt 13) {
            Stop-Function -Message "Basic availability groups are only supported in SQL Server 2016 and above" -Target $Primary
            return
        }

        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Checking requirements"
        $requirementsFailed = $false

        if (-not $server.IsHadrEnabled) {
            $requirementsFailed = $true
            Write-Message -Level Warning -Message "Availability Group (HADR) is not configured for the instance: $Primary. Use Enable-DbaAgHadr to configure the instance."
        }

        if ($Secondary) {
            $secondaries = @()
            if ($SeedingMode -eq "Automatic") {
                $primarypath = Get-DbaDefaultPath -SqlInstance $server
            }
            foreach ($instance in $Secondary) {
                try {
                    $second = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SecondarySqlCredential
                    $secondaries += $second
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance
                }

                if (-not $second.IsHadrEnabled) {
                    $requirementsFailed = $true
                    Write-Message -Level Warning -Message "Availability Group (HADR) is not configured for the instance: $instance. Use Enable-DbaAgHadr to configure the instance."
                }

                if ($SeedingMode -eq "Automatic") {
                    $secondarypath = Get-DbaDefaultPath -SqlInstance $second
                    if ($primarypath.Data -ne $secondarypath.Data) {
                        Write-Message -Level Warning -Message "Primary and secondary ($instance) default data paths do not match. Trying anyway."
                    }
                    if ($primarypath.Log -ne $secondarypath.Log) {
                        Write-Message -Level Warning -Message "Primary and secondary ($instance) default log paths do not match. Trying anyway."
                    }
                }
            }
        }

        if ($requirementsFailed) {
            Stop-Function -Message "Prerequisites are not completly met, so stopping here. See warning messages for details."
            return
        }

        # Don't reuse $server here, it fails
        if (Get-DbaAvailabilityGroup -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -AvailabilityGroup $Name) {
            Stop-Function -Message "Availability group named $Name already exists on $Primary"
            return
        }

        if ($Certificate) {
            $cert = Get-DbaDbCertificate -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Certificate $Certificate
            if (-not $cert) {
                Stop-Function -Message "Certificate $Certificate does not exist on $Primary" -ErrorRecord $_ -Target $Primary
                return
            }
        }

        if (($SharedPath)) {
            if (-not (Test-DbaPath -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Path $SharedPath)) {
                Stop-Function -Continue -Message "Cannot access $SharedPath from $Primary"
                return
            }
        }

        if ($Database -and -not $UseLastBackup -and -not $SharedPath -and $Secondary -and $SeedingMode -ne 'Automatic') {
            Stop-Function -Continue -Message "You must specify a SharedPath when adding databases to a manually seeded availability group"
            return
        }

        if ($server.HostPlatform -eq "Linux") {
            # New to SQL Server 2017 (14.x) is the introduction of a cluster type for AGs. For Linux, there are two valid values: External and None.
            if ($ClusterType -notin "External", "None") {
                Stop-Function -Continue -Message "Linux only supports ClusterType of External or None"
                return
            }
            # Microsoft Distributed Transaction Coordinator (DTC) is not supported under Linux in SQL Server 2017
            if ($DtcSupport) {
                Stop-Function -Continue -Message "Microsoft Distributed Transaction Coordinator (DTC) is not supported under Linux"
                return
            }
        }

        if ($ClusterType -eq "None" -and $server.VersionMajor -lt 14) {
            Stop-Function -Message "ClusterType of None only supported in SQL Server 2017 and above"
            return
        }

        # database checks
        if ($Database) {
            $dbs += Get-DbaDatabase -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Database $Database
        }

        foreach ($primarydb in $dbs) {
            if ($primarydb.MirroringStatus -ne "None") {
                Stop-Function -Message "Cannot setup mirroring on database ($($primarydb.Name)) due to its current mirroring state: $($primarydb.MirroringStatus)"
                return
            }

            if ($primarydb.Status -ne "Normal") {
                Stop-Function -Message "Cannot setup mirroring on database ($($primarydb.Name)) due to its current state: $($primarydb.Status)"
                return
            }

            if ($primarydb.RecoveryModel -ne "Full") {
                if ((Test-Bound -ParameterName UseLastBackup)) {
                    Stop-Function -Message "$($primarydb.Name) not set to full recovery. UseLastBackup cannot be used."
                    return
                } else {
                    Set-DbaDbRecoveryModel -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Database $primarydb.Name -RecoveryModel Full
                }
            }
        }

        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating availability group named $Name on $Primary"

        # Start work
        if ($Pscmdlet.ShouldProcess($Primary, "Setting up availability group named $Name and adding primary replica")) {
            try {
                $ag = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroup -ArgumentList $server, $Name
                $ag.AutomatedBackupPreference = [Microsoft.SqlServer.Management.Smo.AvailabilityGroupAutomatedBackupPreference]::$AutomatedBackupPreference
                $ag.FailureConditionLevel = [Microsoft.SqlServer.Management.Smo.AvailabilityGroupFailureConditionLevel]::$FailureConditionLevel
                $ag.HealthCheckTimeout = $HealthCheckTimeout

                if ($server.VersionMajor -ge 13) {
                    $ag.BasicAvailabilityGroup = $Basic
                    $ag.DatabaseHealthTrigger = $DatabaseHealthTrigger
                    $ag.DtcSupportEnabled = $DtcSupport
                }

                if ($server.VersionMajor -ge 14) {
                    $ag.ClusterType = $ClusterType
                }

                if ($PassThru) {
                    $defaults = 'LocalReplicaRole', 'Name as AvailabilityGroup', 'PrimaryReplicaServerName as PrimaryReplica', 'AutomatedBackupPreference', 'AvailabilityReplicas', 'AvailabilityDatabases', 'AvailabilityGroupListeners'
                    return (Select-DefaultView -InputObject $ag -Property $defaults)
                }

                $replicaparams = @{
                    InputObject                   = $ag
                    AvailabilityMode              = $AvailabilityMode
                    FailoverMode                  = $FailoverMode
                    BackupPriority                = $BackupPriority
                    ConnectionModeInPrimaryRole   = $ConnectionModeInPrimaryRole
                    ConnectionModeInSecondaryRole = $ConnectionModeInSecondaryRole
                    Endpoint                      = $Endpoint
                    ReadonlyRoutingConnectionUrl  = $ReadonlyRoutingConnectionUrl
                    Certificate                   = $Certificate
                    ConfigureXESession            = $ConfigureXESession
                }

                if ($EndpointUrl) {
                    $epUrl, $EndpointUrl = $EndpointUrl
                    $replicaparams += @{EndpointUrl = $epUrl }
                }

                if ($server.VersionMajor -ge 13) {
                    $replicaparams += @{SeedingMode = $SeedingMode }
                }

                $null = Add-DbaAgReplica @replicaparams -EnableException -SqlInstance $server
            } catch {
                $msg = $_.Exception.InnerException.InnerException.Message
                if (-not $msg) {
                    $msg = $_
                }
                Stop-Function -Message $msg -ErrorRecord $_ -Target $Primary
                return
            }
        }

        # Add cluster permissions
        if ($ClusterType -eq 'Wsfc') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding endpoint connect permissions"

            foreach ($second in $secondaries) {
                if ($Pscmdlet.ShouldProcess($Primary, "Adding cluster permissions for availability group named $Name")) {
                    Write-Message -Level Verbose -Message "WSFC Cluster requires granting [NT AUTHORITY\SYSTEM] a few things. Setting now."
                    $sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
                        GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
                        GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
                    try {
                        $null = $server.Query($sql)
                        foreach ($second in $secondaries) {
                            $null = $second.Query($sql)
                        }
                    } catch {
                        Stop-Function -Message "Failure adding cluster service account permissions" -ErrorRecord $_
                    }
                }
            }
        }

        # Add replicas
        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding secondary replicas"

        foreach ($second in $secondaries) {
            if ($Pscmdlet.ShouldProcess($second.Name, "Adding replica to availability group named $Name")) {
                try {
                    # Add replicas
                    if ($EndpointUrl) {
                        $epUrl, $EndpointUrl = $EndpointUrl
                        $replicaparams['EndpointUrl'] = $epUrl
                    }

                    $null = Add-DbaAgReplica @replicaparams -EnableException -SqlInstance $second
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $second -Continue
                }
            }
        }

        try {
            # something is up with .net create(), force a stop
            Invoke-Create -Object $ag
        } catch {
            $msg = $_.Exception.InnerException.InnerException.Message
            if (-not $msg) {
                $msg = $_
            }
            Stop-Function -Message $msg -ErrorRecord $_ -Target $Primary
            return
        }

        # Add listener
        if ($IPAddress -or $Dhcp) {
            $progressmsg = "Adding listener"
        } else {
            $progressmsg = "Joining availability group"
        }
        Write-ProgressHelper -StepNumber ($stepCounter++) -Message $progressmsg

        if ($IPAddress) {
            if ($Pscmdlet.ShouldProcess($Primary, "Adding static IP listener for $Name to the primary replica")) {
                $null = Add-DbaAgListener -InputObject $ag -IPAddress $IPAddress -SubnetMask $SubnetMask -Port $Port
            }
        } elseif ($Dhcp) {
            if ($Pscmdlet.ShouldProcess($Primary, "Adding DHCP listener for $Name to the primary replica")) {
                $null = Add-DbaAgListener -InputObject $ag -Port $Port -Dhcp
            }
        }

        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Joining availability group"

        foreach ($second in $secondaries) {
            if ($Pscmdlet.ShouldProcess("Joining $($second.Name) to $Name")) {
                try {
                    # join replicas to ag
                    Join-DbaAvailabilityGroup -SqlInstance $second -InputObject $ag -EnableException
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $second -Continue
                }
                $second.AvailabilityGroups.Refresh()
            }
        }

        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Granting permissions on availability group, this may take a moment"
        if ($SeedingMode -eq 'Automatic') {
            try {
                if ($Pscmdlet.ShouldProcess($server.Name, "Seeding mode is automatic. Adding CreateAnyDatabase permissions to availability group.")) {
                    $null = $server.Query("ALTER AVAILABILITY GROUP [$Name] GRANT CREATE ANY DATABASE")
                }
            } catch {
                # Log the exception but keep going
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }

        # Add databases
        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding databases"
        if ($Database) {
            if ($Pscmdlet.ShouldProcess($server.Name, "Adding databases to Availability Group.")) {
                if ($Force) {
                    try {
                        Get-DbaDatabase -SqlInstance $secondaries -Database $Database -EnableException | Remove-DbaDatabase -EnableException
                    } catch {
                        Stop-Function -Message "Failed to remove databases from secondary replicas." -ErrorRecord $_
                    }
                }

                $addDatabaseParams = @{
                    SqlInstance       = $server
                    AvailabilityGroup = $Name
                    Database          = $Database
                    Secondary         = $secondaries
                    UseLastBackup     = $UseLastBackup
                    EnableException   = $true
                }
                if ($SeedingMode) { $addDatabaseParams['SeedingMode'] = $SeedingMode }
                if ($SharedPath) { $addDatabaseParams['SharedPath'] = $SharedPath }
                try {
                    $null = Add-DbaAgDatabase @addDatabaseParams
                } catch {
                    Stop-Function -Message "Failed to add databases to Availability Group." -ErrorRecord $_
                }
            }
        }

        # Get results
        Get-DbaAvailabilityGroup -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -AvailabilityGroup $Name
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUB5WbA/w4bNoLAhdCzuWKuz7A
# p0+gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFIVEcybkwhffoLFn29Cmw79JqeKMMA0GCSqGSIb3DQEBAQUABIIBAJRbg3cI
# Tj6Q2Nk+KiE2kKpunfwKDALSqN3wljnYRWhBXw/yN8rY9GOQfMZ6UkmoUMt4Oojh
# EBGNhhCgWTLrd/SMlggyMmeemQRjhRy877X4+nnQiRidEDP0bBgPcRUUKiA9xbV1
# g/8MQCeUFASJinQeCLTETal2Boi75tZiFt7sbF4Fsx4qeQ+nKJ4Vf9KfEeKldD9A
# TUyhpTAbhOO6myTI7Zn5jdtPEpOAGmMlIwFEC8iqh1JEgmlS+OR1vDi3vpLRPRMt
# nL4pZ8aI2nk7u0cgpxWJjliBlLRWLAElVstzmybZSZ+Y+a6t6mPPDClTXokiWSe6
# Yru1kHX9gbK0CRyhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzOVowLwYJKoZIhvcNAQkEMSIEIA+D/u3Lf5l/V2Znt1aGXhFGdN45
# RrVFrWW0+1Vj8O/UMA0GCSqGSIb3DQEBAQUABIIBAL52Kd9I7gqyrYS0UD5rG4n1
# /O6fIucwcauyIHn8rZtaUga5qpF5gyyT+clJND/tPArL3FUTwX0fpmPTcT7nFYrd
# tz7dYsx9+aDoL/Mdcm/4swJJpOaOmREYAIDekAGEblm3nYucvtdRyaeMPMo8iLoM
# roJL0vpGqhifR9uQUoU9C+5TEJuJwk3EDsIxWWcf149YvIqT9b+nkT+Hi2F/9sPR
# eFdeEl1tmW7IMRXzW0I0byW0kIeUMgF5vhhvdPOPUIjscy1MKGaQ0XyPjkIkefus
# t089d+KsqlxalwChlEMrWLwDlVCRjNAx3UPxBr+cy2KzBC0NBt8r75XBmpRkBlc=
# SIG # End signature block
