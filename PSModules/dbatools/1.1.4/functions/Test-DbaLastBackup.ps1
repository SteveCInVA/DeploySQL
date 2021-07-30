function Test-DbaLastBackup {
    <#
    .SYNOPSIS
        Quickly and easily tests the last set of full backups for a server.

    .DESCRIPTION
        Restores all or some of the latest backups and performs a DBCC CHECKDB.

        1. Gathers information about the last full backups
        2. Restores the backups to the Destination with a new name. If no Destination is specified, the originating SQL Server instance wil be used.
        3. The database is restored as "dbatools-testrestore-$databaseName" by default, but you can change dbatools-testrestore to whatever you would like using -Prefix
        4. The internal file names are also renamed to prevent conflicts with original database
        5. A DBCC CHECKDB is then performed
        6. And the test database is finally dropped

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Unlike many of the other commands, you cannot specify more than one server.

    .PARAMETER Destination
        The destination server to use to test the restore. By default, the Destination will be set to the source server

        If a different Destination server is specified, you must ensure that the database backups are on a shared location

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database backups to test. If -Database is not provided, all database backups will be tested.

    .PARAMETER ExcludeDatabase
        Exclude specific Database backups to test.

    .PARAMETER DataDirectory
        Specifies an alternative directory for mdfs, ndfs and so on. The command uses the SQL Server's default data directory for all restores.

    .PARAMETER LogDirectory
        Specifies an alternative directory for ldfs. The command uses the SQL Server's default log directory for all restores.

    .PARAMETER VerifyOnly
        If this switch is enabled, VERIFYONLY will be performed. An actual restore will not be executed.

    .PARAMETER NoCheck
        If this switch is enabled, DBCC CHECKDB will be skipped

    .PARAMETER NoDrop
        If this switch is enabled, the newly-created test database will not be dropped.

    .PARAMETER CopyFile
        If this switch is enabled, the backup file will be copied to the destination default backup location unless CopyPath is specified.

    .PARAMETER CopyPath
        Specifies a path relative to the SQL Server to copy backups when CopyFile is specified. If not specified will use destination default backup location. If destination SQL Server is not local, admin UNC paths will be utilized for the copy.

    .PARAMETER MaxSize
        Max size in MB. Databases larger than this value will not be restored.

    .PARAMETER MaxDop
        Allows you to pass in a MAXDOP setting to the DBCC CheckDB command to limit the number of parallel processes used.

    .PARAMETER DeviceType
        Specifies a filter for backup sets based on DeviceTypes. Valid options are 'Disk','Permanent Disk Device', 'Tape', 'Permanent Tape Device','Pipe','Permanent Pipe Device','Virtual Device', in addition to custom integers for your own DeviceTypes.

    .PARAMETER AzureCredential
        The name of the SQL Server credential on the destination instance that holds the key to the azure storage account.

    .PARAMETER IncludeCopyOnly
        If this switch is enabled, copy only backups will be counted as a last backup.

    .PARAMETER IgnoreLogBackup
        If this switch is enabled, transaction log backups will be ignored. The restore will stop at the latest full or differential backup point.

    .PARAMETER IgnoreDiffBackup
        If this switch is enabled, differential backuys will be ignored. The restore will only use Full and Log backups, so will take longer to complete

    .PARAMETER Prefix
        The database is restored as "dbatools-testrestore-$databaseName" by default. You can change dbatools-testrestore to whatever you would like using this parameter.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER MaxTransferSize
        Parameter to set the unit of transfer. Values must be a multiple of 64kb and a max of 4GB
        Parameter is used as passtrough for Restore-DbaDatabase.

    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refererence: https://msdn.microsoft.com/en-us/library/ms178615.aspx#data-transfer-options
        Parameter is used as passtrough for Restore-DbaDatabase.

    .PARAMETER ReuseSourceFolderStructure
        By default, databases will be migrated to the destination Sql Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure.
        The same structure on the SOURCE will be kept exactly, so consider this if you're migrating between different versions and use part of Microsoft's default Sql structure (MSSql12.INSTANCE, etc)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.


    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaLastBackup

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016

        Determines the last full backup for ALL databases, attempts to restore all databases (with a different name and file structure), then performs a DBCC CHECKDB. Once the test is complete, the test restore will be dropped.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -Database SharePoint_Config

        Determines the last full backup for SharePoint_Config, attempts to restore it, then performs a DBCC CHECKDB.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016, sql2017 | Test-DbaLastBackup

        Tests every database backup on sql2016 and sql2017

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016, sql2017 -Database SharePoint_Config | Test-DbaLastBackup

        Tests the database backup for the SharePoint_Config database on sql2016 and sql2017

    .EXAMPLE
       PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -Database model, master -VerifyOnly

       Skips performing an action restore of the database and simply verifies the backup using VERIFYONLY option of the restore.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -NoCheck -NoDrop

        Skips the DBCC CHECKDB check. This can help speed up the tests but makes it less tested. The test restores will remain on the server.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -DataDirectory E:\bigdrive -LogDirectory L:\bigdrive -MaxSize 10240

        Restores data and log files to alternative locations and only restores databases that are smaller than 10 GB.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2014 -Destination sql2016 -CopyFile

        Copies the backup files for sql2014 databases to sql2016 default backup locations and then attempts restore from there.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2014 -Destination sql2016 -CopyFile -CopyPath "\\BackupShare\TestRestore\"

        Copies the backup files for sql2014 databases to sql2016 default backup locations and then attempts restore from there.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -NoCheck -MaxTransferSize 4194302 -BufferCount 24

        Determines the last full backup for ALL databases, attempts to restore all databases (with a different name and file structure).
        The Restore will use more memory for reading the backup files. Do not set these values to high or you can get an Out of Memory error!!!
        When running the restore with these additional parameters and there is other server activity it could affect server OLTP performance. Please use with causion.
        Prior to running, you should check memory and server resources before configure it to run automatically.
        More information:
        https://www.mssqltips.com/sqlservertip/4935/optimize-sql-server-database-restore-performance/

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -MaxDop 4

        The use of the MaxDop parameter will limit the number of processors used during the DBCC command
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameters DestinationCredential and AzureCredential")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [DbaInstanceParameter]$Destination,
        [object]$DestinationCredential,
        [string]$DataDirectory,
        [string]$LogDirectory,
        [string]$Prefix = "dbatools-testrestore-",
        [switch]$VerifyOnly,
        [switch]$NoCheck,
        [switch]$NoDrop,
        [switch]$CopyFile,
        [string]$CopyPath,
        [int]$MaxSize,
        [string[]]$DeviceType,
        [switch]$IncludeCopyOnly,
        [switch]$IgnoreLogBackup,
        [string]$AzureCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [int]$MaxTransferSize,
        [int]$BufferCount,
        [switch]$IgnoreDiffBackup,
        [int]$MaxDop,
        [switch]$ReuseSourceFolderStructure,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if ($db.Name -eq "tempdb") {
                continue
            }

            $sourceserver = $db.Parent
            $source = $db.Parent.Name
            $instance = [DbaInstanceParameter]$source
            $copysuccess = $true
            $dbName = $db.Name
            $restoreresult = $null

            if (-not (Test-Bound -ParameterName Destination)) {
                $destination = $sourceserver.Name
                $DestinationCredential = $SqlCredential
            }

            if ($db.LastFullBackup.Year -eq 1) {
                [pscustomobject]@{
                    SourceServer   = $source
                    TestServer     = $destination
                    Database       = $db.name
                    FileExists     = $false
                    Size           = $null
                    RestoreResult  = "Skipped"
                    DbccResult     = "Skipped"
                    RestoreStart   = $null
                    RestoreEnd     = $null
                    RestoreElapsed = $null
                    DbccMaxDop     = $null
                    DbccStart      = $null
                    DbccEnd        = $null
                    DbccElapsed    = $null
                    BackupDates    = $null
                    BackupFiles    = $null
                }
                continue
            }

            try {
                $destserver = Connect-SqlInstance -SqlInstance $destination -SqlCredential $DestinationCredential
            } catch {
                Stop-Function -Message "Failed to connect to: $destination." -Target $destination -Continue
            }

            if ($destserver.VersionMajor -lt $sourceserver.VersionMajor) {
                Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue
            }

            if ($destserver.VersionMajor -eq $sourceserver.VersionMajor -and $destserver.VersionMinor -lt $sourceserver.VersionMinor) {
                Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue
            }

            if ($CopyPath) {
                $testpath = Test-DbaPath -SqlInstance $destserver -Path $CopyPath
                if (-not $testpath) {
                    Stop-Function -Message "$destserver cannot access $CopyPath." -Continue
                }
            } else {
                # If not CopyPath is specified, use the destination server default backup directory
                $copyPath = $destserver.BackupDirectory
            }

            if ($instance -ne $destination -and -not $CopyFile) {
                $sourcerealname = $sourceserver.ComputerNetBiosName
                $destrealname = $destserver.ComputerNetBiosName

                if ($BackupFolder) {
                    if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcerealname -ne $destrealname) {
                        Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -Continue
                    }
                }
            }

            if ($datadirectory) {
                if (-not (Test-DbaPath -SqlInstance $destserver -Path $datadirectory)) {
                    $serviceAccount = $destserver.ServiceAccount
                    Stop-Function -Message "Can't access $datadirectory Please check if $serviceAccount has permissions." -Continue
                }
            } else {
                $datadirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType mdf
            }

            if ($logdirectory) {
                if (-not (Test-DbaPath -SqlInstance $destserver -Path $logdirectory)) {
                    $serviceAccount = $destserver.ServiceAccount
                    Stop-Function -Message "$Destination can't access its local directory $logdirectory. Please check if $serviceAccount has permissions." -Continue
                }
            } else {
                $logdirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType ldf
            }

            if ((Test-Bound -ParameterName AzureCredential) -and (Test-Bound -ParameterName CopyFile)) {
                Stop-Function -Message "Cannot use copyfile with Azure backups, set to false." -continue
                $CopyFile = $false
            }

            Write-Message -Level Verbose -Message "Getting recent backup history for $($db.Name) on $instance."

            if (Test-Bound "IgnoreLogBackup") {
                Write-Message -Level Verbose -Message "Skipping Log backups as requested."
                $lastbackup = @()
                $lastbackup += $full = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -LastFull -DeviceType $DeviceType -WarningAction SilentlyContinue
                if (-not (Test-Bound "IgnoreDiffBackup")) {
                    $diff = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -LastDiff -DeviceType $DeviceType -WarningAction SilentlyContinue
                }
                if ($full.start -le $diff.start) {
                    $lastbackup += $diff
                }
            } else {
                $lastbackup = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -Last -DeviceType $DeviceType -WarningAction SilentlyContinue -IgnoreDiffBackup:$IgnoreDiffBackup
            }

            if (-not $lastbackup) {
                Write-Message -Level Verbose -Message "No backups exist for this database."
                $lastbackup = @{
                    Path = "No backups exist for this database"
                }
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
                continue
            }

            if ($CopyFile) {
                try {
                    Write-Message -Level Verbose -Message "Gathering information for file copy."
                    $removearray = @()

                    foreach ($backup in $lastbackup) {
                        foreach ($file in $backup) {
                            $filename = Split-Path -Path $file.FullName -Leaf
                            Write-Message -Level Verbose -Message "Processing $filename."

                            $sourcefile = Join-AdminUnc -servername $instance.ComputerName -filepath "$($file.Path)"

                            if ($instance.IsLocalHost) {
                                $remotedestdirectory = Join-AdminUnc -servername $instance.ComputerName -filepath $copyPath
                            } else {
                                $remotedestdirectory = $copyPath
                            }

                            $remotedestfile = "$remotedestdirectory\$filename"
                            $localdestfile = "$copyPath\$filename"
                            Write-Message -Level Verbose -Message "Destination directory is $destdirectory."
                            Write-Message -Level Verbose -Message "Destination filename is $remotedestfile."

                            try {
                                Write-Message -Level Verbose -Message "Copying $sourcefile to $remotedestfile."
                                Copy-Item -Path $sourcefile -Destination $remotedestfile -ErrorAction Stop
                                $backup.Path = $localdestfile
                                $backup.FullName = $localdestfile
                                $removearray += $remotedestfile
                            } catch {
                                $backup.Path = $sourcefile
                                $backup.FullName = $sourcefile
                            }
                        }
                    }
                    $copysuccess = $true
                } catch {
                    Write-Message -Level Warning -Message "Failed to copy backups for $dbName on $instance to $destdirectory - $_."
                    $copysuccess = $false
                }
            }
            if (-not $copysuccess) {
                Write-Message -Level Verbose -Message "Failed to copy backups."
                $lastbackup = @{
                    Path = "Failed to copy backups"
                }
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
            } elseif (-not ($lastbackup | Where-Object { $_.type -eq 'Full' })) {
                Write-Message -Level Verbose -Message "No full backup returned from lastbackup."
                $lastbackup = @{
                    Path = "Not found"
                }
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
            } elseif ($source -ne $destination -and $lastbackup[0].Path.StartsWith('\\') -eq $false -and -not $CopyFile) {
                Write-Message -Level Verbose -Message "Path not UNC and source does not match destination. Use -CopyFile to move the backup file."
                $fileexists = $dbccresult = "Skipped"
                $success = $restoreresult = "Restore not located on shared location"
            } elseif (($lastbackup[0].Path | ForEach-Object { Test-DbaPath -SqlInstance $destserver -Path $_ }) -eq $false) {
                Write-Message -Level Verbose -Message "SQL Server cannot find backup."
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
            }
            if ($restoreresult -ne "Skipped" -or $lastbackup[0].Path -like 'http*') {
                Write-Message -Level Verbose -Message "Looking good."

                $fileexists = $true
                $ogdbname = $dbName
                $restorelist = Read-DbaBackupHeader -SqlInstance $destserver -Path $lastbackup[0].Path -AzureCredential $AzureCredential

                $totalsize = ($restorelist.BackupSize.Megabyte | Measure-Object -Sum ).Sum

                if ($MaxSize -and $MaxSize -lt $totalsize) {
                    $success = "The backup size for $dbName ($totalsize MB) exceeds the specified maximum size ($MaxSize MB)."
                    $dbccresult = "Skipped"
                } else {
                    $dbccElapsed = $restoreElapsed = $startRestore = $endRestore = $startDbcc = $endDbcc = $null

                    $dbName = "$prefix$dbName"
                    $destdb = $destserver.databases[$dbName]

                    if ($destdb) {
                        Stop-Function -Message "$dbName already exists on $destination - skipping." -Continue
                    }

                    if ($Pscmdlet.ShouldProcess($destination, "Restoring $ogdbname as $dbName.")) {
                        Write-Message -Level Verbose -Message "Performing restore."
                        $startRestore = Get-Date
                        try {
                            if ($ReuseSourceFolderStructure) {
                                $restoreSplat = @{
                                    SqlInstance                = $destserver
                                    RestoredDatabaseNamePrefix = $prefix
                                    DestinationFilePrefix      = $Prefix
                                    IgnoreLogBackup            = $IgnoreLogBackup
                                    AzureCredential            = $AzureCredential
                                    TrustDbBackupHistory       = $true
                                    ReuseSourceFolderStructure = $true
                                    EnableException            = $true
                                }
                            } else {
                                $restoreSplat = @{
                                    SqlInstance                = $destserver
                                    RestoredDatabaseNamePrefix = $prefix
                                    DestinationFilePrefix      = $Prefix
                                    DestinationDataDirectory   = $datadirectory
                                    DestinationLogDirectory    = $logdirectory
                                    IgnoreLogBackup            = $IgnoreLogBackup
                                    AzureCredential            = $AzureCredential
                                    TrustDbBackupHistory       = $true
                                    EnableException            = $true
                                }
                            }

                            if (Test-Bound "MaxTransferSize") {
                                $restoreSplat.Add('MaxTransferSize', $MaxTransferSize)
                            }
                            if (Test-Bound "BufferCount") {
                                $restoreSplat.Add('BufferCount', $BufferCount)
                            }

                            if ($verifyonly) {
                                $restoreresult = $lastbackup | Restore-DbaDatabase @restoreSplat -VerifyOnly:$VerifyOnly
                            } else {
                                $restoreresult = $lastbackup | Restore-DbaDatabase @restoreSplat
                                Write-Message -Level Verbose -Message " Restore-DbaDatabase -SqlInstance $destserver -RestoredDatabaseNamePrefix $prefix -DestinationFilePrefix $Prefix -DestinationDataDirectory $datadirectory -DestinationLogDirectory $logdirectory -IgnoreLogBackup:$IgnoreLogBackup -AzureCredential $AzureCredential -TrustDbBackupHistory"
                            }
                        } catch {
                            $errormsg = Get-ErrorMessage -Record $_
                        }

                        $endRestore = Get-Date
                        $restorets = New-TimeSpan -Start $startRestore -End $endRestore
                        $ts = [timespan]::fromseconds($restorets.TotalSeconds)
                        $restoreElapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                        if ($restoreresult.RestoreComplete -eq $true) {
                            $success = "Success"
                        } else {
                            if ($errormsg) {
                                $success = $errormsg
                            } else {
                                $success = "Failure"
                            }
                        }
                    }

                    $destserver = Connect-SqlInstance -SqlInstance $destination -SqlCredential $DestinationCredential

                    if (-not $NoCheck -and -not $VerifyOnly) {
                        # shouldprocess is taken care of in Start-DbccCheck
                        if ($ogdbname -eq "master") {
                            $dbccresult =
                            "DBCC CHECKDB skipped for restored master ($dbName) database. `
                             The master database cannot be copied off of a server and have a successful DBCC CHECKDB. `
                             See https://www.itprotoday.com/my-master-database-really-corrupt for more information."
                        } else {
                            if ($success -eq "Success") {
                                Write-Message -Level Verbose -Message "Starting DBCC."

                                $startDbcc = Get-Date
                                $dbccresult = Start-DbccCheck -Server $destserver -DbName $dbName -MaxDop $MaxDop 3>$null
                                $endDbcc = Get-Date

                                $dbccts = New-TimeSpan -Start $startDbcc -End $endDbcc
                                $ts = [timespan]::fromseconds($dbccts.TotalSeconds)
                                $dbccElapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)
                            } else {
                                $dbccresult = "Skipped"
                            }
                        }
                    }

                    if ($VerifyOnly) {
                        $dbccresult = "Skipped"
                    }

                    if (-not $NoDrop -and $null -ne $destserver.databases[$dbName]) {
                        if ($Pscmdlet.ShouldProcess($dbName, "Dropping Database $dbName on $destination")) {
                            Write-Message -Level Verbose -Message "Dropping database."

                            ## Drop the database
                            try {
                                #Variable $removeresult marked as unused by PSScriptAnalyzer replace with $null to catch output
                                $null = Remove-DbaDatabase -SqlInstance $destserver -Database $dbName -Confirm:$false
                                Write-Message -Level Verbose -Message "Dropped $dbName Database on $destination."
                            } catch {
                                $destserver.Databases.Refresh()
                                if ($destserver.databases[$dbName]) {
                                    Write-Message -Level Warning -Message "Failed to Drop database $dbName on $destination."
                                }
                            }
                        }
                    }

                    #Cleanup BackupFiles if -CopyFile and backup was moved to destination

                    $destserver.Databases.Refresh()
                    if ($destserver.Databases[$dbName] -and -not $NoDrop) {
                        Write-Message -Level Warning -Message "$dbName was not dropped."
                    }
                }

                if ($CopyFile) {
                    Write-Message -Level Verbose -Message "Removing copied backup file from $destination."
                    try {
                        $removearray | Remove-Item -ErrorAction Stop
                    } catch {
                        Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $instance
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess("console", "Showing results")) {
                [pscustomobject]@{
                    SourceServer   = $source
                    TestServer     = $destination
                    Database       = $db.name
                    FileExists     = $fileexists
                    Size           = [dbasize](($lastbackup.TotalSize | Measure-Object -Sum).Sum)
                    RestoreResult  = $success
                    DbccResult     = $dbccresult
                    RestoreStart   = [dbadatetime]$startRestore
                    RestoreEnd     = [dbadatetime]$endRestore
                    RestoreElapsed = $restoreElapsed
                    DbccMaxDop     = [int]$MaxDop
                    DbccStart      = [dbadatetime]$startDbcc
                    DbccEnd        = [dbadatetime]$endDbcc
                    DbccElapsed    = $dbccElapsed
                    BackupDates    = [String[]]($lastbackup.Start)
                    BackupFiles    = $lastbackup.FullName
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUIQbw4cSgKoaiC0aKAEqu8223
# M6agghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFF0Nt2YC693yXrL18ymBlc5ORy7OMA0GCSqGSIb3DQEBAQUABIIBAHehgTgr
# mw9NIgzAMf/MOFWEQbcRIIDr4EI8EpMevzWj9WZRd8ov9Ij0SZG7tBess3HDGAC9
# pyUT8dm5eqGTuE4skvcsn+KKYnvlvRTXP9D6OcjqTKCbM30GqJQ1DVy8eUWrX1Lm
# XLxBs1rq4tfYUU5MHAXOdpVHFkVyexUCXS+gSEEkwq+zvWain8liSWSgFwVGkjIX
# e/0OQYOOzYDHUJuf2n/0pyzIrEzdMU7++StI+tG6t9iRB8ffIGB7OIL7QIAFeO/n
# fTZim37D2ErnJwVFvZ8NGQ6sJwObPSQ0n5HDYDwP2/a02oG+Dlmm0nmj2TuiRN6R
# UIqQRhTiMVyISduhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAxNVowLwYJKoZIhvcNAQkEMSIEICRftHL+g6p5Te8IE+AYCuWN2Gx6
# MeU6D84M2xIvCRg9MA0GCSqGSIb3DQEBAQUABIIBAEGWRAnksRpBvL4s43+HWU90
# +lw5Uee/aaLP8F8kMnRRhroSrfwZnBNOBlLZXxYUARrW7wTkwi4slRwpqlasaXMw
# JhPhOOxqHMVL5actxL60Mayr2mt6sVFKDDablrNj3ePnV21SM4H13nYRvCMOsbI2
# akFXmBZbix/cSi0rz2MnWK06vZK+YSHz2MgLOyMxKJAJkKxrbkQTAhiOTh0yIykL
# /osXsHV/KdLVyyGffnOgOupXt8n1V503jKcXUljhAK3dADb65gHwTm+EROI58syj
# tmhZzf5c2xsIPXc0mEkeVQ0oo+G/qrfCfrqM8m1JrV20KiEegEnkT0hMvl9LxyQ=
# SIG # End signature block
