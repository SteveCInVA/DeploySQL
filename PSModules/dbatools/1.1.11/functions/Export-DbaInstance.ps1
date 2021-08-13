function Export-DbaInstance {
    <#
    .SYNOPSIS
        Exports SQL Server *ALL* database restore scripts, logins, database mail profiles/accounts, credentials, SQL Agent objects, linked servers,
        Central Management Server objects, server configuration settings (sp_configure), user objects in systems databases,
        system triggers and backup devices from one SQL Server to another.

        For more granular control, please use one of the -Exclude parameters and use the other functions available within the dbatools module.

    .DESCRIPTION
        Export-DbaInstance consolidates most of the export scripts in dbatools into one command.

        This is useful when you're looking to Export entire instances. It less flexible than using the underlying functions.
        Think of it as an easy button. Unless an -Exclude is specified, it exports:

        All database 'restore from backup' scripts.  Note: if a database does not have a backup the 'restore from backup' script won't be generated.
        All logins.
        All database mail objects.
        All credentials.
        All objects within the Job Server (SQL Agent).
        All linked servers.
        All groups and servers within Central Management Server.
        All SQL Server configuration objects (everything in sp_configure).
        All user objects in system databases.
        All system triggers.
        All system backup devices.
        All Audits.
        All Endpoints.
        All Extended Events.
        All Policy Management objects.
        All Resource Governor objects.
        All Server Audit Specifications.
        All Custom Errors (User Defined Messages).
        All Server Roles.
        All Availability Groups.
        All OLEDB Providers.

        The exported files are written to a folder with a naming convention of "machinename$instance-yyyyMMddHHmmss".

        This command supports the following use cases related to the output files:

        1. Export files to a new timestamped folder. This is the default behavior and results in a simple historical archive within the local filesystem.
        2. Export files to an existing folder and overwrite pre-existing files. This can be accomplished using the -Force parameter.
        This results in a single folder location with the latest exported files. These files can then be checked into a source control system if needed.

    .PARAMETER SqlInstance
        The target SQL Server instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Alternative Windows credentials for exporting Linked Servers and Credentials. Accepts credential objects (Get-Credential)

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER WithReplace
        If this switch is used, databases are restored from backup using WITH REPLACE. This is useful if you want to stage some complex file paths.

    .PARAMETER NoRecovery
        If this switch is used, databases will be left in the No Recovery state to enable further backups to be added.

    .PARAMETER AzureCredential
        Optional AzureCredential to connect to blob storage holding the backups

    .PARAMETER IncludeDbMasterKey
        Exports the db master key then logs into the server to copy it to the $Path

    .PARAMETER Exclude
        Exclude one or more objects to export

        Databases
        Logins
        AgentServer
        Credentials
        LinkedServers
        SpConfigure
        CentralManagementServer
        DatabaseMail
        SysDbUserObjects
        SystemTriggers
        BackupDevices
        Audits
        Endpoints
        ExtendedEvents
        PolicyManagement
        ResourceGovernor
        ServerAuditSpecifications
        CustomErrors
        ServerRoles
        AvailabilityGroups
        ReplicationSettings
        OleDbProvider

    .PARAMETER BatchSeparator
        Batch separator for scripting output. "GO" by default based on (Get-DbatoolsConfigValue -FullName 'formatting.batchseparator').

    .PARAMETER NoPrefix
        If this switch is used, the scripts will not include prefix information containing creator and datetime.

    .PARAMETER ExcludePassword
        If this switch is used, the scripts will not include passwords for Credentials, LinkedServers or Logins.

    .PARAMETER ScriptingOption
        Add scripting options to scripting output for all objects except Registered Servers and Extended Events.

    .PARAMETER Force
        Overwrite files in the location specified by -Path. Note: The Server Name is used when creating the folder structure.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Export
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaInstance

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlserver\instance

        All databases, logins, job objects and sp_configure options will be exported from sqlserver\instance to an automatically generated folder name in Documents. For example, %userprofile%\Documents\DbatoolsExport\sqldev1$sqlcluster-20201108140000

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Exclude Databases, Logins -Path C:\dr\sqlcluster

        Exports everything but logins and database restore scripts to a folder such as C:\dr\sqlcluster\sqldev1$sqlcluster-20201108140000

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Path C:\servers\ -NoPrefix

        Exports everything to a folder such as C:\servers\sqldev1$sqlcluster-20201108140000 but scripts will not include prefix information.

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Path C:\servers\ -Force

        Exports everything to a folder such as C:\servers\sqldev1$sqlcluster and will overwrite/refresh existing files in that folder. Note: when the -Force param is used the generated folder name will not include a timestamp. This supports the use case of running Export-DbaInstance on a schedule and writing to the same dir each time.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [Alias("FilePath")]
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [switch]$NoRecovery,
        [string]$AzureCredential,
        [switch]$IncludeDbMasterKey,
        [ValidateSet('AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider')]
        [string[]]$Exclude,
        [string]$BatchSeparator = (Get-DbatoolsConfigValue -FullName 'formatting.batchseparator'),
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOption,
        [switch]$NoPrefix = $false,
        [switch]$ExcludePassword,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path

        if (-not $ScriptingOption) {
            $ScriptingOption = New-DbaScriptingOption
        }

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date

        $eol = [System.Environment]::NewLine
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            $stepCounter = 0
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Force) {
                # when the caller requests to overwrite existing scripts we won't add the dynamic timestamp to the folder name, so that a pre-existing location can be overwritten.
                $exportPath = Join-DbaPath -Path $Path -Child "$($server.name.replace('\', '$'))"
            } else {
                $timeNow = (Get-Date -UFormat (Get-DbatoolsConfigValue -FullName 'formatting.uformat'))
                $exportPath = Join-DbaPath -Path $Path -Child "$($server.name.replace('\', '$'))-$timeNow"
            }

            # Ensure the export dir exists.
            if (-not (Test-Path $exportPath)) {
                try {
                    $null = New-Item -ItemType Directory -Path $exportPath -Force -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                    return
                }
            }

            if ($Exclude -notcontains 'SpConfigure') {
                Write-Message -Level Verbose -Message "Exporting SQL Server Configuration"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL Server Configuration"
                Export-DbaSpConfigure -SqlInstance $server -FilePath "$exportPath\sp_configure.sql"
                # no call to Get-ChildItem because Export-DbaSpConfigure does it
            }

            if ($Exclude -notcontains 'CustomErrors') {
                Write-Message -Level Verbose -Message "Exporting custom errors (user defined messages)"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting custom errors (user defined messages)"
                $null = Get-DbaCustomError -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\customererrors.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\customererrors.sql"
            }

            if ($Exclude -notcontains 'ServerRoles') {
                Write-Message -Level Verbose -Message "Exporting server roles"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting server roles"
                $null = Get-DbaServerRole -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\serverroles.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\serverroles.sql"
            }

            if ($Exclude -notcontains 'Credentials') {
                Write-Message -Level Verbose -Message "Exporting SQL credentials"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL credentials"
                $null = Export-DbaCredential -SqlInstance $server -Credential $Credential -FilePath "$exportPath\credentials.sql" -ExcludePassword:$ExcludePassword
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\credentials.sql"
            }

            if ($Exclude -notcontains 'Logins') {
                Write-Message -Level Verbose -Message "Exporting logins"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting logins"
                Export-DbaLogin -SqlInstance $server -FilePath "$exportPath\logins.sql" -ExcludePassword:$ExcludePassword -NoPrefix:$NoPrefix -WarningAction SilentlyContinue
                # no call to Get-ChildItem because Export-DbaLogin does it
            }

            if ($Exclude -notcontains 'DatabaseMail') {
                Write-Message -Level Verbose -Message "Exporting database mail"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database mail"
                # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                $null = Get-DbaDbMailConfig -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailAccount -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailProfile -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailServer -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix

                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\dbmail.sql"
            }

            if ($Exclude -notcontains 'CentralManagementServer') {
                Write-Message -Level Verbose -Message "Exporting Central Management Server"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Central Management Server"
                $outputFilePath = "$exportPath\regserver.xml"
                $null = Export-DbaRegServer -SqlInstance $server -FilePath $outputFilePath -Overwrite:$Force
                Get-ChildItem -ErrorAction Ignore -Path $outputFilePath
            }

            if ($Exclude -notcontains 'BackupDevices') {
                Write-Message -Level Verbose -Message "Exporting Backup Devices"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Backup Devices"
                $null = Get-DbaBackupDevice -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\backupdevices.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\backupdevices.sql"
            }

            if ($Exclude -notcontains 'LinkedServers') {
                Write-Message -Level Verbose -Message "Exporting linked servers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting linked servers"
                Export-DbaLinkedServer -SqlInstance $server -FilePath "$exportPath\linkedservers.sql" -Credential $Credential -ExcludePassword:$ExcludePassword
                # no call to Get-ChildItem because Export-DbaLinkedServer does it
            }

            if ($Exclude -notcontains 'SystemTriggers') {
                Write-Message -Level Verbose -Message "Exporting System Triggers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting System Triggers"
                $null = Get-DbaInstanceTrigger -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\servertriggers.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $triggers = Get-Content -Path "$exportPath\servertriggers.sql" -Raw -ErrorAction Ignore
                if ($triggers) {
                    $triggers = $triggers.ToString() -replace 'CREATE TRIGGER', "$BatchSeparator$($eol)CREATE TRIGGER"
                    $triggers = $triggers.ToString() -replace 'ENABLE TRIGGER', "$BatchSeparator$($eol)ENABLE TRIGGER"
                    $null = $triggers | Set-Content -Path "$exportPath\servertriggers.sql" -Force
                    Get-ChildItem -ErrorAction Ignore -Path "$exportPath\servertriggers.sql"
                }
            }

            if ($Exclude -notcontains 'Databases') {
                Write-Message -Level Verbose -Message "Exporting database restores"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database restores"
                Get-DbaDbBackupHistory -SqlInstance $server -Last -WarningAction SilentlyContinue | Restore-DbaDatabase -SqlInstance $server -NoRecovery:$NoRecovery -WithReplace -OutputScriptOnly -WarningAction SilentlyContinue -AzureCredential $AzureCredential | Out-File -FilePath "$exportPath\databases.sql"
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\databases.sql"
            }

            if ($Exclude -notcontains 'Audits') {
                Write-Message -Level Verbose -Message "Exporting Audits"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Audits"
                $null = Get-DbaInstanceAudit -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\audits.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\audits.sql"
            }

            if ($Exclude -notcontains 'ServerAuditSpecifications') {
                Write-Message -Level Verbose -Message "Exporting Server Audit Specifications"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Server Audit Specifications"
                $null = Get-DbaInstanceAuditSpecification -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\auditspecs.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\auditspecs.sql"
            }

            if ($Exclude -notcontains 'Endpoints') {
                Write-Message -Level Verbose -Message "Exporting Endpoints"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Endpoints"
                $null = Get-DbaEndpoint -SqlInstance $server | Where-Object IsSystemObject -EQ $false | Export-DbaScript -FilePath "$exportPath\endpoints.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\endpoints.sql"
            }

            if ($Exclude -notcontains 'PolicyManagement' -and $PSVersionTable.PSEdition -eq "Core") {
                Write-Message -Level Verbose -Message "Skipping Policy Management -- not supported by PowerShell Core"
            }
            if ($Exclude -notcontains 'PolicyManagement' -and $PSVersionTable.PSEdition -ne "Core") {
                Write-Message -Level Verbose -Message "Exporting Policy Management"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Policy Management"

                $outputFilePath = "$exportPath\policymanagement.sql"
                $scriptText = ""
                $policyObjects = @()

                # the policy objects are a different set of classes and are not compatible with the SMO object usage in Export-DbaScript

                $policyObjects += Get-DbaPbmCondition -SqlInstance $server
                $policyObjects += Get-DbaPbmObjectSet -SqlInstance $server
                $policyObjects += Get-DbaPbmPolicy -SqlInstance $server

                foreach ($policyObject in $policyObjects) {
                    $tsqlScript = $policyObject.ScriptCreate()
                    $scriptText += $tsqlScript.GetScript() + "$eol$BatchSeparator$eol$eol"
                }

                Set-Content -Path $outputFilePath -Value $scriptText

                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\policymanagement.sql"
            }

            if ($Exclude -notcontains 'ResourceGovernor') {
                Write-Message -Level Verbose -Message "Exporting Resource Governor"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Resource Governor"
                # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                $null = Get-DbaRgClassifierFunction -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaRgResourcePool -SqlInstance $server | Where-Object Name -NotIn 'default', 'internal' | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaRgWorkloadGroup -SqlInstance $server | Where-Object Name -NotIn 'default', 'internal' | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaResourceGovernor -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\resourcegov.sql"
            }

            if ($Exclude -notcontains 'ExtendedEvents') {
                Write-Message -Level Verbose -Message "Exporting Extended Events"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Extended Events"
                $null = Get-DbaXESession -SqlInstance $server | Export-DbaXESession -FilePath "$exportPath\extendedevents.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\extendedevents.sql"
            }

            if ($Exclude -notcontains 'AgentServer') {
                Write-Message -Level Verbose -Message "Exporting job server"

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting job server"
                # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                $null = Get-DbaAgentJobCategory -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentOperator -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentAlert -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentProxy -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentSchedule -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentJob -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\sqlagent.sql"
            }

            if ($Exclude -notcontains 'ReplicationSettings') {
                Write-Message -Level Verbose -Message "Exporting replication settings"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting replication settings"
                $null = Export-DbaRepServerSetting -SqlInstance $instance -SqlCredential $SqlCredential -FilePath "$exportPath\replication.sql"
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\replication.sql"
            }

            if ($Exclude -notcontains 'SysDbUserObjects') {
                Write-Message -Level Verbose -Message "Exporting user objects in system databases (this can take a minute)."
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting user objects in system databases (this can take a minute)."
                $outputFile = "$exportPath\userobjectsinsysdbs.sql"
                $sysDbUserObjects = Export-DbaSysDbUserObject -SqlInstance $server -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption -PassThru
                Set-Content -Path $outputFile -Value $sysDbUserObjects # this approach is needed because -Append is used in Export-DbaSysDbUserObject.ps1
                Get-ChildItem -ErrorAction Ignore -Path $outputFile
            }

            if ($Exclude -notcontains 'AvailabilityGroups') {
                Write-Message -Level Verbose -Message "Exporting availability group"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting availability groups"
                $null = Get-DbaAvailabilityGroup -SqlInstance $server -WarningAction SilentlyContinue | Export-DbaScript -FilePath "$exportPath\AvailabilityGroups.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\AvailabilityGroups.sql"
            }

            if ($Exclude -notcontains 'OleDbProvider') {
                Write-Message -Level Verbose -Message "Exporting OLEDB Providers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting OLEDB Providers"
                $null = Get-DbaOleDbProvider -SqlInstance $server -WarningAction SilentlyContinue | Export-DbaScript -FilePath "$exportPath\OleDbProvider.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\oledbprovider.sql"
            }


            Write-Progress -Activity "Performing Instance Export for $instance" -Completed
        }
    }
    end {
        $totalTime = ($elapsed.Elapsed.toString().Split(".")[0])
        Write-Message -Level Verbose -Message "SQL Server export complete."
        Write-Message -Level Verbose -Message "Export started: $started"
        Write-Message -Level Verbose -Message "Export completed: $(Get-Date)"
        Write-Message -Level Verbose -Message "Total Elapsed time: $totalTime"
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUv91Qt/x2XvKrXOLfxxLAD8SJ
# tY+gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFPjsLv8SY0vU4qTcZHn4+MA+MtL2MA0GCSqGSIb3DQEBAQUABIIBAAGayZwS
# HCzoARo7cCEIpFr4xnqEsHJVkQWw1Fal47Oi8XOhMEkMGWetuaToEvkD38HE2Tgc
# WsaBQpBMxY0m2JX6/HK4nDfWndMIIHgDNFyjOZQOSuKAzoiKa9Yhb42PqFtigKZk
# 4W1G7M3s8FqVV1taIJW1zjRvWgGa1q4qEmzoP8YClSSQfqdCa9lxEmAC7n4lWs7e
# nNgWrh9+ORYhX4am+DKDvssDDrFbwv4Ssp10c5UJqbSRIsm8nvH0T/GZpxkE1xxb
# 4pk82JdSVWqKxSe0R2rhsFa3oLkw73w3H8cfFMACh9P0yVlHtGL592fgrdae6cIa
# 9c6Dw2s8eF29I+OhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUwM1owLwYJKoZIhvcNAQkEMSIEIDFyOg9vvGtZ+chKiAKTYEv1YPoG
# qCNHMc3NTWtbGuUPMA0GCSqGSIb3DQEBAQUABIIBAJgdyazGjsSleIh/EJsfDJrl
# n60N8uI5TatJ19zcxcDGyrGo6qwo4ntUElJ/xDyo9AHaLKV6zbdBFq7dO1AgzCKk
# +cvJS9U+qPAQCMp11ZXmNTdmOUp6764a2DfV6pmDLWODJajEL9KcI+l/Bvd1ew75
# QIJmJ1BMIdCEM1aGf9myPqQu1DxSx1l3B9Mk+EE82ea/KngJhkoYLHPEC9ZoJLyV
# acLt4OSnRUOvi9oHn2rjc0lPfFlrbsf18DtscTVGWx0o5gIA6KsNkvp5KnXhhmhV
# E+n+ALHYxm2jLbNUOzELacPR56c+3s3DHsGHVLR++fO4k83nV+WgFHjFQfGby8s=
# SIG # End signature block
