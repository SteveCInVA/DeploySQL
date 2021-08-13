function Get-DbaTopResourceUsage {
    <#
    .SYNOPSIS
        Returns the top 20 resource consumers for cached queries based on four different metrics: duration, frequency, IO, and CPU.

    .DESCRIPTION
        Returns the top 20 resource consumers for cached queries based on four different metrics: duration, frequency, IO, and CPU.

        This command is based off of queries provided by Michael J. Swart at http://michaeljswart.com/go/Top20

        Per Michael: "I've posted queries like this before, and others have written many other versions of this query. All these queries are based on sys.dm_exec_query_stats."

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

    .PARAMETER ExcludeSystem
        This will exclude system objects like replication procedures from being returned.

    .PARAMETER Type
        By default, all Types run but you can specify one or more of the following: Duration, Frequency, IO, or CPU

    .PARAMETER Limit
        By default, these query the Top 20 worst offenders (though more than 20 results can be returned if each of the top 20 have more than 1 subsequent result)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Query, Performance
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaTopResourceUsage

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2008, sql2012

        Return the 80 (20 x 4 types) top usage results by duration, frequency, IO, and CPU servers for servers sql2008 and sql2012

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2008 -Type Duration, Frequency -Database TestDB

        Return the highest usage by duration (top 20) and frequency (top 20) for the TestDB on sql2008

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2016 -Limit 30

        Return the highest usage by duration (top 30) and frequency (top 30) for the TestDB on sql2016

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2008, sql2012 -ExcludeSystem

        Return the 80 (20 x 4 types) top usage results by duration, frequency, IO, and CPU servers for servers sql2008 and sql2012 without any System Objects

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2016| Select-Object *

        Return all the columns plus the QueryPlan column

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet("All", "Duration", "Frequency", "IO", "CPU")]
        [string[]]$Type = "All",
        [int]$Limit = 20,
        [switch]$EnableException,
        [switch]$ExcludeSystem
    )

    begin {

        $instancecolumns = " SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, "

        if ($database) {
            $wheredb = " and coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') in ('$($database -join '', '')')"
        }

        if ($ExcludeDatabase) {
            $wherenotdb = " and coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') not in ('$($excludedatabase -join '', '')')"
        }

        if ($ExcludeSystem) {
            $whereexcludesystem = " AND coalesce(object_name(st.objectid, st.dbid), '<none>') NOT LIKE 'sp_MS%' "
        }
        $duration = ";with long_queries as
                        (
                            select top $Limit
                                query_hash,
                                sum(total_elapsed_time) elapsed_time
                            from sys.dm_exec_query_stats
                            where query_hash <> 0x0
                            group by query_hash
                            order by sum(total_elapsed_time) desc
                        )
                        select $instancecolumns
                            coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                            coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                            qs.query_hash as QueryHash,
                            qs.total_elapsed_time / 1000 as TotalElapsedTimeMs,
                            qs.execution_count as ExecutionCount,
                            cast((total_elapsed_time / 1000) / (execution_count + 0.0) as money) as AverageDurationMs,
                            lq.elapsed_time / 1000 as QueryTotalElapsedTimeMs,
                            SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                                (CASE
                                    WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                                    ELSE qs.statement_end_offset
                                    END - qs.statement_start_offset) / 2) as QueryText,
                            qp.query_plan as QueryPlan
                        from sys.dm_exec_query_stats qs
                        join long_queries lq
                            on lq.query_hash = qs.query_hash
                        cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                        cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                        outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                        where pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                        order by lq.elapsed_time desc,
                            lq.query_hash,
                            qs.total_elapsed_time desc
                        option (recompile)"

        $frequency = ";with frequent_queries as
                        (
                            select top $Limit
                                query_hash,
                                sum(execution_count) executions
                            from sys.dm_exec_query_stats
                            where query_hash <> 0x0
                            group by query_hash
                            order by sum(execution_count) desc
                        )
                        select $instancecolumns
                            coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                            coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                            qs.query_hash as QueryHash,
                            qs.execution_count as ExecutionCount,
                            executions as QueryTotalExecutions,
                            SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                                (CASE
                                    WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                                    ELSE qs.statement_end_offset
                                    END - qs.statement_start_offset) / 2) as QueryText,
                            qp.query_plan as QueryPlan
                        from sys.dm_exec_query_stats qs
                        join frequent_queries fq
                            on fq.query_hash = qs.query_hash
                        cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                        cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                        outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                        where pa.attribute = 'dbid'  $wheredb $wherenotdb $whereexcludesystem
                        order by fq.executions desc,
                            fq.query_hash,
                            qs.execution_count desc
                        option (recompile)"

        $io = ";with high_io_queries as
                (
                    select top $Limit
                        query_hash,
                        sum(total_logical_reads + total_logical_writes) io
                    from sys.dm_exec_query_stats
                    where query_hash <> 0x0
                    group by query_hash
                    order by sum(total_logical_reads + total_logical_writes) desc
                )
                select $instancecolumns
                    coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                    coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                    qs.query_hash as QueryHash,
                    qs.total_logical_reads + total_logical_writes as TotalIO,
                    qs.execution_count as ExecutionCount,
                    cast((total_logical_reads + total_logical_writes) / (execution_count + 0.0) as money) as AverageIO,
                    io as QueryTotalIO,
                    SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                        (CASE
                            WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                            ELSE qs.statement_end_offset
                            END - qs.statement_start_offset) / 2) as QueryText,
                    qp.query_plan as QueryPlan
                from sys.dm_exec_query_stats qs
                join high_io_queries fq
                    on fq.query_hash = qs.query_hash
                cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                where pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                order by fq.io desc,
                    fq.query_hash,
                    qs.total_logical_reads + total_logical_writes desc
                option (recompile)"

        $cpu = ";with high_cpu_queries as
                (
                    select top $Limit
                        query_hash,
                        sum(total_worker_time) cpuTime
                    from sys.dm_exec_query_stats
                    where query_hash <> 0x0
                    group by query_hash
                    order by sum(total_worker_time) desc
                )
                select $instancecolumns
                    coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                    coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                    qs.query_hash as QueryHash,
                    qs.total_worker_time as CpuTime,
                    qs.execution_count as ExecutionCount,
                    cast(total_worker_time / (execution_count + 0.0) as money) as AverageCpuMs,
                    cpuTime as QueryTotalCpu,
                    SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                        (CASE
                            WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                            ELSE qs.statement_end_offset
                            END - qs.statement_start_offset) / 2) as QueryText,
                    qp.query_plan as QueryPlan
                from sys.dm_exec_query_stats qs
                join high_cpu_queries hcq
                    on hcq.query_hash = qs.query_hash
                cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                where pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                order by hcq.cpuTime desc,
                    hcq.query_hash,
                    qs.total_worker_time desc
                option (recompile)"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10 -StatementTimeout 0
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Type -in "All", "Duration") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $duration"
                    $server.Query($duration) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for duration." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($Type -in "All", "Frequency") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $frequency"
                    $server.Query($frequency) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for frequency." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($Type -in "All", "IO") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $io"
                    $server.Query($io) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for IO." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($Type -in "All", "CPU") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $cpu"
                    $server.Query($cpu) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for CPU." -ErrorRecord $_ -Target $server -Continue
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUeoXqA8Sc+vn7IzqweLF7SNQX
# Vs+gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFEUMCjKhGL8rjQCf6+n7jy3kDa3VMA0GCSqGSIb3DQEBAQUABIIBAB6Bh7JT
# J97OrW9MoU3UvfsM3aVlNRo6VYYfYkhXBcQ6BSKjlqFU8sk5uPdnORH3bUvrn8bl
# /8PQ5ylQ4g7xp8EajzP08OfqEThT7QuL8AGbUXb6YmvR2JCH9e9RzSDMdFzPd77K
# i3GYMjcC3NMe/oNjHlsVdTP/1gHTquQ4AK/h/Sn7Rd6gKafyVz4vOAIay83p69r9
# x1+70upZB78CAudGdOPBSceY5raEPm19T7i6EM2LypId9fbCDRo7+K6MCb8Hi0Gn
# NG60IFQjAUvm4jMe70JEF1EUdRaDhvg08q6gxSSkQnirMNgZrd2GYU9/Lw7sl2L7
# rAcBfEdVlMQwmI2hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUyOVowLwYJKoZIhvcNAQkEMSIEIA66pGF9XxoDpdBWTS2N0Yobvq9O
# ZcRbWNYXqMEDtjd4MA0GCSqGSIb3DQEBAQUABIIBAGcHR76DtPEU8dD0+PmmROtH
# CKZEy1H+jj6yl87lMQkz65GeLH9ZlRGJ5A+lj/Vfi5nIWTzFu2ZT8P3/iW2rJv9q
# p+k+RxyPh878cuafhW3NxuDKGxIqaIBoW1CHkkOGz0O+VWskWglneX7deyIN6n8a
# 2+/RiSDb25foJZxriqM6XwtEIW8ECSE920y79/QpIW2dYzaVeTC056fEu26hMXhv
# zv+8nueLZ74HHu8pgMMmWLQnNs2f/SR1ItxQgJqdLCmRKms0b3XnXLVYIUiKdLEe
# u/8ut0hGb9QfEZDBFT42qGcCM7wHdWroZkKf+VvzYCIe1EWAYUIa7KIDolDc/d8=
# SIG # End signature block
