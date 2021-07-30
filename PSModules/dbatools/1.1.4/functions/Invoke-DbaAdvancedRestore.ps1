function Invoke-DbaAdvancedRestore {
    <#
    .SYNOPSIS
        Allows the restore of modified BackupHistory Objects
        For 90% of users Restore-DbaDatabase should be your point of access to this function. The other 10% use it at their own risk

    .DESCRIPTION
        This is the final piece in the Restore-DbaDatabase Stack. Usually a BackupHistory object will arrive here from `Restore-DbaDatabase` via the following pipeline:
        `Get-DbaBackupInformation  | Select-DbaBackupInformation | Format-DbaBackupInformation | Test-DbaBackupInformation | Invoke-DbaAdvancedRestore`

        We have exposed these functions publicly to allow advanced users to perform operations that we don't support, or won't add as they would make things too complex for the majority of our users

        For example if you wanted to do some very complex redirection during a migration, then doing the rewrite of destinations may be better done with your own custom scripts rather than via `Format-DbaBackupInformation`

        We would recommend ALWAYS pushing your input through `Test-DbaBackupInformation` just to make sure that it makes sense to us.

    .PARAMETER BackupHistory
        The BackupHistory object to be restored.
        Can be passed in on the pipeline

    .PARAMETER SqlInstance
        The SqlInstance to which the backups should be restored

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER OutputScriptOnly
        If set, the restore will not be performed, but the T-SQL scripts to perform it will be returned

    .PARAMETER VerifyOnly
        If set, performs a Verify of the backups rather than a full restore

    .PARAMETER RestoreTime
        Point in Time to which the database should be restored.

        This should be the same value or earlier, as used in the previous pipeline stages

    .PARAMETER StandbyDirectory
        A folder path where a standby file should be created to put the recovered databases in a standby mode

    .PARAMETER NoRecovery
        Leave the database in a restoring state so that further restore may be made

    .PARAMETER MaxTransferSize
        Parameter to set the unit of transfer. Values must be a multiple by 64kb

    .PARAMETER Blocksize
        Specifies the block size to use. Must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb or 64kb
        Can be specified in bytes
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER Continue
        Indicates that the restore is continuing a restore, so target database must be in Recovering or Standby states
        When specified, WithReplace will be set to true

    .PARAMETER AzureCredential
        AzureCredential required to connect to blob storage holding the backups

    .PARAMETER WithReplace
        Indicated that if the database already exists it should be replaced

    .PARAMETER KeepReplication
        Indicates whether replication configuration should be restored as part of the database restore operation

    .PARAMETER KeepCDC
        Indicates whether CDC information should be restored as part of the database

    .PARAMETER PageRestore
        The output from Get-DbaSuspect page containing the suspect pages to be restored.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER ExecuteAs
        If set, this will cause the database(s) to be restored (and therefore owned) as the SA user

    .PARAMETER StopMark
        Mark in the transaction log to stop the restore at

    .PARAMETER StopBefore
        Switch to indicate the restore should stop before StopMark

    .PARAMETER StopAfterDate
        By default the restore will stop at the first occurence of StopMark found in the chain, passing a datetime where will cause it to stop the first StopMark atfer that datetime

    .PARAMETER EnableException
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.

    .NOTES
        Tags: Restore, Backup
        Author: Stuart Moore (@napalmgram - http://stuart-moore.com)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaAdvancedRestore

    .EXAMPLE
        PS C:\> $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance

        Will restore all the backups in the BackupHistory object according to the transformations it contains

    .EXAMPLE
        PS C:\> $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance -OutputScriptOnly
        PS C:\> $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance

        First generates just the T-SQL restore scripts so they can be sanity checked, and then if they are good perform the full restore.
        By reusing the BackupHistory object there is no need to rescan all the backup files again

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "AzureCredential", Justification = "For Parameter AzureCredential")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Object[]]$BackupHistory,
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$OutputScriptOnly,
        [switch]$VerifyOnly,
        [datetime]$RestoreTime = (Get-Date).AddDays(2),
        [string]$StandbyDirectory,
        [switch]$NoRecovery,
        [int]$MaxTransferSize,
        [int]$BlockSize,
        [int]$BufferCount,
        [switch]$Continue,
        [string]$AzureCredential,
        [switch]$WithReplace,
        [switch]$KeepReplication,
        [switch]$KeepCDC,
        [object[]]$PageRestore,
        [string]$ExecuteAs,
        [switch]$StopBefore,
        [string]$StopMark,
        [datetime]$StopAfterDate,
        [switch]$EnableException
    )
    begin {
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
        if ($KeepCDC -and ($NoRecovery -or ('' -ne $StandbyDirectory))) {
            Stop-Function -Category InvalidArgument -Message "KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work"
            return
        }

        if ($null -ne $PageRestore) {
            Write-Message -Message "Doing Page Recovery" -Level Verbose
            $tmpPages = @()
            foreach ($Page in $PageRestore) {
                $tmpPages += "$($Page.FileId):$($Page.PageID)"
            }
            $NoRecovery = $True
            $Pages = $tmpPages -join ','
        }
        $internalHistory = @()
    }
    process {
        foreach ($bh in $BackupHistory) {
            $internalHistory += $bh
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        if ($Continue -eq $True) {
            $WithReplace = $True
        }
        $databases = $internalHistory.Database | Select-Object -Unique
        foreach ($database in $databases) {
            $databaseRestoreStartTime = Get-Date
            if ($database -in $server.Databases.Name) {
                if (-not $OutputScriptOnly -and -not $VerifyOnly -and $server.DatabaseEngineEdition -ne "SqlManagedInstance") {
                    if ($Pscmdlet.ShouldProcess("Killing processes in $database on $SqlInstance as it exists and WithReplace specified  `n", "Cannot proceed if processes exist, ", "Database Exists and WithReplace specified, need to kill processes to restore")) {
                        try {
                            Write-Message -Level Verbose -Message "Killing processes on $database"
                            $null = Stop-DbaProcess -SqlInstance $server -Database $database -WarningAction Silentlycontinue
                            $null = $server.Query("Alter database $database set offline with rollback immediate; alter database $database set restricted_user; Alter database $database set online with rollback immediate", 'master')
                            $server.ConnectionContext.Connect()
                        } catch {
                            Write-Message -Level Verbose -Message "No processes to kill in $database"
                        }
                    }
                } elseif (-not $OutputScriptOnly -and -not $VerifyOnly -and $server.DatabaseEngineEdition -eq "SqlManagedInstance") {
                    if ($Pscmdlet.ShouldProcess("Dropping $database on $SqlInstance as it exists and WithReplace specified  `n", "Cannot proceed if database exist, ", "Database Exists and WithReplace specified, need to drop database to restore")) {
                        try {
                            Write-Message -Level Verbose "$SqlInstance is a Managed instance so dropping database was WithReplace not supported"
                            $null = Stop-DbaProcess -SqlInstance $server -Database $database -WarningAction Silentlycontinue
                            $null = Remove-DbaDatabase -SqlInstance $server -Database $database -Confirm:$false
                            $server.ConnectionContext.Connect()
                        } catch {
                            Write-Message -Level Verbose -Message "No processes to kill in $database"
                        }
                    }

                } elseif (-not $WithReplace -and (-not $VerifyOnly)) {
                    Write-Message -Level verbose -Message "$database exists and WithReplace not specified, stopping"
                    continue
                }
            }
            Write-Message -Message "WithReplace  = $WithReplace" -Level Debug
            $backups = @($internalHistory | Where-Object { $_.Database -eq $database } | Sort-Object -Property Type, FirstLsn)
            $BackupCnt = 1

            foreach ($backup in $backups) {
                $fileRestoreStartTime = Get-Date
                $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
                if (($backup -ne $backups[-1]) -or $true -eq $NoRecovery) {
                    $restore.NoRecovery = $True
                } elseif ($backup -eq $backups[-1] -and '' -ne $StandbyDirectory) {
                    $restore.StandbyFile = $StandByDirectory + "\" + $database + (Get-Date -Format yyyyMMddHHmmss) + ".bak"
                    Write-Message -Level Verbose -Message "Setting standby on last file $($restore.StandbyFile)"
                } else {
                    $restore.NoRecovery = $False
                }
                if (-not [string]::IsNullOrEmpty($StopMark)) {
                    if ($StopBefore -eq $True) {
                        $restore.StopBeforeMarkName = $StopMark
                        if ($null -ne $StopAfterDate) {
                            $restore.StopBeforeMarkAfterDate = $StopAfterDate
                        }
                    } else {
                        $restore.StopAtMarkName = $StopMark
                        if ($null -ne $StopAfterDate) {
                            $restore.StopAtMarkAfterDate = $StopAfterDate
                        }
                    }
                } elseif ($RestoreTime -gt (Get-Date) -or $backup.RestoreTime -gt (Get-Date) -or $backup.RecoveryModel -eq 'Simple') {
                    $restore.ToPointInTime = $null
                } else {
                    if ($RestoreTime -ne $backup.RestoreTime) {
                        $restore.ToPointInTime = $backup.RestoreTime.ToString("yyyy-MM-ddTHH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        $restore.ToPointInTime = $RestoreTime.ToString("yyyy-MM-ddTHH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }

                $restore.Database = $database
                if ($server.DatabaseEngineEdition -ne "SqlManagedInstance") {
                    $restore.ReplaceDatabase = $WithReplace
                }
                if ($MaxTransferSize) {
                    $restore.MaxTransferSize = $MaxTransferSize
                }
                if ($BufferCount) {
                    $restore.BufferCount = $BufferCount
                }
                if ($BlockSize) {
                    $restore.Blocksize = $BlockSize
                }
                if ($KeepReplication) {
                    $restore.KeepReplication = $KeepReplication
                }
                if ($true -ne $Continue -and ($null -eq $Pages)) {
                    foreach ($file in $backup.FileList) {
                        $moveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
                        $moveFile.LogicalFileName = $file.LogicalName
                        $moveFile.PhysicalFileName = $file.PhysicalName
                        $null = $restore.RelocateFiles.Add($moveFile)
                    }
                }
                $action = switch ($backup.Type) {
                    '1' { 'Database' }
                    '2' { 'Log' }
                    '5' { 'Database' }
                    'Transaction Log' { 'Log' }
                    Default { 'Database' }
                }

                Write-Message -Level Debug -Message "restore action = $action"
                $restore.Action = $action
                foreach ($file in $backup.FullName) {
                    Write-Message -Message "Adding device $file" -Level Debug
                    $device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
                    $device.Name = $file
                    if ($file.StartsWith("http")) {
                        $device.devicetype = "URL"
                    } else {
                        $device.devicetype = "File"
                    }

                    if ($AzureCredential) {
                        $restore.CredentialName = $AzureCredential
                    }

                    $restore.FileNumber = $backup.Position
                    $restore.Devices.Add($device)
                }
                Write-Message -Level Verbose -Message "Performing restore action"
                if ($Pscmdlet.ShouldProcess($SqlInstance, "Restoring $database to $SqlInstance based on these files: $($backup.FullName -join ', ')")) {
                    try {
                        $restoreComplete = $true
                        if ($KeepCDC -and $restore.NoRecovery -eq $false) {
                            $script = $restore.Script($server)
                            if ($script -like '*WITH*') {
                                $script = $script.TrimEnd() + ' , KEEP_CDC'
                            } else {
                                $script = $script.TrimEnd() + ' WITH KEEP_CDC'
                            }
                            if ($true -ne $OutputScriptOnly) {
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            }
                        } elseif ($null -ne $Pages -and $action -eq 'Database') {
                            $script = $restore.Script($server)
                            $script = $script -replace "] FROM", "] PAGE='$pages' FROM"
                            if ($true -ne $OutputScriptOnly) {
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            }
                        } elseif ($OutputScriptOnly) {
                            $script = $restore.Script($server)
                            if ($ExecuteAs -ne '' -and $BackupCnt -eq 1) {
                                $script = "EXECUTE AS LOGIN='$ExecuteAs'; " + $script
                            }
                        } elseif ($VerifyOnly) {
                            Write-Message -Message "VerifyOnly restore" -Level Verbose
                            Write-Progress -id 1 -activity "Verifying $database backup file on $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                            $Verify = $restore.SqlVerify($server)
                            Write-Progress -id 1 -activity "Verifying $database backup file on $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            if ($verify -eq $true) {
                                Write-Message -Message "VerifyOnly restore Succeeded" -Level Verbose
                                return "Verify successful"
                            } else {
                                Write-Message -Message "VerifyOnly restore Failed" -Level Verbose
                                return "Verify failed"
                            }
                        } else {
                            $outerProgress = $BackupCnt / $Backups.Count * 100
                            if ($BackupCnt -eq 1) {
                                Write-Progress -id 1 -Activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0
                            }
                            Write-Progress -id 2 -ParentId 1 -Activity "Restore $($backup.FullName -Join ',')" -percentcomplete 0
                            $script = $restore.Script($server)
                            if ($ExecuteAs -ne '' -and $BackupCnt -eq 1) {
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $script = "EXECUTE AS LOGIN='$ExecuteAs'; " + $script
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            } else {
                                $percentcomplete = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                                    Write-Progress -id 2 -ParentId 1 -Activity "Restore $($backup.FullName -Join ',')" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
                                }
                                $restore.add_PercentComplete($percentcomplete)
                                $restore.PercentCompleteNotification = 1
                                $restore.SqlRestore($server)
                                Write-Progress -id 2 -ParentId 1 -Activity "Restore $($backup.FullName -Join ',')" -Completed
                                Add-TeppCacheItem -SqlInstance $server -Type database -Name $database
                            }
                            Write-Progress -id 1 -Activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete $outerProgress -status ([System.String]::Format("Progress: {0:N2} %", $outerProgress))
                        }
                    } catch {
                        Write-Message -Level Verbose -Message "Failed, Closing Server connection"
                        $restoreComplete = $False
                        $ExitError = $_.Exception.InnerException
                        Stop-Function -Message "Failed to restore db $database, stopping" -ErrorRecord $_ -Continue
                        break
                    } finally {
                        if ($OutputScriptOnly -eq $false) {
                            $pathSep = Get-DbaPathSep -Server $server
                            $RestoreDirectory = ((Split-Path $backup.FileList.PhysicalName -Parent) | Sort-Object -Unique).Replace('\', $pathSep) -Join ','
                            [PSCustomObject]@{
                                ComputerName           = $server.ComputerName
                                InstanceName           = $server.ServiceName
                                SqlInstance            = $server.DomainInstanceName
                                Database               = $backup.Database
                                DatabaseName           = $backup.Database
                                DatabaseOwner          = $server.ConnectionContext.TrueLogin
                                Owner                  = $server.ConnectionContext.TrueLogin
                                NoRecovery             = $restore.NoRecovery
                                WithReplace            = $WithReplace
                                KeepReplication        = $KeepReplication
                                RestoreComplete        = $restoreComplete
                                BackupFilesCount       = $backup.FullName.Count
                                RestoredFilesCount     = $backup.Filelist.PhysicalName.count
                                BackupSizeMB           = if ([bool]($backup.psobject.Properties.Name -contains 'TotalSize')) { [Math]::Round(($backup | Measure-Object -Property TotalSize -Sum).Sum / $backup.FullName.Count / 1mb, 2) } else { $null }
                                CompressedBackupSizeMB = if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSize')) { [Math]::Round(($backup | Measure-Object -Property CompressedBackupSize -Sum).Sum / $backup.FullName.Count / 1mb, 2) } else { $null }
                                BackupFile             = $backup.FullName -Join ','
                                RestoredFile           = $((Split-Path $backup.FileList.PhysicalName -Leaf) | Sort-Object -Unique) -Join ','
                                RestoredFileFull       = ($backup.Filelist.PhysicalName -Join ',')
                                RestoreDirectory       = $RestoreDirectory
                                BackupSize             = if ([bool]($backup.psobject.Properties.Name -contains 'TotalSize')) { [dbasize](($backup | Measure-Object -Property TotalSize -Sum).Sum / $backup.FullName.Count) } else { $null }
                                CompressedBackupSize   = if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSize')) { [dbasize](($backup | Measure-Object -Property CompressedBackupSize -Sum).Sum / $backup.FullName.Count) } else { $null }
                                BackupStartTime        = $backup.Start
                                BackupEndTime          = $backup.End
                                RestoreTargetTime      = if ($RestoreTime -lt (Get-Date)) { $RestoreTime } else { 'Latest' }
                                Script                 = $script
                                BackupFileRaw          = ($backups.Fullname)
                                FileRestoreTime        = New-TimeSpan -Seconds ((Get-Date) - $fileRestoreStartTime).TotalSeconds
                                DatabaseRestoreTime    = New-TimeSpan -Seconds ((Get-Date) - $databaseRestoreStartTime).TotalSeconds
                                ExitError              = $ExitError
                            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, BackupFile, BackupFilesCount, BackupSize, CompressedBackupSize, Database, Owner, DatabaseRestoreTime, FileRestoreTime, NoRecovery, RestoreComplete, RestoredFile, RestoredFilesCount, Script, RestoreDirectory, WithReplace
                        } else {
                            $script
                        }
                        if ($restore.Devices.Count -gt 0) {
                            $restore.Devices.Clear()
                        }
                        Write-Message -Level Verbose -Message "Succeeded, Closing Server connection"
                        $server.ConnectionContext.Disconnect()
                    }
                }
                $BackupCnt++
            }
            Write-Progress -id 2 -Activity "Finished" -Completed
            if ($server.ConnectionContext.exists) {
                $server.ConnectionContext.Disconnect()
            }
            Write-Progress -id 1 -Activity "Finished" -Completed
        }
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU2A95prsaNkWHqcZdSOWJX8GK
# I1GgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFH2ncWSeTquEOUQnV3+d9r5eq/HyMA0GCSqGSIb3DQEBAQUABIIBAGB+vD42
# p0QziRuKUpkK1SIa0/00Jg9I2u10IQVDkCYkfBgB/XyEoz0qkJbXMfyIzGkhUIdd
# enGO53xo0JPjwwwdVjEvtL98qMYwCraZnjEUkQ2RYcZ58R/ory0ahcr7IhzGiBwv
# t1+sc4o16LfDjjwl21epiR509PpYbBbKI/OxOqV370t/TeFbVuVEynCGKbn/jdiv
# rAC+nfsiIX0L+RQOOyFGMLMEOqT764Sjm05ReJntQDykGuzoZdQ4XL5NDwQqlAux
# /84JPbsMXB7Jlb6xdBWxPcheF88y7ROrqu8eAuTnHGywHcVm4+bDdwfagZPvtsfq
# yzH20sA+F4ZL64qhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk0OVowLwYJKoZIhvcNAQkEMSIEIHrf6g/kSS5ASdI2bvF4bG/kBoc+
# NBlVovbLf1WQKgByMA0GCSqGSIb3DQEBAQUABIIBAGNP00FEpyHW4jRgAn8Dl1N/
# GXihmrA7zkIJ4FqZjg8QuQHSN4tPzW9atmnTuBOCAIvJK+ydUi5WybJ2q2Fbko7t
# dCMl4iX/+IIDEtp8o/jE95XeMxj8GZi9TWTJN08Nimal7Gw2c4irc2wKPpzdpNfU
# 27w9u+qmnP4+0Ukqsk07jcZU5hDWA0IGSBxqSUBWGw8iWt1bBYADEZTxIzivwm65
# rKyPohNAQ2uyAMphWlkywfjVcbz/BQLNQpcKon/0rkshxKL4g9tG//JunWn/O0gF
# p07s6GX/VIyTKdbjmbCj5VFsBQp+88ln+NY1ajmyj02xCPMLzJnbBAdxXxplNxE=
# SIG # End signature block
