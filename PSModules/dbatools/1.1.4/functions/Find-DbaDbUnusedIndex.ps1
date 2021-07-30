function Find-DbaDbUnusedIndex {
    <#
    .SYNOPSIS
        Find unused indexes

    .DESCRIPTION
        This command will help you to find Unused indexes on a database or a list of databases

        For now only supported for CLUSTERED and NONCLUSTERED indexes

    .PARAMETER SqlInstance
        The SQL Server you want to check for unused indexes.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

    .PARAMETER IgnoreUptime
        Less than 7 days uptime can mean that analysis of unused indexes is unreliable, and normally no results will be returned. By setting this option results will be returned even if the Instance has been running for less than 7 days.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Seeks
        Specify a custom threshold for user seeks. The default for this parameter is 1.
        The valid values are between 1 and 1000000 to provide flexibility on the definition of 'unused' indexes.
        Note: The resulting WHERE clause uses the AND operator:
        user_seeks < $Seeks
        AND user_scans < $Scans
        AND user_lookups < $Lookups

    .PARAMETER Scans
        Specify a custom threshold for user scans. The default for this parameter is 1.
        The valid values are between 1 and 1000000 to provide flexibility on the definition of 'unused' indexes.
        Note: The resulting WHERE clause uses the AND operator:
        user_seeks < $Seeks
        AND user_scans < $Scans
        AND user_lookups < $Lookups

    .PARAMETER Lookups
        Specify a custom threshold for user lookups. The default for this parameter is 1.
        The valid values are between 1 and 1000000 to provide flexibility on the definition of 'unused' indexes.
        Note: The resulting WHERE clause uses the AND operator:
        user_seeks < $Seeks
        AND user_scans < $Scans
        AND user_lookups < $Lookups

    .NOTES
        Tags: Index
        Author: Aaron Nelson (@SQLvariant), SQLvariant.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaDbUnusedIndex

    .EXAMPLE
        PS C:\> Find-DbaDbUnusedIndex -SqlInstance sql2016 -Database db1, db2

        Finds unused indexes on db1 and db2 on sql2016

    .EXAMPLE
        PS C:\> Find-DbaDbUnusedIndex -SqlInstance sql2016 -SqlCredential $cred

        Finds unused indexes on db1 and db2 on sql2016 using SQL Authentication to connect to the server

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 | Find-DbaDbUnusedIndex

        Finds unused indexes on all databases on sql2016

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2019 | Find-DbaDbUnusedIndex -Seeks 10 -Scans 100 -Lookups 1000

        Finds 'unused' indexes with user_seeks < 10, user_scans < 100, and user_lookups < 1000 on all databases on sql2019.
        Note that these additional parameters provide flexibility to define what is considered an 'unused' index.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IgnoreUptime,
        [ValidateRange(1, 1000000)][int]$Seeks = 1,
        [ValidateRange(1, 1000000)][int]$Scans = 1,
        [ValidateRange(1, 1000000)][int]$Lookups = 1,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        # Support Compression 2008+
        $sql = "
        ;WITH
            CTE_IndexSpace
        AS
        (
            SELECT
                s.object_id                         AS object_id
            ,   s.index_id                          AS index_id
            ,   SUM(s.used_page_count) * 8 / 1024.0 AS IndexSizeMB
            ,   SUM(p.[rows])                       AS [RowCount]
            --REPLACEPARAMCTE
            FROM
                sys.dm_db_partition_stats AS s
            INNER JOIN
                sys.partitions p WITH (NOLOCK)
                    ON s.[partition_id] = p.[partition_id]
                    AND s.[object_id] = p.[object_id]
                    AND s.index_id = p.index_id
            WHERE
                s.index_id > 0 -- Exclude HEAPS
                AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
            GROUP BY
                s.[object_id]
            ,   s.index_id
            --REPLACEPARAMCTE
        )
        SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, DB_NAME(database_id) AS 'Database'
        ,s.name AS 'Schema'
        ,t.name AS 'Table'
        ,i.object_id AS ObjectId
        ,i.name AS 'IndexName'
        ,i.index_id as 'IndexId'
        ,i.type_desc as 'TypeDesc'
        ,user_seeks as 'UserSeeks'
        ,user_scans as 'UserScans'
        ,user_lookups  as 'UserLookups'
        ,user_updates  as 'UserUpdates'
        ,last_user_seek  as 'LastUserSeek'
        ,last_user_scan  as 'LastUserScan'
        ,last_user_lookup  as 'LastUserLookup'
        ,last_user_update  as 'LastUserUpdate'
        ,system_seeks  as 'SystemSeeks'
        ,system_scans  as 'SystemScans'
        ,system_lookups  as 'SystemLookup'
        ,system_updates  as 'SystemUpdates'
        ,last_system_seek  as 'LastSystemSeek'
        ,last_system_scan  as 'LastSystemScan'
        ,last_system_lookup  as 'LastSystemLookup'
        ,last_system_update as 'LastSystemUpdate'
        ,COALESCE(indexSpace.IndexSizeMB, 0) AS 'IndexSizeMB'
        ,COALESCE(indexSpace.[RowCount], 0) AS 'RowCount'
        --REPLACEPARAMSELECT
        FROM sys.tables t
        JOIN sys.schemas s
            ON t.schema_id = s.schema_id
        JOIN sys.indexes i
            ON i.object_id = t.object_id
        LEFT OUTER JOIN sys.dm_db_index_usage_stats iu
            ON iu.object_id = i.object_id
                AND iu.index_id = i.index_id
        JOIN CTE_IndexSpace indexSpace
            ON indexSpace.index_id = i.index_id
                AND indexSpace.object_id = i.object_id
        WHERE iu.database_id = DB_ID()
                AND OBJECTPROPERTY(i.[object_id], 'IsMSShipped') = 0
                AND user_seeks < $Seeks
                AND user_scans < $Scans
                AND user_lookups < $Lookups
                AND i.type_desc NOT IN ('HEAP', 'CLUSTERED COLUMNSTORE')"

        # Replacement values for the SQL above
        $replaceParamCTE = "--REPLACEPARAMCTE"
        $replaceValueCTE = ", p.data_compression_desc"
        $replaceParamSelect = "--REPLACEPARAMSELECT"
        $replaceValueSelect = ", indexSpace.data_compression_desc AS CompressionDescription"
    }

    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        # Return a warning if the database specified was not found
        if ($null -eq $InputObject -or $InputObject.Count -eq 0) {
            Write-Message -Level Warning -Message "Database [$Database] was not found on [$SqlInstance]."
            continue
        }

        foreach ($db in $InputObject) {
            if ($db.Parent.Databases[$db].IsAccessible -eq $false) {
                Write-Message -Level Warning -Message "Database [$db] is not accessible."
                continue
            }

            $server = $db.Parent
            $instance = $server.Name

            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "This function does not support versions lower than SQL Server 2005 (v9)." -Continue
            }

            $lastRestart = $server.Databases['tempdb'].CreateDate
            $endDate = Get-Date -Date $lastRestart
            $diffDays = (New-TimeSpan -Start $endDate -End (Get-Date)).Days

            if ($diffDays -le 6) {
                if ($IgnoreUptime) {
                    Write-Message -Level Verbose -Message "The SQL Service was restarted on $lastRestart, which is not long enough for a solid evaluation."
                } else {
                    Stop-Function -Message "The SQL Service on $instance was restarted on $lastRestart, which is not long enough for a solid evaluation." -Continue
                }
            }

            <#
                Validate if server version is:
                    - sql 2012 and if have SP3 CU3 (Build 6537) or higher
                    - sql 2014 and if have SP2 (Build 5000) or higher
                If the major version is the same but the build is lower, throws the message
            #>

            if (($server.VersionMajor -eq 11 -and $server.BuildNumber -lt 6537) -or ($server.VersionMajor -eq 12 -and $server.BuildNumber -lt 5000)) {
                Stop-Function -Message "This SQL version has a known issue. Rebuilding an index clears any existing row entry from sys.dm_db_index_usage_stats for that index.`r`nPlease refer to connect item: https://support.microsoft.com/en-us/help/3160407/fix-sys-dm-db-index-usage-stats-missing-information-after-index-rebuil" -Continue
            }

            if ($diffDays -le 33) {
                Write-Message -Level Verbose -Message "The SQL Service on $instance was restarted on $lastRestart, which may not be long enough for a solid evaluation."
            }

            <#
                Data compression was added in SQL 2008, so add in the additional compression description column for versions 2008 or higher.
            #>
            $sqlToRun = $sql

            if ($server.VersionMajor -gt 9) {
                $sqlToRun = $sqlToRun.Replace($replaceParamCTE, $replaceValueCTE).Replace($replaceParamSelect, $replaceValueSelect)
            }

            try {
                $db.Query($sqlToRun)
            } catch {
                Stop-Function -Message "Issue gathering indexes" -Category InvalidOperation -ErrorRecord $_ -Target $db
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUlZI1AzF8f/AivX5XKjcLmQN0
# a32gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFA56HpeE4hlR7ORXzin8ekgCVHzRMA0GCSqGSIb3DQEBAQUABIIBAGHahdEy
# GAyzQSB/9g979zTKIcmsox17J/Q4N4WOCXb6v2Et+y4WGY6m4ZwJPZ8PRjehCySt
# rSXlhP6HpLp6/LsJ0FjFa12ObOzlaP6BMlhD99xo3pItRolt1b2RYUWnHSxqNJPZ
# 1cmhGe4s8N7c90wDznmnt4m3hoob9jFbA7N/c+5v1UuIiCKJG5c99UBWEoan5pQV
# yywVkjwuydv1Lu0AGXRpuK7yNrF2Ub5ksKwrAU+wLoI8z8BdpTfPWuJaLs0BjO2u
# 7yZxOfizNQSvmvp0QKr9KL0Z8kP/p9gXe7662HSrfv9S1KOw7SzuumNTFNJWIUIj
# BKQGghJ8MDEckyOhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkyM1owLwYJKoZIhvcNAQkEMSIEIOOuSuHs7s4RyFxHNuCO3P1Z1yhF
# DFq38rN2H04Ed9vtMA0GCSqGSIb3DQEBAQUABIIBABKGQZgeX4KcfR3sPo63CBfl
# JuQmc50EcdaMplAtfuJeSKc/pqS7V57Hm1kdr0t98dSxMcOFqqz7E5/yqxWa6mjd
# xV1U8UNqoU5whWZhF2GzclepXNDk+4cssyDWarR2vUh0/2Qh0W/jFJ//KzXSmkQ+
# 1bv6IrE9Fa7uHDoboqJLpHqxfGCWA1m5CrYAFODBYKK5TZKN+4Q+SMrXIzhZlcgX
# ulKLCqDIGX3CKastd9vvuiHYe45K2Iyj0qoLqH7c++aj7JFTduJD/PV6NtH87rOe
# 9wvwq6pry/j1m4DdxWib/SNtPeNX97IkvzY0X1XZpnyG9azBAM13qsxHF8BTy4Q=
# SIG # End signature block
