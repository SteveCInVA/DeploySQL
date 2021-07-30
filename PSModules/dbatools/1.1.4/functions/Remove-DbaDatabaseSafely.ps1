function Remove-DbaDatabaseSafely {
    <#
    .SYNOPSIS
        Safely removes a SQL Database and creates an Agent Job to restore it.

    .DESCRIPTION
        Performs a DBCC CHECKDB on the database, backs up the database with Checksum and verify only to a final (golden) backup location, creates an Agent Job to restore from that backup, drops the database, runs the agent job to restore the database, performs a DBCC CHECKDB and drops the database.

        With huge thanks to Grant Fritchey and his verify your backups video. Take a look, it's only 3 minutes long. http://sqlps.io/backuprant

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        If specified, Agent jobs will be created on this server. By default, the jobs will be created on the server specified by SqlInstance. You must have sysadmin access and the server must be SQL Server 2000 or higher. The SQL Agent service will be started if it is not already running.

    .PARAMETER DestinationCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more databases to remove.

    .PARAMETER NoDbccCheckDb
        If this switch is enabled, the initial DBCC CHECK DB will be skipped. This will make the process quicker but will also allow you to create an Agent job that restores a database backup containing a corrupt database.

        A second DBCC CHECKDB is performed on the restored database so you will still be notified BUT USE THIS WITH CARE.

    .PARAMETER BackupFolder
        Specifies the path to a folder where the final backups of the removed databases will be stored. If you are using separate source and destination servers, you must specify a UNC path such as  \\SERVER1\BACKUPSHARE\

    .PARAMETER JobOwner
        Specifies the name of the account which will own the Agent jobs. By default, sa is used.

    .PARAMETER UseDefaultFilePaths
        If this switch is enabled, the default file paths for the data and log files on the instance where the database is restored will be used. By default, the original file paths will be used.

    .PARAMETER CategoryName
        Specifies the Category Name for the Agent job that is created for restoring the database(s). By default, the name is "Rationalisation".

    .PARAMETER BackupCompression
        If this switch is enabled, compression will be used for the backup regardless of the SQL Server instance setting. By default, the SQL Server instance setting for backup compression is used.

    .PARAMETER AllDatabases
        If this switch is enabled, all user databases on the server will be removed. This is useful when decommissioning a server. You should use a Destination with this switch.

    .PARAMETER ReuseSourceFolderStructure
        If this switch is enabled, the source folder structure will be used when restoring instead of using the destination instance default folder structure.

    .PARAMETER Force
        If this switch is enabled, all actions will be performed even if DBCC errors are detected. An Agent job will be created with 'DBCCERROR' in the name and the backup file will have 'DBCC' in its name.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Remove
        Author: Rob Sewell (@SQLDBAWithBeard), sqldbawithabeard.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDatabaseSafely

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Database RideTheLightning -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

        Performs a DBCC CHECKDB on database RideTheLightning on server Fade2Black. If there are no errors, the database is backup to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. Then, an Agent job to restore the database from that backup is created. The database is then dropped, the Agent job to restore it run, a DBCC CHECKDB run against the restored database, and then it is dropped again.

        Any DBCC errors will be written to your documents folder

    .EXAMPLE
        PS C:\> $Database = 'DemoNCIndex','RemoveTestDatabase'
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Database $Database -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

        Performs a DBCC CHECKDB on two databases, 'DemoNCIndex' and 'RemoveTestDatabase' on server Fade2Black. Then, an Agent job to restore each database from those backups is created. The databases are then dropped, the Agent jobs to restore them run, a DBCC CHECKDB run against the restored databases, and then they are dropped again.

        Any DBCC errors will be written to your documents folder

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Destination JusticeForAll -Database RideTheLightning -BackupFolder '\\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE'

        Performs a DBCC CHECKDB on database RideTheLightning on server Fade2Black. If there are no errors, the database is backup to the folder \\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE . Then, an Agent job is created on server JusticeForAll to restore the database from that backup is created. The database is then dropped on Fade2Black, the Agent job to restore it on JusticeForAll is run, a DBCC CHECKDB run against the restored database, and then it is dropped from JusticeForAll.

        Any DBCC errors will be written to your documents folder

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance IronMaiden -Database $Database -Destination TheWildHearts -BackupFolder Z:\Backups -NoDbccCheckDb -JobOwner 'THEBEARD\Rob'

        For the databases $Database on the server IronMaiden a DBCC CHECKDB will not be performed before backing up the databases to the folder Z:\Backups. Then, an Agent job is created on server TheWildHearts with a Job Owner of THEBEARD\Rob to restore each database from that backup using the instance's default file paths. The database(s) is(are) then dropped on IronMaiden, the Agent job(s) run, a DBCC CHECKDB run on the restored database(s), and then the database(s) is(are) dropped.

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance IronMaiden -Database $Database -Destination TheWildHearts -BackupFolder Z:\Backups

        The databases $Database on the server IronMaiden will be backed up the to the folder Z:\Backups. Then, an Agent job is created on server TheWildHearts with a Job Owner of THEBEARD\Rob to restore each database from that backup using the instance's default file paths. The database(s) is(are) then dropped on IronMaiden, the Agent job(s) run, a DBCC CHECKDB run on the restored database(s), and then the database(s) is(are) dropped.

        If there is a DBCC Error, the function  will continue to perform rest of the actions and will create an Agent job with 'DBCCERROR' in the name and a Backup file with 'DBCCError' in the name.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default", ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [DbaInstanceParameter]$Destination = $SqlInstance,
        [PSCredential]$DestinationCredential,
        [Alias("NoCheck")]
        [switch]$NoDbccCheckDb,
        [parameter(Mandatory)]
        [string]$BackupFolder,
        [string]$CategoryName = 'Rationalisation',
        [string]$JobOwner,
        [switch]$AllDatabases,
        [ValidateSet("Default", "On", "Off")]
        [string]$BackupCompression = 'Default',
        [switch]$ReuseSourceFolderStructure,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if (!$AllDatabases -and !$Database) {
            Stop-Function -Message "You must specify at least one database. Use -Database or -AllDatabases." -ErrorRecord $_
            return
        }

        $sourceserver = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $sqlCredential

        if (-not $destination) {
            $destination = $SqlInstance
            $DestinationCredential = $SqlCredential
        }

        if ($SqlInstance -ne $destination) {

            $destserver = Connect-SqlInstance -SqlInstance $destination -SqlCredential $DestinationCredential

            $sourcenb = $instance.ComputerName
            $destnb = $instance.ComputerName

            if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcenb -ne $destnb) {
                Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -ErrorRecord $_ -Target $backupFolder
                return
            }
        } else {
            $destserver = $sourceserver
        }

        $source = $sourceserver.DomainInstanceName
        $destination = $destserver.DomainInstanceName

        if (!$jobowner) {
            $jobowner = Get-SqlSaLogin -SqlInstance $destserver
        }

        if ($alldatabases -or !$Database) {
            $database = ($sourceserver.databases | Where-Object { $_.IsSystemObject -eq $false -and ($_.Status -match 'Offline') -eq $false }).Name
        }

        if (!(Test-DbaPath -SqlInstance $destserver -Path $backupFolder)) {
            $serviceAccount = $destserver.ServiceAccount
            Stop-Function -Message "Can't access $backupFolder Please check if $serviceAccount has permissions." -ErrorRecord $_ -Target $backupFolder
        }

        #TODO: Test
        $jobname = "Rationalised Final Database Restore for $dbName"
        $jobStepName = "Restore the $dbName database from Final Backup"

        if (!($destserver.Logins | Where-Object { $_.Name -eq $jobowner })) {
            Stop-Function -Message "$destination does not contain the login $jobowner - Please fix and try again - Aborting." -ErrorRecord $_ -Target $jobowner
        }
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        $start = Get-Date

        try {
            $destInstanceName = $destserver.InstanceName

            if ($destserver.EngineEdition -match "Express") {
                Write-Message -Level Warning -Message "$destInstanceName is Express Edition which does not support SQL Server Agent."
                return
            }

            if ($destInstanceName -eq '') {
                $destInstanceName = "MSSQLSERVER"
            }
            $agentService = Get-DbaService -ComputerName $destserver.ComputerName -InstanceName $destInstanceName -Type Agent

            if ($agentService.State -ne 'Running') {
                Stop-Function -Message "SQL Server Agent is not running. Please start the service." -ErrorAction $agentService.Name
            } else {
                Write-Message -Level Verbose -Message "SQL Server Agent $($agentService.Name) is running."
            }
        } catch {
            Stop-Function -Message "Failure getting SQL Agent service" -ErrorRecord $_
            return
        }

        Write-Message -Level Verbose -Message "Starting Rationalisation Script at $start."

        foreach ($dbName in $Database) {

            $db = $sourceserver.databases[$dbName]

            # The db check is needed when the number of databases exceeds 255, then it's no longer auto-populated
            if (!$db) {
                Stop-Function -Message "$dbName does not exist on $source. Aborting routine for this database." -Continue
            }

            $lastFullBckDuration = ( Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -LastFull).Duration

            if (-NOT ([string]::IsNullOrEmpty($lastFullBckDuration))) {
                $lastFullBckDurationSec = $lastFullBckDuration.TotalSeconds
                $lastFullBckDurationMin = [Math]::Round($lastFullBckDuration.TotalMinutes, 2)

                Write-Message -Level Verbose -Message "From the backup history the last full backup took $lastFullBckDurationSec seconds ($lastFullBckDurationMin minutes)"
                if ($lastFullBckDurationSec -gt 600) {
                    Write-Message -Level Verbose -Message "Last full backup took more than 10 minutes. Do you want to continue?"

                    # Set up the parts for the user choice
                    $Title = "Backup duration"
                    $Info = "Last full backup took more than $lastFullBckDurationMin minutes. Do you want to continue?"

                    $Options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No (Skip)")
                    [int]$Defaultchoice = 0
                    $choice = $host.UI.PromptForChoice($Title, $Info, $Options, $Defaultchoice)
                    # Check the given option
                    if ($choice -eq 1) {
                        Stop-Function -Message "You have chosen skipping the database $dbName because of last known backup time ($lastFullBckDurationMin minutes)." -ErrorRecord $_ -Target $dbName -Continue
                        Continue
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Couldn't find last full backup time for database $dbName using Get-DbaDbBackupHistory."
            }

            $jobname = "Rationalised Database Restore Script for $dbName"
            $jobStepName = "Restore the $dbName database from Final Backup"
            $checkJob = Get-DbaAgentJob -SqlInstance $destserver -Job $jobname

            if ($checkJob.count -gt 0) {
                if ($Force -eq $false) {
                    Stop-Function -Message "FAILED: The Job $jobname already exists. Have you done this before? Rename the existing job and try again or use -Force to drop and recreate." -Continue
                } else {
                    if ($Pscmdlet.ShouldProcess($dbName, "Dropping $jobname on $destination")) {
                        Write-Message -Level Verbose -Message "Dropping $jobname on $destination."
                        $checkJob.Drop()
                    }
                }
            }


            Write-Message -Level Verbose -Message "Starting Rationalisation of $dbName."
            ## if we want to Dbcc before to abort if we have a corrupt database to start with
            if ($NoDbccCheckDb -eq $false) {
                if ($Pscmdlet.ShouldProcess($dbName, "Running dbcc check on $dbName on $source")) {
                    Write-Message -Level Verbose -Message "Starting DBCC CHECKDB for $dbName on $source."
                    $dbccgood = Start-DbccCheck -server $sourceserver -dbname $dbName -table

                    if ($dbccgood -ne "Success") {
                        if ($Force -eq $false) {
                            Write-Message -Level Verbose -Message "DBCC failed for $dbName (you should check that). Aborting routine for this database."
                            continue
                        } else {
                            Write-Message -Level Verbose -Message "DBCC failed, but Force specified. Continuing."
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($source, "Backing up $dbName")) {

                Write-Message -Level Verbose -Message "Starting Backup for $dbName on $source."
                ## Take a Backup
                try {
                    $timenow = [DateTime]::Now.ToString('yyyyMMdd_HHmmss')

                    if ($Force -and $dbccgood -ne "Success") {
                        $filename = "$backupFolder\$($dbName)_DBCCERROR_$timenow.bak"
                    } else {
                        $filename = "$backupFolder\$($dbName)_Final_Before_Drop_$timenow.bak"
                    }

                    $DefaultCompression = $sourceserver.Configuration.DefaultBackupCompression.ConfigValue
                    $backupWithCompressionParams = @{
                        SqlInstance    = $SqlInstance
                        SqlCredential  = $SqlCredential
                        Database       = $dbName
                        BackupFileName = $filename
                        CompressBackup = $true
                        Checksum       = $true
                    }

                    $backupWithoutCompressionParams = @{
                        SqlInstance    = $SqlInstance
                        SqlCredential  = $SqlCredential
                        Database       = $dbName
                        BackupFileName = $filename
                        Checksum       = $true
                    }
                    if ($BackupCompression -eq "Default") {
                        if ($DefaultCompression -eq 1) {
                            $null = Backup-DbaDatabase @backupWithCompressionParams
                        } else {
                            $null = Backup-DbaDatabase @backupWithoutCompressionParams
                        }
                    } elseif ($BackupCompression -eq "On") {
                        $null = Backup-DbaDatabase @backupWithCompressionParams
                    } else {
                        $null = Backup-DbaDatabase @backupWithoutCompressionParams
                    }

                } catch {
                    Stop-Function -Message "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database. Exception: $_" -Target $filename -ErrorRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Creating Automated Restore Job from Golden Backup for $dbName on $destination")) {
                Write-Message -Level Verbose -Message "Creating Automated Restore Job from Golden Backup for $dbName on $destination."
                try {
                    if ($Force -eq $true -and $dbccgood -ne "Success") {
                        $jobName = $jobname -replace "Rationalised", "DBCC ERROR"
                    }

                    ## Create a Job Category
                    if (!(Get-DbaAgentJobCategory -SqlInstance $destination -SqlCredential $DestinationCredential -Category $categoryname)) {
                        New-DbaAgentJobCategory -SqlInstance $destination -SqlCredential $DestinationCredential -Category $categoryname
                    }

                    try {
                        if ($Pscmdlet.ShouldProcess($destination, "Creating Agent Job $jobname on $destination")) {
                            $jobParams = @{
                                SqlInstance   = $destination
                                SqlCredential = $DestinationCredential
                                Job           = $jobname
                                Category      = $categoryname
                                Description   = "This job will restore the $dbName database using the final backup located at $filename."
                                Owner         = $jobowner
                            }
                            $job = New-DbaAgentJob @jobParams

                            Write-Message -Level Verbose -Message "Created Agent Job $jobname on $destination."
                        }
                    } catch {
                        Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for this database." -Target $categoryname -ErrorRecord $_ -Continue
                    }

                    ## Create Job Step
                    ## Aaron's Suggestion: In the restore script, add a comment block that tells the last known size of each file in the database.
                    ## Suggestion check for disk space before restore
                    ## Create Restore Script
                    try {
                        $jobStepCommand = Restore-DbaDatabase -SqlInstance $destserver -Path $filename -OutputScriptOnly -WithReplace

                        $jobStepParams = @{
                            SqlInstance     = $destination
                            SqlCredential   = $DestinationCredential
                            Job             = $job
                            StepName        = $jobStepName
                            SubSystem       = 'TransactSql'
                            Command         = $jobStepCommand
                            Database        = 'master'
                            OnSuccessAction = 'QuitWithSuccess'
                            OnFailAction    = 'QuitWithFailure'
                            StepId          = 1
                        }
                        if ($Pscmdlet.ShouldProcess($destination, "Creating Agent JobStep on $destination")) {
                            $jobStep = New-DbaAgentJobStep @jobStepParams
                        }
                        $jobStartStepid = $jobStep.ID
                        Write-Message -Level Verbose -Message "Created Agent JobStep $jobStepName on $destination."
                    } catch {
                        Stop-Function -Message "FAILED : To Create Agent JobStep $jobStepName on $destination - Aborting." -Target $jobStepName -ErrorRecord $_ -Continue
                    }
                    if ($Pscmdlet.ShouldProcess($destination, "Applying Agent Job $jobname to $destination")) {
                        $job.StartStepID = $jobStartStepid
                        $job.Alter()
                    }
                } catch {
                    Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for $dbName. Exception: $_" -Target $jobname -ErrorRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Dropping Database $dbName on $sourceserver")) {
                ## Drop the database
                try {
                    $null = Remove-DbaDatabase -SqlInstance $sourceserver -Database $dbName -Confirm:$false
                    Write-Message -Level Verbose -Message "Dropped $dbName Database on $source prior to running the Agent Job"
                } catch {
                    Stop-Function -Message "FAILED : To Drop database $dbName on $server - aborting routine for $dbName. Exception: $_" -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Running Agent Job on $destination to restore $dbName")) {
                ## Run the restore job to restore it
                Write-Message -Level Verbose -Message "Starting $jobname on $destination."
                try {
                    $job.Start()
                    $job.Refresh()
                    $status = $job.CurrentRunStatus

                    while ($status -ne 'Idle') {
                        Write-Message -Level Verbose -Message "Restore Job for $dbName on $destination is $status."
                        Start-Sleep -Seconds 15
                        $job.Refresh()
                        $status = $job.CurrentRunStatus
                    }

                    Write-Message -Level Verbose -Message "Restore Job $jobname has completed on $destination."
                    Write-Message -Level Verbose -Message "Sleeping for a few seconds to ensure the next step (DBCC) succeeds."
                    Start-Sleep -Seconds 10 ## This is required to ensure the next DBCC Check succeeds
                } catch {
                    Stop-Function -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbName. Exception: $_" -Continue
                }

                if ($job.LastRunOutcome -ne 'Succeeded') {
                    # LOL, love the plug.
                    Write-Message -Level Warning -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbName."
                    Write-Message -Level Warning -Message "Check the Agent Job History on $destination - if you have SSMS2016 July release or later."
                    Write-Message -Level Warning -Message "Get-DbaAgentJobHistory -SqlInstance $destination -Job '$jobname'."

                    continue
                }

                $refreshRetries = 1

                $destserver.Databases.Refresh()
                $restoredDatabase = Get-DbaDatabase -SqlInstance $destserver -Database $dbName
                while ($null -eq $restoredDatabase -and $refreshRetries -lt 6) {
                    Write-Message -Level verbose -Message "Database $dbName not found! Refreshing collection."

                    #refresh database list, otherwise the next step (DBCC) can fail
                    $restoredDatabase.Parent.Databases.Refresh()

                    Start-Sleep -Seconds 1

                    $refreshRetries += 1
                }
            }

            ## Run a Dbcc No choice here
            if ($Pscmdlet.ShouldProcess($dbName, "Running Dbcc CHECKDB on $dbName on $destination")) {
                Write-Message -Level Verbose -Message "Starting Dbcc CHECKDB for $dbName on $destination."
                $dbccgood = Start-DbccCheck -server $sourceserver -dbname $dbName -table

                if ($dbccgood -ne "Success") {
                    Write-Message -Level Verbose -Message "DBCC CHECKDB finished successfully for $dbName on $servername."
                } else {
                    Write-Message -Level Verbose -Message "DBCC failed for $dbName (you should check that). Continuing."
                }
            }

            if ($Pscmdlet.ShouldProcess($dbName, "Dropping Database $dbName on $destination")) {
                ## Drop the database
                try {
                    $null = Remove-DbaDatabase -SqlInstance $destserver -Database $dbName -Confirm:$false
                    Write-Message -Level Verbose -Message "Dropped $dbName database on $destination."
                } catch {
                    Stop-Function -Message "FAILED : To Drop database $dbName on $destination - Aborting. Exception: $_" -Target $dbName -ErrorRecord $_ -Continue
                }
            }
            Write-Message -Level Verbose -Message "Rationalisation Finished for $dbName."

            [PSCustomObject]@{
                SqlInstance     = $source
                DatabaseName    = $dbName
                JobName         = $jobname
                TestingInstance = $destination
                BackupFolder    = $backupFolder
            }
        }
    }

    end {
        if (Test-FunctionInterrupt) {
            return
        }
        if ($Pscmdlet.ShouldProcess("console", "Showing final message")) {
            $End = Get-Date
            Write-Message -Level Verbose -Message "Finished at $End."
            $Duration = $End - $start
            Write-Message -Level Verbose -Message "Script Duration: $Duration."
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUbwJyPDcqfs/7KOk+4b1wUatg
# NQqgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFGjM+rvTwB6EV7UHAijs1rAnJgv6MA0GCSqGSIb3DQEBAQUABIIBAGIEYZBO
# JCJjybnU2R2D0DtDERkoKXDNYABZtx5IS5y56XwefY1CZlCInW5vx4f+Ru/GPVjS
# UUiVPQBSgN+oYsXq/DnSQM1uFtIVQdivEn2S/Z2oncUbQ18R1VQUrfxRWi7Znttj
# jwuJxgS2EJEh64pNuf4e7zeJzoqvQ7pdJaIZAo0UMGoP3MXjV5FMgHL/1LXAG1gV
# RNlxnwdxAMr/vuAa0842ecDwQLlOkcgVZIxMZsaM1XSdYO1wot8oE0NFhDrPz7MO
# +IH3uzuos5XzeJaUrJplXva7nAOxYjxTciYc1F5FUdJVOl88tHBDlidxJJrN2/HP
# ZZv61e0yJf8cUwShggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAwMVowLwYJKoZIhvcNAQkEMSIEIC8Uqi3kY7+qMSeS5QKfelMXKUNY
# AnUIeJOIa865hnA8MA0GCSqGSIb3DQEBAQUABIIBAHsg3/xS/m/ny5/0UBbK/req
# ezYSWW+XndO9/6y/2OoEtt87rjQFTy6KmSpctX/OAolGE+ePqTAdGpDMAXCdDzNN
# dh7j1mC22zOKedeQ81aFSbnvejMPeVuTTb/eSRfipovfMGQc4Si6TLZgpsZfFYff
# yxLhf4YkUSxtnTtVa2O+Dvy/cgKDs+f9aS2oGAlEuCuuLHECesQamynGG8TiRQtT
# tpzu+bkjVdS27Zgh6ALkhjGWGvYPZl5bWFureK42nil+7BF4OuRFAdZaPFahpsup
# TpLpwByG4SmIrKc13UYl5DRBoZvP88q/MXLXGPZSERdPJtEF1LHCI6fDq6m/cfQ=
# SIG # End signature block
