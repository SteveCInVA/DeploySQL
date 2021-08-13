function Install-DbaInstance {
    <#
    .SYNOPSIS
        This function will help you to quickly install a SQL Server instance.

    .DESCRIPTION
        This function will help you to quickly install a SQL Server instance on one or many computers.
        Some of the things this function will do for you:
        * Add your login as an admin to the new instance
        * Search for SQL Server installations in the specified file repository
        * Generate SA password if needed
        * Install specific features using 'Default' and 'All' templates or cherry-pick the ones you need
        * Set number of tempdb files based on number of cores (SQL2016+)
        * Activate .Net 3.5 feature for SQL2012/2014
        * Restart the machine if needed after the installation is done

        Fully customizable installation parameters allow you to:
        * Use existing Configuration.ini files for the installation
        * Define service account credentials using native Powershell syntax
        * Override any configurations by using -Configuration switch
        * Change the TCP port after the installation is done
        * Enable 'Perform volume maintenance tasks' for the SQL Server account

        Note that the dowloaded installation media must be extracted and available to the server where the installation runs.
        NOTE: If no ProductID (PID) is found in the configuration files/parameters, Evaluation version is going to be installed.

        When using CredSSP authentication, this function will configure CredSSP authentication for PowerShell Remoting sessions.
        If this is not desired (e.g.: CredSSP authentication is managed externally, or is already configured appropriately,)
        it can be disabled by setting the dbatools configuration option 'commands.initialize-credssp.bypass' value to $true.

    .PARAMETER SqlInstance
        The target computer and, optionally, a new instance name and a port number.
        Use one of the following generic formats:
        Server1
        Server2\Instance1
        Server1\Alpha:1533, Server2\Omega:1566
        "ServerName\NewInstanceName,1534"

        You can also define instance name and port using -InstanceName and -Port parameters.

    .PARAMETER SaCredential
        Securely provide the password for the sa account when using mixed mode authentication.

    .PARAMETER Credential
        Used when executing installs against remote servers

    .PARAMETER ConfigurationFile
        The path to the custom Configuration.ini file.

    .PARAMETER Configuration
        A hashtable with custom configuration items that you want to use during the installation.
        Overrides all other parameters.
        For example, to define a custom server collation you can use the following parameter:
        PS> Install-DbaInstance -Version 2017 -Configuration @{ SQLCOLLATION = 'Latin1_General_BIN' }

        Full list of parameters can be found here: https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt#Install

    .PARAMETER Authentication
        Chooses an authentication protocol for remote connections.
        Allowed values: 'Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos'
        If the protocol fails to establish a connection

        Defaults:
        * CredSSP when -Credential is specified - due to the fact that repository Path is usually a network share and credentials need to be passed to the remote host
          to avoid the double-hop issue.
        * Default when -Credential is not specified. Will likely fail if a network path is specified.

    .PARAMETER Version
        SQL Server version you wish to install.
        This is the year version (e.g. "2008R2", "2017", "2019")

    .PARAMETER InstanceName
        Name of the SQL Server instance to install. Overrides the instance name specified in -SqlInstance.

    .PARAMETER Feature
        Features to install. Templates like "Default" and "All" can be used to setup a predefined set of components. Full list of features:

        Default
        All
        Engine
        Tools
        Replication
        FullText
        DataQuality
        PolyBase
        MachineLearning
        AnalysisServices
        ReportingServices
        ReportingForSharepoint
        SharepointAddin
        IntegrationServices
        MasterDataServices
        PythonPackages
        RPackages
        ReplayController
        ReplayClient
        SDK
        BIDS
        SSMS

    .PARAMETER InstancePath
        Root folder for instance components. Includes SQL Server logs, system databases, etc.

    .PARAMETER DataPath
        Path to the Data folder.

    .PARAMETER LogPath
        Path to the Log folder.

    .PARAMETER TempPath
        Path to the TempDB folder.

    .PARAMETER BackupPath
        Path to the Backup folder.

    .PARAMETER UpdateSourcePath
        Path to the updates that you want to slipstream into the installation.

    .PARAMETER AdminAccount
        One or more members of the sysadmin group. Uses UserName from the -Credential parameter if specified, or current Windows user by default.

    .PARAMETER Port
        After successful installation, changes SQL Server TCP port to this value. Overrides the port specified in -SqlInstance.

    .PARAMETER ProductID
        Product ID, or simply, serial number of your SQL Server installation, which will determine which version to install.
        If the PID is already built into the installation media, can be ignored.

    .PARAMETER EngineCredential
        Service account of the SQL Server Database Engine

    .PARAMETER AgentCredential
        Service account of the SQL Server Agent

    .PARAMETER ASCredential
        Service account of the Analysis Services

    .PARAMETER ISCredential
        Service account of the Integration Services

    .PARAMETER RSCredential
        Service account of the Reporting Services

    .PARAMETER FTCredential
        Service account of the Full-Text catalog service

    .PARAMETER PBEngineCredential
        Service account of the PolyBase service

    .PARAMETER Path
        Path to the folder(s) with SQL Server installation media downloaded. It will be scanned recursively for a corresponding setup.exe.
        Path should be available from the remote server.
        If a setup.exe file is missing in the repository, the installation will fail.
        Consider setting the following configuration in your session if you want to omit this parameter: `Set-DbatoolsConfig -Name Path.SQLServerSetup -Value '\\path\to\installations'`

    .PARAMETER PerformVolumeMaintenanceTasks
        Allow SQL Server service account to perform Volume Maintenance tasks.

    .PARAMETER SaveConfiguration
        Save installation configuration file in a custom location. Will not be preserved otherwise.

    .PARAMETER Throttle
        Maximum number of computers updated in parallel. Once reached, the update operations will queue up.
        Default: 50

    .PARAMETER Restart
        Restart computer automatically if a restart is required before or after the installation.

    .PARAMETER AuthenticationMode
        Chooses authentication mode for SQL Server. Allowed values: Mixed, Windows.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Install
        Author: Reitse Eskens (@2meterDBA), Kirill Kravtsov (@nvarscar)
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbaInstance

    .Example
        PS C:\> Install-DbaInstance -Version 2017 -Feature All

        Install a default SQL Server instance and run the installation enabling all features with default settings. Automatically generates configuration.ini

    .Example
        PS C:\> Install-DbaInstance -SqlInstance sql2017\sqlexpress, server01 -Version 2017 -Feature Default

        Install a named SQL Server instance named sqlexpress on sql2017, and a default instance on server01. Automatically generates configuration.ini.
        Default features will be installed.

    .Example
        PS C:\> Install-DbaInstance -Version 2008R2 -SqlInstance sql2017 -ConfigurationFile C:\temp\configuration.ini

        Install a default named SQL Server instance on the remote machine, sql2017 and use the local configuration.ini

    .Example
        PS C:\> Install-DbaInstance -Version 2017 -InstancePath G:\SQLServer -UpdateSourcePath '\\my\updates'

        Run the installation locally with default settings apart from the application volume, this will be redirected to G:\SQLServer.
        The installation procedure would search for SQL Server updates in \\my\updates and slipstream them into the installation.

    .Example
        PS C:\> $svcAcc = Get-Credential MyDomain\SvcSqlServer
        PS C:\> Install-DbaInstance -Version 2016 -InstancePath D:\Root -DataPath E: -LogPath L: -PerformVolumeMaintenanceTasks -EngineCredential $svcAcc

        Install SQL Server 2016 instance into D:\Root drive, set default data folder as E: and default logs folder as L:.
        Perform volume maintenance tasks permission is granted. MyDomain\SvcSqlServer is used as a service account for SqlServer.

    .Example
        PS C:\> $config = @{
        >> AGTSVCSTARTUPTYPE = "Manual"
        >> SQLCOLLATION = "Latin1_General_CI_AS"
        >> BROWSERSVCSTARTUPTYPE = "Manual"
        >> FILESTREAMLEVEL = 1
        >> }
        PS C:\> Install-DbaInstance -SqlInstance localhost\v2017:1337 -Version 2017 -Configuration $config

        Run the installation locally with default settings overriding the value of specific configuration items.
        Instance name will be defined as 'v2017'; TCP port will be changed to 1337 after installation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Alias('ComputerName')]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("2008", "2008R2", "2012", "2014", "2016", "2017", "2019")]
        [string]$Version,
        [string]$InstanceName,
        [PSCredential]$SaCredential,
        [PSCredential]$Credential,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Credssp',
        [parameter(ValueFromPipeline)]
        [Alias("FilePath")]
        [object]$ConfigurationFile,
        [hashtable]$Configuration,
        [string[]]$Path = (Get-DbatoolsConfigValue -Name 'Path.SQLServerSetup'),
        [ValidateSet("Default", "All", "Engine", "Tools", "Replication", "FullText", "DataQuality", "PolyBase", "MachineLearning", "AnalysisServices",
            "ReportingServices", "ReportingForSharepoint", "SharepointAddin", "IntegrationServices", "MasterDataServices", "PythonPackages", "RPackages",
            "ReplayController", "ReplayClient", "SDK", "BIDS", "SSMS")]
        [string[]]$Feature = "Default",
        [ValidateSet("Windows", "Mixed")]
        [string]$AuthenticationMode = "Windows",
        [string]$InstancePath,
        [string]$DataPath,
        [string]$LogPath,
        [string]$TempPath,
        [string]$BackupPath,
        [string]$UpdateSourcePath,
        [string[]]$AdminAccount,
        [int]$Port,
        [int]$Throttle = 50,
        [Alias('PID')]
        [string]$ProductID,
        [pscredential]$EngineCredential,
        [pscredential]$AgentCredential,
        [pscredential]$ASCredential,
        [pscredential]$ISCredential,
        [pscredential]$RSCredential,
        [pscredential]$FTCredential,
        [pscredential]$PBEngineCredential,
        [string]$SaveConfiguration,
        [switch]$PerformVolumeMaintenanceTasks,
        [switch]$Restart,
        [switch]$EnableException
    )
    begin {
        Function Read-IniFile {
            # Reads an ini file from a disk and returns a hashtable with a corresponding structure
            Param (
                $Path
            )
            #Collect config entries from the ini file
            Write-Message -Level Verbose -Message "Reading Ini file from $Path"
            $config = @{ }
            switch -regex -file $Path {
                #Comment
                '^#.*' { continue }
                #Section
                "^\[(.+)\]\s*$" {
                    $section = $matches[1]
                    if (-not $config.$section) {
                        $config.$section = @{ }
                    }
                    continue
                }
                #Item
                "^(.+)=(.+)$" {
                    $name, $value = $matches[1..2]
                    $config.$section.$name = $value.Trim('''"')
                    continue
                }
            }
            return $config
        }
        Function Write-IniFile {
            # Writes a hashtable into a file in a format of an ini file
            Param (
                [hashtable]$Content,
                $Path
            )
            Write-Message -Level Verbose -Message "Writing Ini file to $Path"
            $output = @()
            foreach ($key in $Content.Keys) {
                $output += "[$key]"
                if ($Content.$key -is [hashtable]) {
                    foreach ($sectionKey in $Content.$key.Keys) {
                        $origVal = $Content.$key.$sectionKey
                        if ($origVal -is [array]) {
                            $output += "$sectionKey=`"$($origVal -join ',')`""
                        } else {
                            if ($origVal -is [int]) {
                                $origVal = "$origVal"
                            }
                            if ($origVal -ne $origVal.Trim('"')) {
                                $output += "$sectionKey=$origVal"
                            } else {
                                $output += "$sectionKey=`"$origVal`""
                            }
                        }
                    }
                }
            }
            Set-Content -Path $Path -Value $output -Force
        }
        Function Update-ServiceCredential {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            # updates a service account entry and returns the password as a command line argument
            Param (
                $Node,
                [pscredential]$Credential,
                [string]$AccountName,
                [string]$PasswordName = $AccountName.Replace('SVCACCOUNT', 'SVCPASSWORD')
            )
            if ($Credential) {
                if ($AccountName) {
                    $Node.$AccountName = $Credential.UserName
                }
                if ($Credential.Password.Length -gt 0) {
                    return "/$PasswordName=`"" + $Credential.GetNetworkCredential().Password + '"'
                }
            }
        }
        # defining local vars
        $notifiedCredentials = $false
        $notifiedUnsecure = $false

        # read component names
        $components = Get-Content -Path $Script:PSModuleRoot\bin\dbatools-sqlinstallationcomponents.json -Raw | ConvertFrom-Json
    }
    process {
        if (!$Path) {
            Stop-Function -Message "Path to SQL Server setup folder is not set. Consider running Set-DbatoolsConfig -Name Path.SQLServerSetup -Value '\\path\to\updates' or specify the path in the original command"
            return
        }
        # getting a numeric version for further comparison
        #$canonicVersion = (Get-DbaBuild -MajorVersion $Version).BuildLevel
        [version]$canonicVersion = switch ($Version) {
            2008 { '10.0' }
            2008R2 { '10.50' }
            2012 { '11.0' }
            2014 { '12.0' }
            2016 { '13.0' }
            2017 { '14.0' }
            2019 { '15.0' }
            default {
                Stop-Function -Message "Version $Version is not supported"
                return
            }
        }

        # build feature list
        $featureList = @()
        foreach ($f in $Feature) {
            $featureDef = $components | Where-Object Name -contains $f
            foreach ($fd in $featureDef) {
                if (($fd.MinimumVersion -and $canonicVersion -lt [version]$fd.MinimumVersion) -or ($fd.MaximumVersion -and $canonicVersion -gt [version]$fd.MaximumVersion)) {
                    # exclude Default and All
                    if ($f -notin 'Default', 'All') {
                        Stop-Function -Message "Feature $f($($fd.Feature)) is not supported on SQL$Version"
                        return
                    }
                } else {
                    $featureList += $fd.Feature
                }
            }
        }

        # auto generate a random password if mixed is chosen and a credential is not provided
        if ($AuthenticationMode -eq "Mixed" -and -not $SaCredential) {
            $secpasswd = Get-RandomPassword -Length 15
            $SaCredential = New-Object System.Management.Automation.PSCredential ("sa", $secpasswd)
        }

        # turn the configuration file into an object so we can access it various ways
        if ($ConfigurationFile) {
            try {
                $ConfigurationFile = Get-Item -Path $ConfigurationFile -ErrorAction Stop
            } catch {
                Stop-Function -Message "Configuration file not found" -ErrorRecord $_
                return
            }
        }

        # check if installation path(s) is a network path and try to access it from the local machine
        Write-ProgressHelper -ExcludePercent -Activity "Looking for setup files" -StepNumber 0 -Message "Checking if installation is available locally"
        $isNetworkPath = $true
        foreach ($p in $Path) { if ($p -notlike '\\*') { $isNetworkPath = $false } }
        if ($isNetworkPath) {
            Write-Message -Level Verbose -Message "Looking for installation files in $($Path) on a local machine"
            try {
                $localSetupFile = Find-SqlInstanceSetup -Version $canonicVersion -Path $Path
            } catch {
                Write-Message -Level Verbose -Message "Failed to access $($Path) on a local machine, ignoring for now"
            }
        }

        $actionPlan = @()
        foreach ($computer in $SqlInstance) {
            $stepCounter = 1
            $totalSteps = 5
            $activity = "Preparing to install SQL Server $Version on $computer"
            # Test elevated console
            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            # notify about credentials once
            if (-not $computer.IsLocalHost -and -not $notifiedCredentials -and -not $Credential -and $isNetworkPath) {
                Write-Message -Level Warning -Message "Explicit -Credential might be required when running agains remote hosts and -Path is a network folder"
                $notifiedCredentials = $true
            }
            # resolve names
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Resolving computer name"
            $resolvedName = Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential
            if ($computer.IsLocalHost) {
                # Don't add a domain to localhost as this might add a domain that is later not recognized by .IsLocalHost anymore (#6976).
                $fullComputerName = $resolvedName.ComputerName
            } else {
                $fullComputerName = $resolvedName.FullComputerName
            }
            # test if the restart is needed
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Checking for pending restarts"
            try {
                $restartNeeded = Test-PendingReboot -ComputerName $fullComputerName -Credential $Credential
            } catch {
                Stop-Function -Message "Failed to get reboot status from $fullComputerName" -Continue -ErrorRecord $_
            }
            if ($restartNeeded -and (-not $Restart -or $computer.IsLocalHost)) {
                #Exit the actions loop altogether - nothing can be installed here anyways
                Stop-Function -Message "$computer is pending a reboot. Reboot the computer before proceeding." -Continue
            }
            # Attempt to configure CredSSP for the remote host when credentials are defined
            if ($Credential -and -not ([DbaInstanceParameter]$computer).IsLocalHost -and $Authentication -eq 'Credssp') {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Configuring CredSSP protocol"
                Write-Message -Level Verbose -Message "Attempting to configure CredSSP for remote connections"
                Initialize-CredSSP -ComputerName $fullComputerName -Credential $Credential -EnableException $false
                # Verify remote connection and confirm using unsecure credentials
                try {
                    $secureProtocol = Invoke-Command2 -ComputerName $fullComputerName -Credential $Credential -Authentication $Authentication -ScriptBlock { $true } -Raw
                } catch {
                    $secureProtocol = $false
                }
                # only ask once about using unsecure protocol
                if (-not $secureProtocol -and -not $notifiedUnsecure) {
                    if ($PSCmdlet.ShouldProcess($fullComputerName, "Primary protocol ($Authentication) failed, sending credentials via potentially unsecure protocol")) {
                        $notifiedUnsecure = $true
                    } else {
                        Stop-Function -Message "Failed to connect to $fullComputerName through $Authentication protocol. No actions will be performed on that computer." -Continue
                    }
                }
            }
            # find installation file
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Verifying access to setup files"
            $setupFileIsAccessible = $false
            if ($localSetupFile) {
                $testSetupPathParams = @{
                    ComputerName   = $fullComputerName
                    Credential     = $Credential
                    Authentication = $Authentication
                    ScriptBlock    = {
                        Param (
                            [string]$Path
                        )
                        try {
                            return Test-Path $Path
                        } catch {
                            return $false
                        }
                    }
                    ArgumentList   = @($localSetupFile)
                    ErrorAction    = 'Stop'
                    Raw            = $true
                }
                try {
                    $setupFileIsAccessible = Invoke-CommandWithFallback @testSetupPathParams
                } catch {
                    $setupFileIsAccessible = $false
                }
            }
            if ($setupFileIsAccessible) {
                Write-Message -Level Verbose -Message "Setup file $localSetupFile is reachable from remote machine $fullComputerName"
                $setupFile = $localSetupFile
            } else {
                Write-Message -Level Verbose -Message "Looking for installation files in $($Path) on remote machine $fullComputerName"
                $findSetupParams = @{
                    ComputerName   = $fullComputerName
                    Credential     = $Credential
                    Authentication = $Authentication
                    Version        = $canonicVersion
                    Path           = $Path
                }
                try {
                    $setupFile = Find-SqlInstanceSetup @findSetupParams
                } catch {
                    Stop-Function -Message "Failed to enumerate files in $Path" -ErrorRecord $_ -Continue
                }
            }
            if (-not $setupFile) {
                Stop-Function -Message "Failed to find setup file for SQL$Version in $Path on $fullComputerName" -Continue
            }
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Generating a configuration file"
            $instance = if ($InstanceName) { $InstanceName } else { $computer.InstanceName }
            # checking if we need to modify port after the installation
            $portNumber = if ($Port) { $Port } elseif ($computer.Port -in 0, 1433) { $null } else { $computer.Port }
            $mainKey = if ($canonicVersion -ge '11.0') { "OPTIONS" } else { "SQLSERVER2008" }
            if (Test-Bound -ParameterName ConfigurationFile) {
                try {
                    $config = Read-IniFile -Path $ConfigurationFile
                } catch {
                    Stop-Function -Message "Failed to read config file $ConfigurationFile" -ErrorRecord $_
                }
            } else {
                # determine a default user to assign sqladmin permissions
                if ($Credential) {
                    $defaultAdminAccount = $Credential.UserName
                } else {
                    if ($env:USERDOMAIN) {
                        $defaultAdminAccount = "$env:USERDOMAIN\$env:USERNAME"
                    } else {
                        if ($computer.IsLocalHost) {
                            $defaultAdminAccount = "$($resolvedName.ComputerName)\$env:USERNAME"
                        } else {
                            $defaultAdminAccount = $env:USERNAME
                        }
                    }
                }
                # determine browser startup
                if ($instance -eq 'MSSQLSERVER') { $browserStartup = 'Manual' }
                else { $browserStartup = 'Automatic' }
                # build generic config based on parameters
                $config = @{
                    $mainKey = @{
                        ACTION                = "Install"
                        AGTSVCSTARTUPTYPE     = "Automatic"
                        ASCOLLATION           = "Latin1_General_CI_AS"
                        BROWSERSVCSTARTUPTYPE = $browserStartup
                        ENABLERANU            = "False"
                        ERRORREPORTING        = "False"
                        FEATURES              = $featureList
                        FILESTREAMLEVEL       = "0"
                        HELP                  = "False"
                        INDICATEPROGRESS      = "False"
                        INSTANCEID            = $instance
                        INSTANCENAME          = $instance
                        ISSVCSTARTUPTYPE      = "Automatic"
                        QUIET                 = "True"
                        QUIETSIMPLE           = "False"
                        SQLCOLLATION          = "SQL_Latin1_General_CP1_CI_AS"
                        SQLSVCSTARTUPTYPE     = "Automatic"
                        SQLSYSADMINACCOUNTS   = $defaultAdminAccount
                        SQMREPORTING          = "False"
                        TCPENABLED            = "1"
                        UPDATEENABLED         = "False"
                        X86                   = "False"
                    }
                }
            }
            $configNode = $config.$mainKey
            if (-not $configNode) {
                Stop-Function -Message "Incorrect configuration file. Main node $mainKey not found."
                return
            }
            $execParams = @()
            # feature-specific parameters
            # Python
            foreach ($pythonFeature in 'SQL_INST_MPY', 'SQL_SHARED_MPY', 'AdvancedAnalytics') {
                if ($pythonFeature -in $featureList) {
                    $execParams += '/IACCEPTPYTHONLICENSETERMS'
                    break
                }
            }
            # R
            foreach ($rFeature in 'SQL_INST_MR', 'SQL_SHARED_MR', 'AdvancedAnalytics') {
                if ($rFeature -in $featureList) {
                    $execParams += '/IACCEPTROPENLICENSETERMS '
                    break
                }
            }
            # Reporting Services
            if ('RS' -in $featureList) {
                if (-Not $configNode.RSINSTALLMODE) { $configNode.RSINSTALLMODE = "DefaultNativeMode" }
                if (-Not $configNode.RSSVCSTARTUPTYPE) { $configNode.RSSVCSTARTUPTYPE = "Automatic" }
            }
            # version-specific stuff
            if ($canonicVersion -gt '10.0') {
                $execParams += '/IACCEPTSQLSERVERLICENSETERMS'
            }
            if ($canonicVersion -ge '13.0' -and ($configNode.ACTION -in 'Install', 'CompleteImage', 'Rebuilddatabase', 'InstallFailoverCluster', 'CompleteFailoverCluster') -and (-not $configNode.SQLTEMPDBFILECOUNT)) {
                # configure the number of cores
                $cpuInfo = Get-DbaCmObject -ComputerName $fullComputerName -Credential $Credential -ClassName Win32_processor -EnableException:$EnableException
                # trying to read NumberOfLogicalProcessors property. If it's not available, read NumberOfCores
                try {
                    [int]$cores = $cpuInfo | Measure-Object NumberOfLogicalProcessors -Sum -ErrorAction Stop | Select-Object -ExpandProperty sum
                } catch {
                    [int]$cores = $cpuInfo | Measure-Object NumberOfCores -Sum | Select-Object -ExpandProperty sum
                }
                if ($cores -gt 8) {
                    $cores = 8
                }
                if ($cores) {
                    $configNode.SQLTEMPDBFILECOUNT = $cores
                }
            }
            # Apply custom configuration keys if provided
            if ($Configuration) {
                foreach ($key in $Configuration.Keys) {
                    $configNode.$key = [string]$Configuration.$key
                    if ($key -eq 'UpdateSource' -and $configNode.$key -and $Configuration.Keys -notcontains 'UPDATEENABLED') {
                        #enable updates since now we have a source
                        $configNode.UPDATEENABLED = "True"
                    }
                }
            }

            # Now apply credentials
            $execParams += Update-ServiceCredential -Node $configNode -Credential $EngineCredential -AccountName SQLSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $AgentCredential -AccountName AGTSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $ASCredential -AccountName ASSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $ISCredential -AccountName ISSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $RSCredential -AccountName RSSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $FTCredential -AccountName FTSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $PBEngineCredential -AccountName PBENGSVCACCOUNT -PasswordName PBDMSSVCPASSWORD
            $execParams += Update-ServiceCredential -Credential $SaCredential -PasswordName SAPWD
            # And root folders and other variables
            if (Test-Bound -ParameterName InstancePath) {
                $configNode.INSTANCEDIR = $InstancePath
            }
            if (Test-Bound -ParameterName DataPath) {
                $configNode.SQLUSERDBDIR = $DataPath
            }
            if (Test-Bound -ParameterName LogPath) {
                $configNode.SQLUSERDBLOGDIR = $LogPath
            }
            if (Test-Bound -ParameterName TempPath) {
                $configNode.SQLTEMPDBDIR = $TempPath
            }
            if (Test-Bound -ParameterName BackupPath) {
                $configNode.SQLBACKUPDIR = $BackupPath
            }
            if (Test-Bound -ParameterName AdminAccount) {
                $configNode.SQLSYSADMINACCOUNTS = ($AdminAccount | ForEach-Object { '"{0}"' -f $_ }) -join ' '
            }
            if (Test-Bound -ParameterName UpdateSourcePath) {
                $configNode.UPDATESOURCE = $UpdateSourcePath
                $configNode.UPDATEENABLED = "True"
            }
            # PID
            if (Test-Bound -ParameterName ProductID) {
                $configNode.PID = $ProductID
            }
            # Authentication
            if ($AuthenticationMode -eq 'Mixed') {
                $configNode.SECURITYMODE = "SQL"
            }

            # save config file
            $tempdir = Get-DbatoolsConfigValue -FullName path.dbatoolstemp
            $configFile = "$tempdir\Configuration_$($fullComputerName)_$instance_$version.ini"
            try {
                Write-IniFile -Content $config -Path $configFile
            } catch {
                Stop-Function -Message "Failed to write config file to $configFile" -ErrorRecord $_
            }
            if ($PSCmdlet.ShouldProcess($fullComputerName, "Install $Version from $setupFile")) {
                $actionPlan += @{
                    ComputerName                  = $fullComputerName
                    InstanceName                  = $instance
                    Port                          = $portNumber
                    InstallationPath              = $setupFile
                    ConfigurationPath             = $configFile
                    ArgumentList                  = $execParams
                    Restart                       = $Restart
                    Version                       = $canonicVersion
                    Configuration                 = $config
                    SaveConfiguration             = $SaveConfiguration
                    SaCredential                  = $SaCredential
                    PerformVolumeMaintenanceTasks = $PerformVolumeMaintenanceTasks
                    Credential                    = $Credential
                    EnableException               = $EnableException
                }
            }
            Write-Progress -Activity $activity -Complete
        }
        # we need to know if authentication was explicitly defined
        $authBound = Test-Bound Authentication
        # wrapper for parallel advanced install
        $installAction = {
            $installSplat = $_
            if ($authBound) {
                $installSplat.Authentication = $Authentication
            }
            Invoke-DbaAdvancedInstall @installSplat
        }
        # check how many computers we are looking at and decide upon parallelism
        if ($actionPlan.Count -eq 1) {
            $actionPlan | ForEach-Object -Process $installAction
        } elseif ($actionPlan.Count -ge 2) {
            $invokeParallelSplat = @{
                ScriptBlock = $installAction
                Throttle    = $Throttle
                Activity    = "Installing SQL Server $Version on $($actionPlan.Count) computers"
                Status      = "Running the installation"
                ObjectName  = 'computers'
            }
            $actionPlan | Invoke-Parallel -ImportModules -ImportVariables @invokeParallelSplat
        }
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUCYEQ2XUCVxaw9JeOwg6WRI84
# dyKgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFIG8YRWirln9ixgOuHoZGRrP/jxVMA0GCSqGSIb3DQEBAQUABIIBAKlGXSPX
# bx+KCOlkcg32SSkIDkudchDvE6hMfdQ/vtacOf4XRv/8hvsZ1UOEUPPYJdbsHb10
# VvSzV7Ribg5M/HmxlsJKr9+NSITyPlim9Ga0ww5NsclCxySKf9ZvcHjx0Eh43S3f
# Qow/RMkNiBB/5sxUCcNrJGGq+4mAXRiJc9Hdj68KkAdLdHHWZJysQ+wbpzSI+aZN
# rCqXTJWuzB5YZq58K5B6+CN7d2gLl3ePeXIKftQL7u2w54rU6P3RhbqzBlhNuo+o
# sEe/NZEIaKGcNSyxq6UNNPvRwjDKv7wQKUmbLL2mp/tF7ng3yKBB0pEQT2GVgXj0
# dNB9TEtpZzDd48KhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzM1owLwYJKoZIhvcNAQkEMSIEIMjk57ryG6fOEdkqdVUytDv4FO/h
# PVpamQz/Zh1X0guWMA0GCSqGSIb3DQEBAQUABIIBAKKZQkyqClu1wDtDk5KPyFsc
# 2IfHq5FcgVuv1DJdqqSowXMy1LkDpZLg2EImdt07Ctx5wXcc4R7HKlxE1OJRwBcy
# WZP4A2SlqHSYCZlR+xLbqlxEPqqxb4ckjeGGkhAvdYyFW4kQqIxZGsldaFJwqH1f
# VPtBQ/5hC5FlZEYqfa3V/h6JFxLT+P2Uj99bdVzHfYfiQLe539dW3VfW5l4haQd7
# M+Teps+4x7Bf9X8nucRSQmIWf1RIbN4TUOlfZyOP4SQ086+uOo5qkxie1vBdl6rN
# zpPTf7SOYZATj08lOE8aZn0wb7O1qDCIwGs8JBWptJofawfQ4DNjdqDfhQWGGok=
# SIG # End signature block
