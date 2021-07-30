function Test-DbaDiskSpeed {
    <#
    .SYNOPSIS
        Obtains I/O statistics based on the DMV sys.dm_io_virtual_file_stats:

        https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-io-virtual-file-stats-transact-sql

    .DESCRIPTION
        Obtains I/O statistics based on the DMV sys.dm_io_virtual_file_stats:

        https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-io-virtual-file-stats-transact-sql

        This command uses a query from Rich Benner
        https://github.com/RichBenner/PersonalCode/blob/master/Disk_Speed_Check.sql

        ...and also based on further adaptations referenced at https://github.com/sqlcollaborative/dbatools/issues/6551#issue-623216718

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER AggregateBy
        Specify the level of aggregation for the statistics. The available options are 'File' (the default), 'Database', and 'Disk'.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaDiskSpeed

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008, sqlserver2012

        Tests how disks are performing on sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -Database tempdb

        Tests how disks storing tempdb files on sql2008 are performing.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -AggregateBy "File" -Database tempdb

        Returns the statistics aggregated to the file level. This is the default aggregation level if the -AggregateBy param is omitted. The -Database or -ExcludeDatabase params can be used to filter for specific databases.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -AggregateBy "Database"

        Returns the statistics aggregated to the database/disk level. The -Database or -ExcludeDatabase params can be used to filter for specific databases.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -AggregateBy "Disk"

        Returns the statistics aggregated to the disk level. The -Database or -ExcludeDatabase params can be used to filter for specific databases.

    .EXAMPLE
        PS C:\> $results = @(instance1, instance2) | Test-DbaDiskSpeed

        Returns the statistics for instance1 and instance2 as part of a pipeline command

    .EXAMPLE
        PS C:\> $databases = @('master', 'model')
        $results = Test-DbaDiskSpeed -SqlInstance sql2019 -Database $databases

        Returns the statistics for more than one database specified.

    .EXAMPLE
        PS C:\> $excludedDatabases = @('master', 'model')
        $results = Test-DbaDiskSpeed -SqlInstance sql2019 -ExcludeDatabase $excludedDatabases

        Returns the statistics for databases other than the exclusions specified.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet('Database', 'Disk', 'File')]
        [string]$AggregateBy = 'File',
        [switch]$EnableException
    )

    begin {

        $sql = $null

        # Consolidating the common SQL to hopefully make the maintenance easier. The various scenarios are enabled by uncommenting specific lines at runtime.
        $selectList =
        "SELECT
            SERVERPROPERTY('MachineName')                                                                               AS ComputerName
        ,   ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')                                                       AS InstanceName
        ,   SERVERPROPERTY('ServerName')                                                                                AS SqlInstance
        --DATABASE-SELECT,  DB_NAME(a.database_id)                                                                      AS [Database]
        --FILE-ALL,   CAST(((a.size_on_disk_bytes/1024)/1024.0)/1024 AS DECIMAL(10,2))                                  AS [SizeGB]
        --FILE-WINDOWS, RIGHT(b.physical_name, CHARINDEX('\', REVERSE(b.physical_name)) -1)                             AS [FileName]
        --FILE-LINUX, RIGHT(b.physical_name, CHARINDEX('/', REVERSE(b.physical_name)) -1)                               AS [FileName]
        --FILE-ALL,   a.file_id                                                                                         AS [FileID]
        --FILE-ALL,   CASE WHEN a.file_id = 2 THEN 'Log' ELSE 'Data' END                                                AS [FileType]
        --DATABASE-OR-DISK, a.DiskLocation                                                                              AS DiskLocation
        --FILE-WINDOWS,   UPPER(SUBSTRING(b.physical_name, 1, 2))                                                       AS DiskLocation
        --FILE-LINUX, SUBSTRING(physical_name, 1, CHARINDEX('/', physical_name, CHARINDEX('/', physical_name) + 1) - 1) AS DiskLocation
        ,   a.num_of_reads                                                                                              AS [Reads]
        ,   CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END            AS [AverageReadStall]
        ,   CASE
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 10 THEN 'Very Good'
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 20 THEN 'OK'
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 50 THEN 'Slow, Needs Attention'
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END >= 50 THEN 'Serious I/O Bottleneck'
            END                                                                                                         AS [ReadPerformance]
        ,   a.num_of_writes                                                                                             AS [Writes]
        ,   CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/a.num_of_writes AS INT) END           AS [AverageWriteStall]
        ,   CASE
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 10 THEN 'Very Good'
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 20 THEN 'OK'
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 50 THEN 'Slow, Needs Attention'
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END >= 50 THEN 'Serious I/O Bottleneck'
            END                                                                                                         AS [WritePerformance]
        ,   CASE
                WHEN (a.num_of_reads = 0 AND a.num_of_writes = 0) THEN NULL
                ELSE (a.io_stall/(a.num_of_reads + a.num_of_writes))
            END                                                                                                         AS [Avg Overall Latency]
        ,   CASE
                WHEN a.num_of_reads = 0 THEN NULL
                ELSE (a.num_of_bytes_read/a.num_of_reads)
            END                                                                                                         AS [Avg Bytes/Read]
        ,   CASE
                WHEN a.num_of_writes = 0 THEN NULL
                ELSE (a.num_of_bytes_written/a.num_of_writes)
            END                                                                                                         AS [Avg Bytes/Write]
        ,   CASE
                WHEN (a.num_of_reads = 0 AND a.num_of_writes = 0) THEN NULL
                ELSE ((a.num_of_bytes_read + a.num_of_bytes_written)/(a.num_of_reads + a.num_of_writes))
            END                                                                                                         AS [Avg Bytes/Transfer]"

        if ($AggregateBy -eq 'File') {
            $sql = "$selectList
                    FROM sys.dm_io_virtual_file_stats (NULL, NULL) a
                    JOIN sys.master_files b
                        ON a.file_id = b.file_id
                        AND a.database_id = b.database_id"

        } elseif ($AggregateBy -in ('Database', 'Disk')) {
            $sql = "$selectList
                    FROM
                    (
                        SELECT
                        --WINDOWS UPPER(SUBSTRING(b.physical_name, 1, 2))                                                           AS DiskLocation
                        --LINUX SUBSTRING(physical_name, 1, CHARINDEX('/', physical_name, CHARINDEX('/', physical_name) + 1) - 1)   AS DiskLocation
                        ,   SUM(a.num_of_reads)                                                                                     AS num_of_reads
                        ,   SUM(a.io_stall_read_ms)                                                                                 AS io_stall_read_ms
                        ,   SUM(a.num_of_writes)                                                                                    AS num_of_writes
                        ,   SUM(a.io_stall_write_ms)                                                                                AS io_stall_write_ms
                        ,   SUM(a.num_of_bytes_read)                                                                                AS num_of_bytes_read
                        ,   SUM(a.num_of_bytes_written)                                                                             AS num_of_bytes_written
                        ,   SUM(a.io_stall)                                                                                         AS io_stall
                        --DATABASE-GROUPBY, a.database_id                                                                           AS database_id
                        FROM sys.dm_io_virtual_file_stats (NULL, NULL) a
                        JOIN sys.master_files b
                            ON a.file_id = b.file_id
                            AND a.database_id = b.database_id
                        GROUP BY
                            --DATABASE-GROUPBYa.database_id,
                            --WINDOWS UPPER(SUBSTRING(b.physical_name, 1, 2))
                            --LINUX SUBSTRING(physical_name, 1, CHARINDEX('/', physical_name, CHARINDEX('/', physical_name) + 1) - 1)
                    ) AS a"
        }

        if ($Database -or $ExcludeDatabase) {
            if ($Database) {
                $where = " where db_name(a.database_id) in ('$($Database -join "','")') "
            }
            if ($ExcludeDatabase) {
                $where = " where db_name(a.database_id) not in ('$($ExcludeDatabase -join "','")') "
            }
            $sql += $where
        }

        $sql += " ORDER BY (a.num_of_reads + a.num_of_writes) DESC"
    }

    process {
        foreach ($instance in $SqlInstance) {

            $sqlToRun = $sql

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9

                # At runtime uncomment the relevant pieces in the SQL
                if ($AggregateBy -eq 'File') {

                    $sqlToRun = $sqlToRun.replace("--DATABASE-SELECT", "").replace("--FILE-ALL", "")

                    if ($server.HostPlatform -eq "Linux") {
                        $sqlToRun = $sqlToRun.replace("--FILE-LINUX", "")
                    } else {
                        $sqlToRun = $sqlToRun.replace("--FILE-WINDOWS", "")
                    }

                } elseif ($AggregateBy -in ('Database', 'Disk')) {

                    $sqlToRun = $sqlToRun.replace("--DATABASE-OR-DISK", "")

                    if ($server.HostPlatform -eq "Linux") {
                        $sqlToRun = $sqlToRun.replace("--LINUX", "")
                    } else {
                        $sqlToRun = $sqlToRun.replace("--WINDOWS", "")
                    }

                    if ($AggregateBy -eq 'Database') {
                        $sqlToRun = $sqlToRun.replace("--DATABASE-SELECT", "").replace("--DATABASE-GROUPBY", "")
                    }
                }
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Debug -Message "Executing $sqlToRun"
            $server.Query("$sqlToRun")
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU6jLOkBM1GhL0QEjJluJnCOhE
# SvigghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFObjikM3c9gS+4g1x8Ul2iii1mbRMA0GCSqGSIb3DQEBAQUABIIBAAgxDdJ8
# 2fxMtahtiqOpHnSTm3BpZF1Yd6zPZxuWO2VkY/sLXv56uzltG0/f4lhhTkL84aLb
# d/qhaDPfQQv37epBVoFdcnsoSilEU8lrZMKIFKzytOsglKEG+Xe9dzKM5jGODZYe
# DpGvYWAb84ScvORmjhYMpKGLgoUbKYroaVFa+qXi3q7vVs01tU8PZxcOmNyFttYl
# 4BPQ+toF5rbiKtqwn+dTlFGuNGzwNqgJs1N/VkxBACQEglb3gjY4HrTm9XBcgqtr
# jQwIS+tkxoEXS6DFkrWcKfNr1BRpEFCnABpHsOubGA8nfO/GqiHvy+310JlZ4LIi
# 1rqurcHEw5/PbSKhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAxNVowLwYJKoZIhvcNAQkEMSIEIGBpNqQeIHyp+d2e1Pll2y80Wb3w
# CnCNjvLZJCRfS7mtMA0GCSqGSIb3DQEBAQUABIIBACt8PWXLGUevHyPW5Lx1sv1H
# QdGt9CXTDgYwmajh5PoMQzPvXT4Ogbm0QdQeeIohDeXlhqHJ/ii0sJAwAA2XyltH
# k+4BwFV62VsP9a4aPb/qXDILTb5WCDU27Xu5DrzIz/rZcsTWcY1qs+gpRgBIeqwv
# +4h/3gMDeevCGggvptsQlecpCU3j3oV1mPcKIGBT9c7B5lxo1r1hgoKqamc8uY9I
# RlSeuC5KyD9XN28NGgGQ8yERF0UziwfrucjjvwMAHFJ2TOSw33CKXFeGQ238pUAU
# SgGCrGxcV1yPJTGcGmNMd3kWzI7ORGTFRn9B8YcswU8HnXqqa0e6FOUetkPSJ4c=
# SIG # End signature block
