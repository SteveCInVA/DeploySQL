function Select-DbaBackupInformation {
    <#
    .SYNOPSIS
        Select a subset of backups from a dbatools backup history object

    .DESCRIPTION
        Select-DbaBackupInformation filters out a subset of backups from the dbatools backup history object with parameters supplied.

    .PARAMETER BackupHistory
        A dbatools.BackupHistory object containing backup history records

    .PARAMETER RestoreTime
        The point in time you want to restore to

    .PARAMETER IgnoreLogs
        This switch will cause Log Backups to be ignored. So will restore to the last Full or Diff backup only

    .PARAMETER IgnoreDiffs
        This switch will cause Differential backups to be ignored. Unless IgnoreLogs is specified, restore to point in time will still occur, just using all available log backups

    .PARAMETER DatabaseName
        A string array of Database Names that you want to filter to

    .PARAMETER ServerName
        A string array of Server Names that you want to filter

    .PARAMETER ContinuePoints
        The Output of Get-RestoreContinuableDatabase while provides 'Database',redo_start_lsn,'FirstRecoveryForkID' values. Used to filter backups to continue a restore on a database
        Sets IgnoreDiffs, and also filters databases to only those within the ContinuePoints object, or the ContinuePoints object AND DatabaseName if both specified

    .PARAMETER LastRestoreType
        The Output of Get-DbaDbRestoreHistory -last
        This is used to check the last type of backup to a database to see if a differential backup can be restored

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Backup, Restore
        Author:Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Select-DbaBackupInformation

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1)

        Returns all backups needed to restore all the backups in \\server1\backups$ to 1 hour ago

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -DatabaseName ProdFinance

        Returns all the backups needed to restore Database ProdFinance to an hour ago

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -IgnoreLogs

        Returns all the backups in \\server1\backups$ to restore to as close prior to 1 hour ago as can be managed with only full and differential backups

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -IgnoreDiffs

        Returns all the backups in \\server1\backups$ to restore to 1 hour ago using only Full and Diff backups.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object]$BackupHistory,
        [DateTime]$RestoreTime = (Get-Date).addmonths(1),
        [switch]$IgnoreLogs,
        [switch]$IgnoreDiffs,
        [string[]]$DatabaseName,
        [string[]]$ServerName,
        [object]$ContinuePoints,
        [object]$LastRestoreType,
        [switch]$EnableException
    )
    begin {
        $InternalHistory = @()
        $IgnoreFull = $false
        if ((Test-Bound -ParameterName ContinuePoints) -and $null -ne $ContinuePoints) {
            Write-Message -Message "ContinuePoints provided so setting up for a continue" -Level Verbose
            $IgnoreFull = $true
            $Continue = $True
            if (Test-Bound -ParameterName DatabaseName) {
                $DatabaseName = $DatabaseName | Where-Object { $_ -in ($ContinuePoints | Select-Object -Property Database).Database }

                $DroppedDatabases = $DatabaseName | Where-Object { $_ -notin ($ContinuePoints | Select-Object -Property Database).Database }
                if ($null -ne $DroppedDatabases) {
                    Write-Message -Message "$($DroppedDatabases.join(',')) filtered out as not in ContinuePoints" -Level Verbose
                }
            } else {
                $DatabaseName = ($ContinuePoints | Select-Object -Property Database).Database
            }
        }
    }
    process {
        $internalHistory += $BackupHistory
    }

    end {
        ForEach ($History in $InternalHistory) {
            if ("RestoreTime" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'RestoreTime' -Type NoteProperty -Value $RestoreTime
            }
        }
        if ((Test-Bound -ParameterName DatabaseName) -and '' -ne $DatabaseName) {
            Write-Message -Message "Filtering by DatabaseName" -Level Verbose
            #  $InternalHistory = $InternalHistory | Where-Object {$_.Database -in $DatabaseName}
        }

        # Check for AGs
        if (Test-Bound -ParameterName ServerName) {
            if (($InternalHistory | Where-Object { $_.AvailabilityGroupName -ne '' }).count -ne 0) {
                Write-Message -Level Verbose -Message 'Dealing with Availabilitygroups'
                $InternalHistory = $InternalHistory | Where-Object { $_.AvailabilityGroupName -in $servername }
            } else {
                Write-Message -Message "Filtering by ServerName" -Level Verbose
                $InternalHistory = $InternalHistory | Where-Object { $_.InstanceName -in $servername }
            }
        }

        $Databases = ($InternalHistory | Select-Object -Property Database -unique).Database
        if ($continue -and $Databases.count -gt 1 -and $DatabaseName.count -gt 1) {
            Stop-Function -Message "Cannot perform continuing restores on multiple databases with renames, exiting"
            return
        }


        ForEach ($Database in $Databases) {
            #Cope with restores renaming the db
            # $database = the name of database in the backups being scanned
            # $databasefilter = the name of the database the backups are being restore to/against
            if ($null -ne $DatabaseName) {
                $databasefilter = $DatabaseName
            } else {
                $databasefilter = $database
            }

            if ($true -eq $Continue) {
                #Test if Database is in a continuing state and the LSN to continue from:
                if ($Databasefilter -in ($ContinuePoints | Select-Object -Property Database).Database) {
                    Write-Message -Message "$Database in ContinuePoints, will attmept to continue" -Level verbose
                    $IgnoreFull = $True
                    #Check what the last backup restored was
                    if (($LastRestoreType | Where-Object { $_.Database -eq $Databasefilter }).RestoreType -eq 'log') {
                        #log Backup last restored, so diffs cannot be used
                        $IgnoreDiffs = $true
                    } else {
                        #Last restore was a diff or full, so can restore diffs or logs
                        $IgnoreDiffs = $false
                    }
                } else {
                    Write-Message -Message "$Database not in ContinuePoints, will attmept normal restore" -Level Warning
                }
            }

            $dbhistory = @()
            $DatabaseHistory = $internalhistory | Where-Object { $_.Database -eq $Database }
            #For a standard restore, work out the full backup
            if ($false -eq $IgnoreFull) {
                $Full = $DatabaseHistory | Where-Object { $_.Type -in ('Full', 'Database') -and $_.End -le $RestoreTime } | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
                if ($full.Fullname) {
                    $full.Fullname = ($DatabaseHistory | Where-Object { $_.Type -in ('Full', 'Database') -and $_.BackupSetID -eq $Full.BackupSetID }).Fullname
                } else {
                    Stop-Function -Message "Fullname property not found. This could mean that a full backup could not be found or the command must be re-run with the -Continue switch."
                    return
                }
                $dbHistory += $full
            } elseif ($true -eq $IgnoreFull -and $false -eq $IgnoreDiffs) {
                #Fake the Full backup
                Write-Message -Message "Continuing, so setting a fake full backup from the existing database"
                $Full = [PsCustomObject]@{
                    CheckpointLSN = ($ContinuePoints | Where-Object { $_.Database -eq $DatabaseFilter }).differential_base_lsn
                }
            }

            if ($false -eq $IgnoreDiffs) {
                Write-Message -Message "processing diffs" -Level Verbose
                $Diff = $DatabaseHistory | Where-Object { $_.Type -in ('Differential', 'Database Differential') -and $_.End -le $RestoreTime -and $_.DatabaseBackupLSN -eq $Full.CheckpointLSN } | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
                if ($null -ne $Diff) {
                    if ($Diff.FullName) {
                        $Diff.FullName = ($DatabaseHistory | Where-Object { $_.Type -in ('Differential', 'Database Differential') -and $_.BackupSetID -eq $diff.BackupSetID }).Fullname
                    } else {
                        Stop-Function -Message "Fullname property not found. This could mean that a full backup could not be found or the command must be re-run with the -Continue switch."
                        return
                    }
                    $dbhistory += $Diff
                }
            }

            #Sort out the LSN for the log restores
            if ($null -ne ($dbHistory | Sort-Object -Property LastLsn -Descending | Select-Object -First 1).lastLsn) {
                #We have history so use this
                [bigint]$LogBaseLsn = ($dbHistory | Sort-Object -Property LastLsn -Descending | Select-Object -First 1).lastLsn.ToString()
                $FirstRecoveryForkID = $Full.FirstRecoveryForkID
                Write-Message -Level Verbose -Message "Found LogBaseLsn: $LogBaseLsn and FirstRecoveryForkID: $FirstRecoveryForkID"
            } else {
                Write-Message -Message "No full or diff, so attempting to pull from Continue informmation" -Level Verbose
                try {
                    [bigint]$LogBaseLsn = ($ContinuePoints | Where-Object { $_.Database -eq $DatabaseFilter }).redo_start_lsn
                    $FirstRecoveryForkID = ($ContinuePoints | Where-Object { $_.Database -eq $DatabaseFilter }).FirstRecoveryForkID
                    Write-Message -Level Verbose -Message "Found LogBaseLsn: $LogBaseLsn and FirstRecoveryForkID: $FirstRecoveryForkID from Continue information"
                } catch {
                    Stop-Function -Message "Failed to find LSN or RecoveryForkID for $DatabaseFilter" -Category InvalidOperation -Target $DatabaseFilter
                }
            }

            if ($false -eq $IgnoreLogs) {
                $FilteredLogs = $DatabaseHistory | Where-Object { $_.Type -in ('Log', 'Transaction Log') -and $_.Start -lt $RestoreTime -and $_.LastLSN -ge $LogBaseLsn -and $_.FirstLSN -ne $_.LastLSN } | Sort-Object -Property LastLsn, FirstLsn
                $GroupedLogs = $FilteredLogs | Group-Object -Property BackupSetID
                ForEach ($Group in $GroupedLogs) {
                    $Log = $Group.group[0]
                    $Log.FullName = $Group.group.fullname
                    $dbhistory += $Log
                }
                # Get Last T-log

                $lastLog = $DatabaseHistory | Where-Object { $_.Type -in ('Log', 'Transaction Log') -and $_.End -ge $RestoreTime -and $_.DatabaseBackupLSN -ge $Full.CheckpointLSN } | Sort-Object -Property LastLsn, FirstLsn | Select-Object -First 1
                if ($null -ne $lastlog) {
                    $lastLog.FullName = ($DatabaseHistory | Where-Object { $_.BackupSetID -eq $lastLog.BackupSetID }).Fullname
                }
                $dbHistory += $lastLog
            }
            $dbhistory
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUnVD166KFQHIoRtt5LByaPQMp
# SX6gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFDhLhqbg756zHXDKZsTKiZkcsgu7MA0GCSqGSIb3DQEBAQUABIIBAIUrnUMd
# dCWZV98y1ojl4PabAiSUVhC2ByY0AwxWB+czeBNNfdWkCNJ9K1wNidnimEaCGvAK
# 1kJfsAfdno6kg29N8N7QCZwy/LoApz8F3gMO5Y6QSD7tnXH//97whq0+01ug1HbO
# I2RA6L3QXnDQpR30ItiD1sTKJYM84tbOGODznI3oIsPncu2qppne/SHp8MWpUOZX
# BMKo4iqZ90LMUBDgKdN8cPSVrVhz0TOrp0KaFESBZ8n6zyVTu/gBVY+m1tj81sY+
# snt25HTHOoQdszZ23dzsEQhL8ZXQj5uF6ctgapx7G1vO21ee3rjPvy/JhJ+DaqUj
# dIAVj8HimEGO9vChggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAwNlowLwYJKoZIhvcNAQkEMSIEIKWmLy9DzQUSyXyHr+vYp0o4SWrb
# SeJoZ7KRrf5QKql7MA0GCSqGSIb3DQEBAQUABIIBABQI/7N0dzi6hedvZxN1UEo3
# OptPUNZI45E7S9m2NveOkpOGEKE0EhydllKIXngSQmtUcAdW6S4ocENsDMhcXkcq
# +ByvtUgq8qCShdT5vSl8YbN0BN1i5d33GfIVZbJhIY48Fh7g6D7xW1mQqk95WLOA
# Ci7s8rOQfZO1yHY0UPARnsd1iCTUCX6xcssCu3rMueJeAfc5o9GiwN2oC28i5KoO
# rNVuNq0m9gNmXnMCDcNc9u9FW7DEP5GgXk2vqApCsWFdUFVqvEfwq95zHdzvu/i9
# f1RMhOZBTz1H+5CwVcCUf/by1G3ol4Mdz1U6tk52etJnQsOl1cZejr+F6DIkbI0=
# SIG # End signature block
