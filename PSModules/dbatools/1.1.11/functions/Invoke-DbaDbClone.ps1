function Invoke-DbaDbClone {
    <#
    .SYNOPSIS
        Clones a database schema and statistics

    .DESCRIPTION
        Clones a database schema and statistics.

        This can be useful for testing query performance without requiring all the space needed for the data in the database.

        Read more:
            - https://sqlperformance.com/2016/08/sql-statistics/expanding-dbcc-clonedatabase
            - https://support.microsoft.com/en-us/help/3177838/how-to-use-dbcc-clonedatabase-to-generate-a-schema-and-statistics-only

        Thanks to Microsoft Tiger Team for the code and idea https://github.com/Microsoft/tigertoolbox/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database to clone - this list is auto-populated from the server.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER CloneDatabase
        The name(s) to clone to.

    .PARAMETER ExcludeStatistics
        Exclude the statistics in the cloned database

    .PARAMETER ExcludeQueryStore
        Exclude the QueryStore data in the cloned database

    .PARAMETER UpdateStatistics
        Update the statistics prior to cloning (per Microsoft Tiger Team formula)

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Statistics, Performance, Clone
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbClone

    .EXAMPLE
        PS C:\> Invoke-DbaDbClone -SqlInstance sql2016 -Database mydb -CloneDatabase myclone

        Clones mydb to myclone on sql2016

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database mydb | Invoke-DbaDbClone -CloneDatabase myclone, myclone2 -UpdateStatistics

        Updates the statistics of mydb then clones to myclone and myclone2

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [string[]]$CloneDatabase,
        [switch]$ExcludeStatistics,
        [switch]$ExcludeQueryStore,
        [switch]$UpdateStatistics,
        [switch]$EnableException
    )

    begin {
        if (-not $Database -and $SqlInstance) {
            Stop-Function -Message "You must specify a database name if you did not pipe a database"
        }

        $sqlStats = "DECLARE @out TABLE(id INT IDENTITY(1,1), s SYSNAME, o SYSNAME, i SYSNAME, stats_stream VARBINARY(MAX), rows BIGINT, pages BIGINT)
            DECLARE @dbcc TABLE(stats_stream VARBINARY(MAX), rows BIGINT, pages BIGINT)
            DECLARE c CURSOR FOR
                    SELECT OBJECT_SCHEMA_NAME(object_id) s, OBJECT_NAME(object_id) o, name i
                    FROM sys.indexes
                    WHERE type_desc IN ('CLUSTERED COLUMNSTORE', 'NONCLUSTERED COLUMNSTORE')
            DECLARE @s SYSNAME, @o SYSNAME, @i SYSNAME
            OPEN c
            FETCH NEXT FROM c INTO @s, @o, @i
            WHILE @@FETCH_STATUS = 0
            BEGIN
                DECLARE @showStats NVARCHAR(MAX) = N'DBCC SHOW_STATISTICS(""' + QUOTENAME(@s) + '.' + QUOTENAME(@o) + '"", ' + QUOTENAME(@i) + ') WITH stats_stream'
                INSERT @dbcc EXEC sp_executesql @showStats
                INSERT @out SELECT @s, @o, @i, stats_stream, rows, pages FROM @dbcc
                DELETE @dbcc
                FETCH NEXT FROM c INTO @s, @o, @i
            END
            CLOSE c
            DEALLOCATE c

            DECLARE @sql NVARCHAR(MAX);
            DECLARE @id INT;
            SELECT TOP 1 @id=id,@sql=
            'UPDATE STATISTICS ' + QUOTENAME(s) + '.' + QUOTENAME(o)  + '(' + QUOTENAME(i)
            + ') WITH stats_stream = ' + CONVERT(NVARCHAR(MAX), stats_stream, 1)
            + ', rowcount = ' + CONVERT(NVARCHAR(MAX), rows) + ', pagecount = '  + CONVERT(NVARCHAR(MAX), pages)
            FROM @out

            WHILE (@@ROWCOUNT <> 0)
            BEGIN
                EXEC sp_executesql @sql
                DELETE @out WHERE id = @id
                SELECT TOP 1 @id=id,@sql=
                'UPDATE STATISTICS ' + QUOTENAME(s) + '.' + QUOTENAME(o)  + '(' + QUOTENAME(i)
                + ') WITH stats_stream = ' + CONVERT(NVARCHAR(MAX), stats_stream, 1)
                + ', rowcount = ' + CONVERT(NVARCHAR(MAX), rows) + ', pagecount = '  + CONVERT(NVARCHAR(MAX), pages)
                FROM @out
            END
        "

        $noStats = "NO_STATISTICS"
        $noQueryStore = "NO_QUERYSTORE"
        if ( (Test-Bound -ParameterName 'ExcludeStatistics') -or (Test-Bound -ParameterName 'ExcludeQueryStore') ) {
            $sqlWith = ""
            if ($ExcludeStatistics) {
                $sqlWith = "WITH $noStats"
            }
            if ($ExcludeQueryStore) {
                $sqlWith = "WITH $noQueryStore"
            }
            if ($ExcludeStatistics -and $ExcludeQueryStore) {
                $sqlWith = "WITH $noStats,$noQueryStore"
            }
        }

        $sql2012min = [version]"11.0.7001" # SQL 2012 SP4
        $sql2014min = [version]"12.0.5000" # SQL 2014 SP2
        $sql2014CuMin = [version]"12.0.5538" # SQL 2014 SP2 + CU3
        $sql2016min = [version]"13.0.4001" # SQL 2016 SP1
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $instance = $server.Name

            if (-not (Test-Bound -ParameterName CloneDatabase)) {
                $CloneDatabase = "$($db.Name)_clone"
            }

            if ($server.VersionMajor -eq 11 -and $server.Version -lt $sql2012min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2012 SP4 and above required." -Target $server -Continue
            }

            if ($server.VersionMajor -eq 12 -and $server.Version -lt $sql2014min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2014 SP2 and above required." -Target $server -Continue
            }

            if ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -Continue
            }

            if (Test-Bound -ParameterName 'ExcludeStatistics') {
                if ($server.VersionMajor -eq 12 -and $server.Version -lt $sql2014CuMin) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2014 SP1 + CU3 and above required." -Target $server -Continue
                }
                if ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -Continue
                }
            }

            if (Test-Bound -ParameterName 'ExcludeQueryStore') {
                if ($server.VersionMajor -lt 13 - ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min)) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -Continue
                }
            }

            if ($db.IsSystemObject) {
                Stop-Function -Message "Only user databases are supported" -Target $instance -Continue
            }

            if ( (Test-Bound -ParameterName 'UpdateStatistics') -and (Test-Bound -ParameterName 'ExcludeStatistics' -Not) ) {
                if ($Pscmdlet.ShouldProcess($instance, "Update statistics in $($db.Name)")) {
                    try {
                        Write-Message -Level Verbose -Message "Updating statistics"
                        $null = $db.Invoke($sqlStats)
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                    }
                }
            }

            $dbName = $db.Name

            foreach ($clonedb in $CloneDatabase) {
                Write-Message -Level Verbose -Message "Cloning $clonedb from $db"
                if ($server.Databases[$clonedb]) {
                    Stop-Function -Message "Destination clone database $clonedb already exists" -Target $instance -Continue
                } else {
                    if ($Pscmdlet.ShouldProcess($instance, "Execute DBCC CloneDatabase($dbName, $clonedb)")) {
                        try {
                            $sql = "DBCC CLONEDATABASE('$dbName','$clonedb') $sqlWith"
                            Write-Message -Level Debug -Message "Sql Statement: $sql"
                            $null = $db.Invoke($sql)
                            $server.Databases.Refresh()
                            Get-DbaDatabase -SqlInstance $server -Database $clonedb
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUSoYxW46bLA4vbaEmHUcHooDY
# V1qgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFJ2jYc9ylUd3a+5JEhba5CfAY934MA0GCSqGSIb3DQEBAQUABIIBAF2NUcm7
# zpC74pzNUOfERxO+4QIXfcVAFDoNX/UWIzt3DewKXWpZqLPy61FL3ReZBQyUuJLR
# +/WXT8JlkThpVw9oAdFQttbO3AKhFtD54WAWkgcnXM9fBVCP3cdaIyBL5f98tCgn
# clyYtspwC4AO8uKLa5RLuX8W8NkKFiRcz+SnfM2If//LISQ6lIPuow2gX1tIBKzh
# aJF+y9MVMs7H4lTZsRAHTxPhQQwhDEQSCj2sNm7X9rmF39qsq6fxmS1aPuqZHhpn
# KuUVcZ6t6wXFnefoFr43nmwpFZi54Jq6Lalk/r8Tjv7gz4/C0/yl/ZcR4vdi5c9x
# vsFWD7DebWAfDUGhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzNVowLwYJKoZIhvcNAQkEMSIEIOGpSRmuyb2k8plUunxhv3jgJCUh
# Fr56SCxajOF8P7C2MA0GCSqGSIb3DQEBAQUABIIBAGk0qxsfqjPC1sJnsP3WfRTy
# G872m0zYL6uod+8/Jk9bKEYRBMsQiC6/+o80+pPSv6iCM8wUWyScfWDgm8xtQ+5K
# M78Z4RHbMY56eXNQ6LqaU8k6qQs22DQPPxtyIpK8lxzyLxY8Ij0yyTtWE9uY0/Jq
# 4lnYPHdBjUqFNF0cYPs4jK6y1r2jmxqVCoK5OjBu/Raj+zJFfdrFK0hdEWGDGmyU
# NQnbQeIJ8+2rwf3B59j7YVdAYakwJ26yeZDcUrEmTI9XsOdzJWrEIhqaMl7Ki25l
# CS1agpZHG7HvdNMSaVzHSe5Zwws7+MCORAHVhJyTgdAQVx2LVBUGu+hXtyKT4X0=
# SIG # End signature block
