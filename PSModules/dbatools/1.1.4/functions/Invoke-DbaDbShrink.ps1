function Invoke-DbaDbShrink {
    <#
    .SYNOPSIS
        Shrinks all files in a database. This is a command that should rarely be used.

        - Shrinks can cause severe index fragmentation (to the tune of 99%)
        - Shrinks can cause massive growth in the database's transaction log
        - Shrinks can require a lot of time and system resources to perform data movement

    .DESCRIPTION
        Shrinks all files in a database. Databases should be shrunk only when completely necessary.

        Many awesome SQL people have written about why you should not shrink your data files. Paul Randal and Kalen Delaney wrote great posts about this topic:

        http://www.sqlskills.com/blogs/paul/why-you-should-not-shrink-your-data-files
        https://www.itprotoday.com/sql-server/shrinking-data-files

        However, there are some cases where a database will need to be shrunk. In the event that you must shrink your database:

        1. Ensure you have plenty of space for your T-Log to grow
        2. Understand that shrinks require a lot of CPU and disk resources
        3. Consider running DBCC INDEXDEFRAG or ALTER INDEX ... REORGANIZE after the shrink is complete.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to the default instance on localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server.

    .PARAMETER AllUserDatabases
        Run command against all user databases.

    .PARAMETER PercentFreeSpace
        Specifies how much free space to leave, defaults to 0.

    .PARAMETER ShrinkMethod
        Specifies the method that is used to shrink the database
        Default
        Data in pages located at the end of a file is moved to pages earlier in the file. Files are truncated to reflect allocated space.
        EmptyFile
        Migrates all of the data from the referenced file to other files in the same filegroup. (DataFile and LogFile objects only).
        NoTruncate
        Data in pages located at the end of a file is moved to pages earlier in the file.
        TruncateOnly
        Data distribution is not affected. Files are truncated to reflect allocated space, recovering free space at the end of any file.

    .PARAMETER StatementTimeout
        Timeout in minutes. Defaults to infinity (shrinks can take a while).

    .PARAMETER LogsOnly
        Deprecated. Use FileType instead.

    .PARAMETER FileType
        Specifies the files types that will be shrunk
        All - All Data and Log files are shrunk, using database shrink (Default)
        Data - Just the Data files are shrunk using file shrink
        Log - Just the Log files are shrunk using file shrink

    .PARAMETER StepSize
        Measured in bits - but no worries! PowerShell has a very cool way of formatting bits. Just specify something like: 1MB or 10GB. See the examples for more information.

        If specified, this will chunk a larger shrink operation into multiple smaller shrinks.
        If shrinking a file by a large amount there are benefits of doing multiple smaller chunks.

    .PARAMETER ExcludeIndexStats
        Exclude statistics about fragmentation.

    .PARAMETER ExcludeUpdateUsage
        Exclude DBCC UPDATE USAGE for database.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run.

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Shrink database" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Shrink, Database
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbShrink

    .EXAMPLE
        PS C:\> Invoke-DbaDbShrink -SqlInstance sql2016 -Database Northwind,pubs,Adventureworks2014

        Shrinks Northwind, pubs and Adventureworks2014 to have as little free space as possible.

    .EXAMPLE
        PS C:\> Invoke-DbaDbShrink -SqlInstance sql2014 -Database AdventureWorks2014 -PercentFreeSpace 50

        Shrinks AdventureWorks2014 to have 50% free space. So let's say AdventureWorks2014 was 1GB and it's using 100MB space. The database free space would be reduced to 50MB.

    .EXAMPLE
        PS C:\> Invoke-DbaDbShrink -SqlInstance sql2014 -Database AdventureWorks2014 -PercentFreeSpace 50 -FileType Data -StepSize 25MB

        Shrinks AdventureWorks2014 to have 50% free space, runs shrinks in 25MB chunks for improved performance.

    .EXAMPLE
        PS C:\> Invoke-DbaDbShrink -SqlInstance sql2012 -AllUserDatabases

        Shrinks all user databases on SQL2012 (not ideal for production)

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [ValidateRange(0, 99)]
        [int]$PercentFreeSpace = 0,
        [ValidateSet('Default', 'EmptyFile', 'NoTruncate', 'TruncateOnly')]
        [string]$ShrinkMethod = "Default",
        [ValidateSet('All', 'Data', 'Log')]
        [string]$FileType = "All",
        [int64]$StepSize,
        [int]$StatementTimeout = 0,
        [switch]$ExcludeIndexStats,
        [switch]$ExcludeUpdateUsage,
        [switch]$EnableException
    )

    begin {
        if (-not $Database -and -not $ExcludeDatabase -and -not $AllUserDatabases) {
            Stop-Function -Message "You must specify databases to execute against using either -Database, -Exclude or -AllUserDatabases"
            return
        }

        if ((Test-Bound -ParameterName StepSize) -and $StepSize -lt 1024) {
            Stop-Function -Message "StepSize is measured in bits. Did you mean $StepSize bits? If so, please use 1024 or above. If not, then use the PowerShell bit notation like $($StepSize)MB or $($StepSize)GB"
            return
        }

        if ($StepSize) {
            $stepSizeKB = ([dbasize]($StepSize)).Kilobyte
        }
        $StatementTimeoutSeconds = $StatementTimeout * 60

        $sql = "SELECT
                  avg(avg_fragmentation_in_percent) as [avg_fragmentation_in_percent]
                , max(avg_fragmentation_in_percent) as [max_fragmentation_in_percent]
                FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
                WHERE indexstats.avg_fragmentation_in_percent > 0 AND indexstats.page_count > 100
                GROUP BY indexstats.database_id"
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $server.ConnectionContext.StatementTimeout = $StatementTimeoutSeconds
            Write-Message -Level Verbose -Message "Connection timeout set to $StatementTimeout"

            $dbs = $server.Databases | Where-Object { $_.IsAccessible }

            if ($AllUserDatabases) {
                $dbs = $dbs | Where-Object { $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {

                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsDatabaseSnapshot) {
                    Write-Message -Level Warning -Message "The database $db on server $instance is a snapshot and cannot be shrunk. Skipping database."
                    continue
                }

                $files = @()
                if ($FileType -in ('Log', 'All')) {
                    $files += $db.LogFiles
                }
                if ($FileType -in ('Data', 'All')) {
                    $files += $db.FileGroups.Files
                }

                foreach ($file in $files) {
                    [dbasize]$startingSize = $file.Size
                    [dbasize]$spaceUsed = $file.UsedSpace
                    [dbasize]$spaceAvailable = ($file.Size - $file.UsedSpace)
                    [dbasize]$desiredSpaceAvailable = [math]::ceiling((($PercentFreeSpace / 100)) * $spaceUsed)
                    [dbasize]$desiredFileSize = $spaceUsed + $desiredSpaceAvailable

                    Write-Message -Level Verbose -Message "File: $($file.Name)"
                    Write-Message -Level Verbose -Message "Initial Size: $($startingSize)"
                    Write-Message -Level Verbose -Message "Space Used: $($spaceUsed)"
                    Write-Message -Level Verbose -Message "Initial Freespace: $($spaceAvailable)"
                    Write-Message -Level Verbose -Message "Target Freespace: $($desiredSpaceAvailable)"
                    Write-Message -Level Verbose -Message "Target FileSize: $($desiredFileSize)"

                    if ($spaceAvailable -le $desiredSpaceAvailable) {
                        Write-Message -Level Warning -Message "File size of ($startingSize) is less than or equal to the desired outcome ($desiredFileSize) for $($file.Name)"
                    } else {
                        if ($Pscmdlet.ShouldProcess("$db on $instance", "Shrinking from $($startingSize) to $($desiredFileSize)")) {
                            if ($server.VersionMajor -gt 8 -and $ExcludeIndexStats -eq $false) {
                                Write-Message -Level Verbose -Message "Getting starting average fragmentation"
                                $dataRow = $server.Query($sql, $db.name)
                                $startingFrag = $dataRow.avg_fragmentation_in_percent
                                $startingTopFrag = $dataRow.max_fragmentation_in_percent
                            } else {
                                $startingTopFrag = $startingFrag = $null
                            }

                            $start = Get-Date
                            try {
                                Write-Message -Level Verbose -Message "Beginning shrink of files"

                                [dbasize]$shrinkGap = ($startingSize - $desiredFileSize)
                                Write-Message -Level Verbose -Message "ShrinkGap: $($shrinkGap)"
                                Write-Message -Level Verbose -Message "Step Size: $($stepSizeKB)"

                                if ($stepSizeKB -and ($shrinkGap -ge $stepSizeKB)) {
                                    for ($i = 1; $i -le (($shrinkGap) / $stepSizeKB); $i++) {
                                        Write-Message -Level Verbose -Message "Step: $i / $((($shrinkGap) / $stepSizeKB))"
                                        [dbasize]$shrinkSize = $startingSize - ($stepSizeKB * $i)
                                        if ($shrinkSize -lt $desiredFileSize) {
                                            $shrinkSize = $desiredFileSize
                                        }
                                        Write-Message -Level Verbose -Message ("Shrinking {0} to {1}" -f $file.Name, $shrinkSize)
                                        $file.Shrink(($shrinkSize / 1024), $ShrinkMethod)
                                        $file.Refresh()

                                        if ($startingSize -eq $file.Size) {
                                            Write-Message -Level Verbose -Message ("Unable to shrink further")
                                            break
                                        }
                                    }
                                } else {
                                    $file.Shrink(($desiredFileSize / 1024), $ShrinkMethod)
                                    $file.Refresh()
                                }
                                $success = $true
                            } catch {
                                $success = $false
                                Stop-Function -message "Failure" -EnableException $EnableException -ErrorRecord $_ -Continue
                                continue
                            }
                            $end = Get-Date
                            [dbasize]$finalFileSize = $file.Size
                            [dbasize]$finalSpaceAvailable = ($file.Size - $file.UsedSpace)
                            Write-Message -Level Verbose -Message "Final file size: $($finalFileSize)"
                            Write-Message -Level Verbose -Message "Final file space available: $($finalSpaceAvailable)"

                            if ($server.VersionMajor -gt 8 -and $ExcludeIndexStats -eq $false -and $success -and $FileType -ne 'Log') {
                                Write-Message -Level Verbose -Message "Getting ending average fragmentation"
                                $dataRow = $server.Query($sql, $db.name)
                                $endingDefrag = $dataRow.avg_fragmentation_in_percent
                                $endingTopDefrag = $dataRow.max_fragmentation_in_percent
                            } else {
                                $endingTopDefrag = $endingDefrag = $null
                            }

                            $timSpan = New-TimeSpan -Start $start -End $end
                            $ts = [TimeSpan]::fromseconds($timSpan.TotalSeconds)
                            $elapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                            $object = [PSCustomObject]@{
                                ComputerName                = $server.ComputerName
                                InstanceName                = $server.ServiceName
                                SqlInstance                 = $server.DomainInstanceName
                                Database                    = $db.name
                                File                        = $file.name
                                Start                       = $start
                                End                         = $end
                                Elapsed                     = $elapsed
                                Success                     = $success
                                InitialSize                 = ($startingSize * 1024)
                                InitialUsed                 = ($spaceUsed * 1024)
                                InitialAvailable            = ($spaceAvailable * 1024)
                                TargetAvailable             = ($desiredSpaceAvailable * 1024)
                                FinalAvailable              = ($finalSpaceAvailable * 1024)
                                FinalSize                   = ($finalFileSize * 1024)
                                InitialAverageFragmentation = [math]::Round($startingFrag, 1)
                                FinalAverageFragmentation   = [math]::Round($endingDefrag, 1)
                                InitialTopFragmentation     = [math]::Round($startingTopFrag, 1)
                                FinalTopFragmentation       = [math]::Round($endingTopDefrag, 1)
                                Notes                       = "Database shrinks can cause massive index fragmentation and negatively impact performance. You should now run DBCC INDEXDEFRAG or ALTER INDEX ... REORGANIZE"
                            }
                            if ($ExcludeIndexStats) {
                                Select-DefaultView -InputObject $object -ExcludeProperty InitialAverageFragmentation, FinalAverageFragmentation, InitialTopFragmentation, FinalTopFragmentation
                            } else {
                                $object
                            }
                        }
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUiDfS3tQYj9tYQa2qAo5gxrXA
# /a+gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFMJMBbG34/6aIM/X2Gz6WkHh96JyMA0GCSqGSIb3DQEBAQUABIIBAGbi0EEb
# VwAxzNzGqD7dmbqe4PhKFagniscCoeEYHUa/wl3rDswTwClC3uViiMHTETCTFAAg
# uEoInCssjjE5Q4bwzNpljoYlYDlkkLOc4cTWL2F/HW7MQLveBUAF+fW49GnjONI1
# Z7MLZS507Chl5rMZ5Hqo2lcFivSzuGXBRB0T5xPgMHa7HM7dU4diwVU2hIPX3z2N
# TrbcMbSfpc17b1sKwRiAlU4VtWZftZQQ8c4OTE+Nef+7lTLNCCe489TTIHIo5Mk1
# AnRXYB5ZjCX8vQ/IH79TknjktxZ5l86EbbUx9Vbke4yInTR4LQXFqLZ9MAAMH7yA
# 2lktkJb4I3MzxTShggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1MVowLwYJKoZIhvcNAQkEMSIEIOmLe5qqQcQaKmWSyoEqpZiEeOwv
# 40vgQSlQiAt1RkDqMA0GCSqGSIb3DQEBAQUABIIBAGIsLsRTcm9xb5EM4G2zvIiG
# YeSVTVwIRxSdrvRekWBklnX/jOCX0ZQWZNZaMBgLrPZH8y0mqGJQmiZikOULQFgr
# W8+j5ujNegl+ZvqY853ZlcU0CKblzvsztbtcfwbog+Qd1RbYbj6PuAw5qOxgaAuc
# qZ++WgVpK1c7vYSFPeWYHTDQbFtn4NCrSyJYoZJQ683yt0QjJibMXhKeWezf4Z5+
# RMhC1AE75GWuFJXjM2uGsrqo0189NXgc2lOH4kmogNrovBFvPyZc0NfMg/aFNAGB
# xM4h/m4UU686cmkfshH3MyC9nTCenCEfi1qq4FPiVLf1Lx11A1WHVQHtvB5E2rU=
# SIG # End signature block
