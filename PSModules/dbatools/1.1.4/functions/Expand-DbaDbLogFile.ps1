function Expand-DbaDbLogFile {
    <#
    .SYNOPSIS
        This command will help you to automatically grow your transaction log  file in a responsible way (preventing the generation of too many VLFs).

    .DESCRIPTION
        As you may already know, having a transaction log file with too many Virtual Log Files (VLFs) can hurt your database performance in many ways.

        Example:
        Too many VLFs can cause transaction log backups to slow down and can also slow down database recovery and, in extreme cases, even impact insert/update/delete performance.

        References:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
        http://www.brentozar.com/blitz/high-virtual-log-file-vlf-count/

        In order to get rid of this fragmentation we need to grow the file taking the following into consideration:
        - How many VLFs are created when we perform a grow operation or when an auto-grow is invoked?

        Note: In SQL Server 2014 this algorithm has changed (http://www.sqlskills.com/blogs/paul/important-change-vlf-creation-algorithm-sql-server-2014/)

        Attention:
        We are growing in MB instead of GB because of known issue prior to SQL 2012:
        More detail here:
        http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
        and
        http://connect.microsoft.com/SqlInstance/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
        or
        https://connect.microsoft.com/SqlInstance/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb

        Understanding related problems:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
        http://www.brentozar.com/blitz/high-virtual-log-file-vlf-count/

        Known bug before SQL Server 2012
        http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
        http://connect.microsoft.com/SqlInstance/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
        https://connect.microsoft.com/SqlInstance/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb

        How it works?
        The transaction log will grow in chunks until it reaches the desired size.
        Example: If you have a log file with 8192MB and you say that the target size is 81920MB (80GB) it will grow in chunks of 8192MB until it reaches 81920MB. 8192 -> 16384 -> 24576 ... 73728 -> 81920

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER TargetLogSize
        Specifies the target size of the transaction log file in megabytes.

    .PARAMETER IncrementSize
        Specifies the amount the transaction log should grow in megabytes. If this value differs from the suggested value based on your TargetLogSize, you will be prompted to confirm your choice.

        This value will be calculated if not specified.

    .PARAMETER LogFileId
        Specifies the file number(s) of additional transaction log files to grow.

        If this value is not specified, only the first transaction log file will be processed.

    .PARAMETER ShrinkLogFile
        If this switch is enabled, your transaction log files will be shrunk.

    .PARAMETER ShrinkSize
        Specifies the target size of the transaction log file for the shrink operation in megabytes.

    .PARAMETER BackupDirectory
        Specifies the location of your backups. Backups must be performed to shrink the transaction log.

        If this value is not specified, the SQL Server instance's default backup directory will be used.

    .PARAMETER ExcludeDiskSpaceValidation
        If this switch is enabled, the validation for enough disk space using Get-DbaDiskSpace command will be skipped.
        This can be useful when you know that you have enough space to grow your TLog but you don't have PowerShell Remoting enabled to validate it.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Backup
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: ALTER DATABASE permission
        Limitations: Freespace cannot be validated on the directory where the log file resides in SQL Server 2005.
        This script uses Get-DbaDiskSpace dbatools command to get the TLog's drive free space

    .LINK
        https://dbatools.io/Expand-DbaDbLogFile

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database db1 -TargetLogSize 50000

        Grows the transaction log for database db1 on sqlcluster to 50000 MB and calculates the increment size.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database db1, db2 -TargetLogSize 10000 -IncrementSize 200

        Grows the transaction logs for databases db1 and db2 on sqlcluster to 1000MB and sets the growth increment to 200MB.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database db1 -TargetLogSize 10000 -LogFileId 9

        Grows the transaction log file  with FileId 9 of the db1 database on sqlcluster instance to 10000MB.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database (Get-Content D:\DBs.txt) -TargetLogSize 50000

        Grows the transaction log of the databases specified in the file 'D:\DBs.txt' on sqlcluster instance to 50000MB.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance SqlInstance -Database db1,db2 -TargetLogSize 100 -IncrementSize 10 -ShrinkLogFile -ShrinkSize 10 -BackupDirectory R:\MSSQL\Backup

        Grows the transaction logs for databases db1 and db2 on SQL server SQLInstance to 100MB, sets the incremental growth to 10MB, shrinks the transaction log to 10MB and uses the directory R:\MSSQL\Backup for the required backups.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default')]
    param (
        [parameter(Position = 1, Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [parameter(Position = 3)]
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [parameter(Position = 4)]
        [object[]]$ExcludeDatabase,
        [parameter(Position = 5, Mandatory)]
        [int]$TargetLogSize,
        [parameter(Position = 6)]
        [int]$IncrementSize = -1,
        [parameter(Position = 7)]
        [int]$LogFileId = -1,
        [parameter(Position = 8, ParameterSetName = 'Shrink', Mandatory)]
        [switch]$ShrinkLogFile,
        [parameter(Position = 9, ParameterSetName = 'Shrink', Mandatory)]
        [int]$ShrinkSize,
        [parameter(Position = 10, ParameterSetName = 'Shrink')]
        [AllowEmptyString()]
        [string]$BackupDirectory,
        [switch]$ExcludeDiskSpaceValidation,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level Verbose -Message "Set ErrorActionPreference to Inquire."
        $ErrorActionPreference = 'Inquire'

        #Convert MB to KB (SMO works in KB)
        Write-Message -Level Verbose -Message "Convert variables MB to KB (SMO works in KB)."
        [int]$TargetLogSizeKB = $TargetLogSize * 1024
        [int]$LogIncrementSize = $IncrementSize * 1024
        [int]$ShrinkSizeKB = $ShrinkSize * 1024
        [int]$SuggestLogIncrementSize = 0
        [bool]$LogByFileID = if ($LogFileId -eq -1) {
            $false
        } else {
            $true
        }

        #Set base information
        Write-Message -Level Verbose -Message "Initialize the instance '$SqlInstance'."

        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential

        if ($ShrinkLogFile -eq $true) {
            if ($BackupDirectory.length -eq 0) {
                $backupdirectory = $server.Settings.BackupDirectory
            }

            $pathexists = Test-DbaPath -SqlInstance $server -Path $backupdirectory

            if ($pathexists -eq $false) {
                Stop-Function -Message "Backup directory does not exist."
            }
        }
    }

    process {

        try {

            [datetime]$initialTime = Get-Date

            #control the iteration number
            $databaseProgressbar = 0;

            Write-Message -Level Verbose -Message "Resolving FullComputerName name."
            # We don't have windows credentials here, so Resolve-DbaNetworkName has to respect that and work like Resolve-NetBiosName did before.
            $resolvedComputerName = Resolve-DbaComputerName -ComputerName $SqlInstance

            $databases = $server.Databases | Where-Object IsAccessible
            Write-Message -Level Verbose -Message "Number of databases found: $($databases.Count)."
            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            #go through all databases
            Write-Message -Level Verbose -Message "Processing...foreach database..."
            foreach ($db in $databases.Name) {
                Write-Message -Level Verbose -Message "Working on $db."
                $databaseProgressbar += 1

                #set step to reutilize on logging operations
                [string]$step = "$databaseProgressbar/$($Databases.Count)"

                if ($server.Databases[$db]) {
                    Write-Progress `
                        -Id 1 `
                        -Activity "Using database: $db on Instance: '$SqlInstance'" `
                        -PercentComplete ($databaseProgressbar / $Databases.Count * 100) `
                        -Status "Processing - $databaseProgressbar of $($Databases.Count)"

                    #Validate which file will grow
                    if ($LogByFileID) {
                        $logfile = $server.Databases[$db].LogFiles.ItemById($LogFileId)
                    } else {
                        $logfile = $server.Databases[$db].LogFiles[0]
                    }

                    $numLogfiles = $server.Databases[$db].LogFiles.Count

                    Write-Message -Level Verbose -Message "$step - Use log file: $logfile."
                    $currentSize = $logfile.Size
                    $currentSizeMB = $currentSize / 1024

                    #Get the number of VLFs
                    $initialVLFCount = Measure-DbaDbVirtualLogFile -SqlInstance $server -Database $db

                    Write-Message -Level Verbose -Message "$step - Log file current size: $([System.Math]::Round($($currentSize/1024.0), 2)) MB "
                    [long]$requiredSpace = ($TargetLogSizeKB - $currentSize)

                    if ($ExcludeDiskSpaceValidation -eq $false) {
                        Write-Message -Level Verbose -Message "Verifying if sufficient space exists ($([System.Math]::Round($($requiredSpace / 1024.0), 2))MB) on the volume to perform this task."

                        [long]$TotalTLogFreeDiskSpaceKB = 0
                        Write-Message -Level Verbose -Message "Get TLog drive free space"

                        try {
                            # That would need a Credential, but we don't have one...
                            [object]$AllDrivesFreeDiskSpace = Get-DbaDiskSpace -ComputerName $resolvedComputerName | Select-Object Name, SizeInKB

                            #Verify path using Split-Path on $logfile.FileName in backwards. This way we will catch the LUNs. Example: "K:\Log01" as LUN name. Need to add final backslash if not there
                            $DrivePath = Split-Path $logfile.FileName -parent
                            $DrivePath = if (!($DrivePath.EndsWith("\"))) { "$DrivePath\" }
                            else { $DrivePath }
                            Do {
                                if ($AllDrivesFreeDiskSpace | Where-Object { $DrivePath -eq "$($_.Name)" }) {
                                    $TotalTLogFreeDiskSpaceKB = ($AllDrivesFreeDiskSpace | Where-Object { $DrivePath -eq $_.Name }).SizeInKB
                                    $match = $true
                                    break
                                } else {
                                    $match = $false
                                    $DrivePath = Split-Path $DrivePath -parent
                                    $DrivePath = if (!($DrivePath.EndsWith("\"))) { "$DrivePath\" }
                                    else { $DrivePath }
                                }

                            }
                            while (!$match -or ([string]::IsNullOrEmpty($DrivePath)))

                            Write-Message -Level Verbose -Message "Total TLog Free Disk Space in MB: $([System.Math]::Round($($TotalTLogFreeDiskSpaceKB / 1024.0), 2))"

                        } catch {
                            #Could not validate the disk space. Will ask if we want to continue.
                            $TotalTLogFreeDiskSpaceKB = 0
                        }

                        if (($TotalTLogFreeDiskSpaceKB -le 0) -or ([string]::IsNullOrEmpty($TotalTLogFreeDiskSpaceKB))) {
                            $title = "Choose increment value for database '$db':"
                            $message = "Cannot validate freespace on drive where the log file resides. Do you wish to continue? (Y/N)"
                            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                            $result = $host.ui.PromptForChoice($title, $message, $options, 0)
                            #no
                            if ($result -eq 1) {
                                Write-Message -Level Warning -Message "You have cancelled the execution"
                                return
                            }
                        } elseif ($requiredSpace -gt $TotalTLogFreeDiskSpaceKB) {
                            Write-Message -Level Verbose -Message "There is not enough space on volume to perform this task. `r`n" `
                                "Available space: $([System.Math]::Round($($TotalTLogFreeDiskSpaceKB / 1024.0), 2))MB;`r`n" `
                                "Required space: $([System.Math]::Round($($requiredSpace / 1024.0), 2))MB;"
                            return
                        }
                    }

                    if ($currentSize -ige $TargetLogSizeKB -and ($ShrinkLogFile -eq $false)) {
                        Write-Message -Level Verbose -Message "$step - [INFO] The T-Log file '$logfile' size is already equal or greater than target size - No action required."
                    } else {
                        Write-Message -Level Verbose -Message "$step - [OK] There is sufficient free space to perform this task."

                        # If SQL Server version is greater or equal to 2012
                        if ($server.Version.Major -ge "11") {
                            switch ($TargetLogSize) {
                                { $_ -le 64 } { $SuggestLogIncrementSize = 64 }
                                { $_ -ge 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
                                { $_ -ge 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
                                { $_ -ge 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
                                { $_ -ge 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
                                { $_ -ge 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4096 }
                                { $_ -ge 16384 } { $SuggestLogIncrementSize = 8192 }
                            }
                        }
                        # 2008 R2 or under
                        else {
                            switch ($TargetLogSize) {
                                { $_ -le 64 } { $SuggestLogIncrementSize = 64 }
                                { $_ -ge 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
                                { $_ -ge 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
                                { $_ -ge 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
                                { $_ -ge 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
                                { $_ -ge 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4000 }
                                { $_ -ge 16384 } { $SuggestLogIncrementSize = 8000 }
                            }

                            if (($IncrementSize % 4096) -eq 0) {
                                Write-Message -Level Verbose -Message "Your instance version is below SQL 2012, remember the known BUG mentioned on HELP. `r`nUse Get-Help Expand-DbaTLogFileResponsibly to read help`r`nUse a different value for incremental size.`r`n"
                                return
                            }
                        }
                        Write-Message -Level Verbose -Message "Instance $server version: $($server.Version.Major) - Suggested TLog increment size: $($SuggestLogIncrementSize)MB"

                        # Shrink Log File to desired size before re-growth to desired size (You need to remove as many VLF's as possible to ensure proper growth)
                        $ShrinkSize = $ShrinkSizeKB / 1024
                        if ($ShrinkLogFile -eq $true) {
                            if ($server.Databases[$db].RecoveryModel -eq [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple) {
                                Write-Message -Level Warning -Message "Database '$db' is in Simple RecoveryModel which does not allow log backups. Do not specify -ShrinkLogFile and -ShrinkSize parameters."
                                Continue
                            }

                            try {
                                $sql = "SELECT last_log_backup_lsn FROM sys.database_recovery_status WHERE database_id = DB_ID('$db')"
                                $sqlResult = $server.ConnectionContext.ExecuteWithResults($sql);

                                if ($sqlResult.Tables[0].Rows[0]["last_log_backup_lsn"] -is [System.DBNull]) {
                                    Write-Message -Level Warning -Message "First, you need to make a full backup before you can do Tlog backup on database '$db' (last_log_backup_lsn is null)."
                                    Continue
                                }
                            } catch {
                                Stop-Function -Message "Can't execute SQL on $server. `r`n $($_)" -Continue
                            }

                            If ($Pscmdlet.ShouldProcess($($server.name), "Backing up TLog for $db")) {
                                Write-Message -Level Verbose -Message "We are about to backup the Tlog for database '$db' to '$backupdirectory' and shrink the log."
                                Write-Message -Level Verbose -Message "Starting Size = $currentSizeMB."

                                $DefaultCompression = $server.Configuration.DefaultBackupCompression.ConfigValue

                                if ($currentSizeMB -gt $ShrinkSize) {
                                    $backupRetries = 1
                                    Do {
                                        try {
                                            $percent = $null
                                            $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
                                            $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Log
                                            $backup.BackupSetDescription = "Transaction Log backup of " + $db
                                            $backup.BackupSetName = $db + " Backup"
                                            $backup.Database = $db
                                            $backup.MediaDescription = "Disk"
                                            $dt = Get-Date -format yyyyMMddHHmmssms
                                            $null = $backup.Devices.AddDevice($backupdirectory + "\" + $db + "_db_" + $dt + ".trn", 'File')
                                            if ($DefaultCompression -eq $true) {
                                                $backup.CompressionOption = 1
                                            } else {
                                                $backup.CompressionOption = 0
                                            }
                                            $null = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                                                Write-Progress -id 2 -ParentId 1 -activity "Backing up $db to $server" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
                                            }
                                            $backup.add_PercentComplete($percent)
                                            $backup.PercentCompleteNotification = 10
                                            $backup.add_Complete($complete)
                                            Write-Progress -id 2 -ParentId 1 -activity "Backing up $db to $server" -percentcomplete 0 -Status ([System.String]::Format("Progress: {0} %", 0))
                                            $backup.SqlBackup($server)
                                            Write-Progress -id 2 -ParentId 1 -activity "Backing up $db to $server" -status "Complete" -Completed
                                            $logfile.Shrink($ShrinkSize, [Microsoft.SqlServer.Management.SMO.ShrinkMethod]::TruncateOnly)
                                            $logfile.Refresh()
                                        } catch {
                                            Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
                                            Stop-Function -Message "Backup failed for database" -ErrorRecord $_ -Target $db -Continue
                                            Continue
                                        }

                                    }
                                    while (($logfile.Size / 1024) -gt $ShrinkSize -and ++$backupRetries -lt 6)

                                    $currentSize = $logfile.Size
                                    Write-Message -Level Verbose -Message "TLog backup and truncate for database '$db' finished. Current TLog size after $backupRetries backups is $($currentSize/1024)MB"
                                }
                            }
                        }

                        # SMO uses values in KB
                        $SuggestLogIncrementSize = $SuggestLogIncrementSize * 1024

                        # If default, use $SuggestedLogIncrementSize
                        if ($IncrementSize -eq -1) {
                            $LogIncrementSize = $SuggestLogIncrementSize
                        } else {
                            if ($LogIncrementSize -lt $SuggestLogIncrementSize) {
                                Write-Message -Level Warning -Message "The input value for increment size is $([System.Math]::Round($LogIncrementSize / 1024, 0))MB, which is less than the suggested value of $($SuggestLogIncrementSize / 1024)MB."
                            }
                        }

                        #start growing file
                        If ($Pscmdlet.ShouldProcess($($server.name), "Starting log growth. Increment chunk size: $($LogIncrementSize/1024)MB for database '$db'")) {
                            Write-Message -Level Verbose -Message "Starting log growth. Increment chunk size: $($LogIncrementSize/1024)MB for database '$db'"

                            Write-Message -Level Verbose -Message "$step - While current size less than target log size."

                            while ($currentSize -lt $TargetLogSizeKB) {

                                Write-Progress `
                                    -Id 2 `
                                    -ParentId 1 `
                                    -Activity "Growing file $logfile on '$db' database" `
                                    -PercentComplete ($currentSize / $TargetLogSizeKB * 100) `
                                    -Status "Remaining - $([System.Math]::Round($($($TargetLogSizeKB - $currentSize) / 1024.0), 2)) MB"

                                Write-Message -Level Verbose -Message "$step - Verifying if the log can grow or if it's already at the desired size."
                                if (($TargetLogSizeKB - $currentSize) -lt $LogIncrementSize) {
                                    Write-Message -Level Verbose -Message "$step - Log size is lower than the increment size. Setting current size equals $TargetLogSizeKB."
                                    $currentSize = $TargetLogSizeKB
                                } else {
                                    Write-Message -Level Verbose -Message "$step - Grow the $logfile file in $([System.Math]::Round($($LogIncrementSize / 1024.0), 2)) MB"
                                    $currentSize += $LogIncrementSize
                                }

                                #When -WhatIf Switch, do not run
                                if ($PSCmdlet.ShouldProcess("$step - File will grow to $([System.Math]::Round($($currentSize/1024.0), 2)) MB", "This action will grow the file $logfile on database $db to $([System.Math]::Round($($currentSize/1024.0), 2)) MB .`r`nDo you wish to continue?", "Perform grow")) {
                                    Write-Message -Level Verbose -Message "$step - Set size $logfile to $([System.Math]::Round($($currentSize/1024.0), 2)) MB"
                                    $logfile.size = $currentSize

                                    Write-Message -Level Verbose -Message "$step - Applying changes"
                                    $logfile.Alter()
                                    Write-Message -Level Verbose -Message "$step - Changes have been applied"

                                    #Will put the info like VolumeFreeSpace up to date
                                    $logfile.Refresh()
                                }
                            }

                            Write-Message -Level Verbose -Message "`r`n$step - [OK] Growth process for logfile '$logfile' on database '$db', has been finished."

                            Write-Message -Level Verbose -Message "$step - Grow $logfile log file on $db database finished."
                        }
                    }
                }
                #else verifying existence
                else {
                    Write-Message -Level Verbose -Message "Database '$db' does not exist on instance '$SqlInstance'."
                }

                #Get the number of VLFs
                $currentVLFCount = Measure-DbaDbVirtualLogFile -SqlInstance $server -Database $db

                [pscustomobject]@{
                    ComputerName    = $server.ComputerName
                    InstanceName    = $server.ServiceName
                    SqlInstance     = $server.DomainInstanceName
                    Database        = $db
                    ID              = $logfile.ID
                    Name            = $logfile.Name
                    LogFileCount    = $numLogfiles
                    InitialSize     = [dbasize]($currentSizeMB * 1024 * 1024)
                    CurrentSize     = [dbasize]($TargetLogSize * 1024 * 1024)
                    InitialVLFCount = $initialVLFCount.Total
                    CurrentVLFCount = $currentVLFCount.Total
                } | Select-DefaultView -ExcludeProperty LogFileCount
            } #foreach database
        } catch {
            Stop-Function -Message "Logfile $logfile on database $db not processed. Error: $($_.Exception.Message). Line Number:  $($_InvocationInfo.ScriptLineNumber)" -Continue
        }
    }

    end {
        Write-Message -Level Verbose -Message "Process finished $((Get-Date) - ($initialTime))"
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUb3KsIcJ+regVzbBTUHDLpZ4J
# nhOgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFOyPc/1n19dP8GG2zXHxcGIGv3TwMA0GCSqGSIb3DQEBAQUABIIBALbuKI6o
# Eqw5XP0mbfaoyiOqu3ce3WSgZyOg/rztwHrskG1JhGmcaer+y38Y/eViiYdWtvQD
# plTZxnD6YuHO9B03krxPgPppHj6lk9aqBn1O5Eazlawhi/vae9lN4vcQqNxixeby
# aAheeUBuZsjdfhOgfX/Ayp0Egfx+h0Dt2JuZoYnaifxZs3BcGRyvQKunqWxq/ZDk
# 5RNd4gzcAhX8ypSf8U67o3msstxc2/ZRD4sCmjAoNx2swl4xnPpotmN+9oOepxzr
# TGOxxEUUakUvFDK6Mn4Ag+2tZeo4fohN94d2dp+zrW8dwyDKa+7OBq3PuApG981I
# GUK/begW9/MtMPChggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkyMFowLwYJKoZIhvcNAQkEMSIEIKmza0IshF/Ts0gHz4chPIZvY0eE
# zESOlayIMyhpfadzMA0GCSqGSIb3DQEBAQUABIIBAIWQ0BPnBd4HgfL7ozE3z+cc
# ttkCAh3TOE7fsK1LHyNSI/MmiephiTHt5AsvAVYEk36mWHHLcktHZCB9okyrhV70
# Hr//XBKg1SQo0y3Y/rPOU7C5dx87XckhjY9QKZCLmdey+x2Zex/63oCXK0XX25P4
# Kt4VhgZ0MANfykyIx4wti4lVPiSHXvwZhbFIZQ+UCZkImTXVQ85YB4xk8w8c5nGM
# EX48Lf5k34jS3bj0DGJFU+n3gS/ZsuvJrU2fjw98lI06AJd+UO6782GJHEk7RqPh
# EXviwtLq6KWWqlIoKr2YuCOS8qHO0gv8rVHuCPvm/xMifKGY3oLXY3bSxXyY/ew=
# SIG # End signature block
