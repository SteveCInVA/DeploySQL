function Get-DbaDbSpace {
    <#
    .SYNOPSIS
        Returns database file space information for database files on a SQL instance.

    .DESCRIPTION
        This function returns database file space information for a SQL Instance or group of SQL Instances. Information is based on a query against sys.database_files and the FILEPROPERTY function to query and return information.

        File free space script borrowed and modified from Glenn Berry's DMV scripts (http://www.sqlskills.com/blogs/glenn/category/dmv-queries/)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

    .PARAMETER InputObject
        A piped collection of database objects from Get-DbaDatabase

    .PARAMETER IncludeSystemDBs
        Deprecated - if filtering is needed, please pipe filtered results from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Space
        Author: Michael Fal (@Mike_Fal), http://mikefal.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbSpace

    .EXAMPLE
        PS C:\> Get-DbaDbSpace -SqlInstance localhost

        Returns all user database files and free space information for the localhost.

    .EXAMPLE
        PS C:\> Get-DbaDbSpace -SqlInstance localhost | Where-Object {$_.PercentUsed -gt 80}

        Returns all user database files and free space information for the local host. Filters the output object by any files that have a percent used of greater than 80%.

    .EXAMPLE
        PS C:\> 'localhost','localhost\namedinstance' | Get-DbaDbSpace

        Returns all user database files and free space information for the localhost and localhost\namedinstance SQL Server instances. Processes data via the pipeline.

    .EXAMPLE
        PS C:\> Get-DbaDbSpace -SqlInstance localhost -Database db1, db2 | Where-Object { $_.SpaceUntilMaxSize.Megabyte -lt 1 }

        Returns database files and free space information for the db1 and db2 on localhost where there is only 1MB left until the space is maxed out

    .EXAMPLE
        PS C:\> Get-DbaDbSpace -SqlInstance localhost -Database db1, db2 | Where-Object { $_.SpaceUntilMaxSize.Gigabyte -lt 1 }

        Returns database files and free space information for the db1 and db2 on localhost where there is only 1GB left until the space is maxed out

    #>
    [CmdletBinding()]
    param ([parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$IncludeSystemDBs,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                                   ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                                   SERVERPROPERTY('ServerName') AS SqlInstance,
                    DB_NAME() as DBName
                    ,f.name AS [FileName]
                    ,fg.name AS [Filegroup]
                    ,f.physical_name AS [PhysicalName]
                    ,f.type_desc AS [FileType]
                    ,CAST(CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS FLOAT) as [UsedSpaceMB]
                    ,CAST(f.size/128.0 - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS FLOAT) AS [FreeSpaceMB]
                    ,CAST((f.size/128.0) AS FLOAT) AS [FileSizeMB]
                    ,CAST((FILEPROPERTY(f.name, 'SpaceUsed')/(f.size/1.0)) * 100 as FLOAT) as [PercentUsed]
                    ,CAST((f.growth/128.0) AS FLOAT) AS [GrowthMB]
                    ,CASE is_percent_growth WHEN 1 THEN 'pct' WHEN 0 THEN 'MB' ELSE 'Unknown' END AS [GrowthType]
                    ,CASE f.max_size WHEN -1 THEN 2147483648. ELSE CAST((f.max_size/128.0) AS FLOAT) END AS [MaxSizeMB]
                    ,CAST((f.size/128.0) AS FLOAT) - CAST(CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS FLOAT) AS [SpaceBeforeAutoGrow]
                    ,CASE f.max_size	WHEN (-1)
                                        THEN CAST(((2147483648.) - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int))/128.0 AS FLOAT)
                                        ELSE CAST((f.max_size - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int))/128.0 AS FLOAT)
                                        END AS [SpaceBeforeMax]
                    ,CASE f.growth	WHEN 0 THEN 0.00
                                    ELSE	CASE f.is_percent_growth	WHEN 0
                                                    THEN	CASE f.max_size
                                                            WHEN (-1)
                                                            THEN CAST(((((2147483648.)-f.Size)/f.Growth)*f.Growth)/128.0 AS FLOAT)
                                                            ELSE CAST((((f.max_size-f.Size)/f.Growth)*f.Growth)/128.0 AS FLOAT)
                                                            END
                                                    WHEN 1
                                                    THEN	CASE f.max_size
                                                            WHEN (-1)
                                                            THEN CAST(CONVERT([int],f.Size*power((1)+CONVERT([float],f.Growth)/(100),CONVERT([int],log10(CONVERT([float],(2147483648.))/CONVERT([float],f.Size))/log10((1)+CONVERT([float],f.Growth)/(100)))))/128.0 AS FLOAT)
                                                            ELSE CAST(CONVERT([int],f.Size*power((1)+CONVERT([float],f.Growth)/(100),CONVERT([int],log10(CONVERT([float],f.Max_Size)/CONVERT([float],f.Size))/log10((1)+CONVERT([float],f.Growth)/(100)))))/128.0 AS FLOAT)
                                                            END
                                                    ELSE (0)
                                                    END
                                    END AS [PossibleAutoGrowthMB]
                    , CASE f.max_size	WHEN -1 THEN 0
                                        ELSE CASE f.growth
                                                WHEN 0 THEN (f.max_size - f.size)/128
                                                ELSE	CASE f.is_percent_growth
                                                        WHEN 0
                                                        THEN CAST((f.max_size - f.size - (	CONVERT(FLOAT,FLOOR((f.max_size-f.Size)/f.Growth)*f.Growth)))/128.0 AS FLOAT)
                                                        ELSE CAST((f.max_size - f.size - (	CONVERT([int],f.Size*power((1)+CONVERT([float],f.Growth)/(100),CONVERT([int],log10(CONVERT([float],f.Max_Size)/CONVERT([float],f.Size))/log10((1)+CONVERT([float],f.Growth)/(100)))))))/128.0 AS FLOAT)
                                                        END
                                                END
                                    END AS [UnusableSpaceMB]

                FROM sys.database_files AS f WITH (NOLOCK)
                LEFT OUTER JOIN sys.filegroups AS fg WITH (NOLOCK)
                ON f.data_space_id = fg.data_space_id"
    }

    process {
        if ($IncludeSystemDBs) {
            Stop-Function -Message "IncludeSystemDBs will be removed. Please pipe in filtered results from Get-DbaDatabase instead."
            return
        }
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "SQL Server 2000 not supported. $server skipped." -Continue
            }

            try {
                Write-Message -Level Verbose -Message "Querying $instance - $db."
                If ($db.status -ne 'Normal' -or $db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "$db is not accessible." -Target $db
                    continue
                }
                #Execute query against individual database and add to output
                foreach ($row in ($db.ExecuteWithResults($sql)).Tables.Rows) {
                    if ($row.UsedSpaceMB -is [System.DBNull]) {
                        $UsedMB = 0
                    } else {
                        $UsedMB = [Math]::Round($row.UsedSpaceMB)
                    }
                    if ($row.FreeSpaceMB -is [System.DBNull]) {
                        $FreeMB = 0
                    } else {
                        $FreeMB = [Math]::Round($row.FreeSpaceMB)
                    }
                    if ($row.PercentUsed -is [System.DBNull]) {
                        $PercentUsed = 0
                    } else {
                        $PercentUsed = [Math]::Round($row.PercentUsed)
                    }
                    if ($row.SpaceBeforeMax -is [System.DBNull]) {
                        $SpaceUntilMax = 0
                    } else {
                        $SpaceUntilMax = [Math]::Round($row.SpaceBeforeMax)
                    }
                    if ($row.UnusableSpaceMB -is [System.DBNull]) {
                        $UnusableSpace = 0
                    } else {
                        $UnusableSpace = [Math]::Round($row.UnusableSpaceMB)
                    }

                    [pscustomobject]@{
                        ComputerName       = $server.ComputerName
                        InstanceName       = $server.ServiceName
                        SqlInstance        = $server.DomainInstanceName
                        Database           = $row.DBName
                        FileName           = $row.FileName
                        FileGroup          = $row.FileGroup
                        PhysicalName       = $row.PhysicalName
                        FileType           = $row.FileType
                        UsedSpace          = [dbasize]($UsedMB * 1024 * 1024)
                        FreeSpace          = [dbasize]($FreeMB * 1024 * 1024)
                        FileSize           = [dbasize]($row.FileSizeMB * 1024 * 1024)
                        PercentUsed        = $PercentUsed
                        AutoGrowth         = [dbasize]($row.GrowthMB * 1024 * 1024)
                        AutoGrowType       = $row.GrowthType
                        SpaceUntilMaxSize  = [dbasize]($SpaceUntilMax * 1024 * 1024)
                        AutoGrowthPossible = [dbasize]($row.PossibleAutoGrowthMB * 1024 * 1024)
                        UnusableSpace      = [dbasize]($UnusableSpace * 1024 * 1024)
                    }
                }
            } catch {
                Stop-Function -Message "Unable to query $instance - $db." -Target $db -ErrorRecord $_ -Continue
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUZpHHK3Fy4s4m+wc9+6znYmOo
# QU2gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFFCUj99LXG3pEupxROr8hsEQSJI/MA0GCSqGSIb3DQEBAQUABIIBAHWp/bMm
# uBm2vwBbh5ovwRHvz+vG67AvXvCV047NUDOgSQFCx0A1xPhbTlcKgaSLbyOD1uMl
# 0Xv2D4f5NEZGSYUnl0yX1w/q9kmuHGNklEfu5bx2WR9/DW8owdPdwRB3/S0SrZXo
# EPoULg6S7s3uk8Rkazohg588PApiOMEZ6nH5eBTzWt628Uy/A2ZDIp29NS9orvkz
# HtIsF2d7CQYCyMxQPYXSmqx2k2/SpUbzU0bKJaDdRpHoYLOepgS6tUbVPx+HbJjo
# k0WPEce9Iaegng07bDGVvar4YSJUQtOP2J7wepDKJ2SnSM9XNQJX3C8FGb4rzlhK
# Ga0Rob3jGSQS88ehggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkzM1owLwYJKoZIhvcNAQkEMSIEIBizesjGxhNvcJM4UK3fPA5j68HQ
# KkK+1zhLlXlRaHkqMA0GCSqGSIb3DQEBAQUABIIBAD2oWYKb4+9bg40/8NMsb3qK
# pLEy4kQPW9/lQeGDHxL0EU7Az/PG7qKaTCArb3VXlPChGCXLgwMl1tDZ+ReJ2A3N
# fr6lArn9GQ7rgVPNtdBIyFNHb308FAqA7D7KaiPgu0MVXM56JuLca+zr7KcK3pXE
# 2Mgq6+IIdIBhmr+AiOOFazCm66hBcSlH6joRyMqCsJDLgCP2WGJcWdKiwLNFx8OK
# ljSsUY7m7yfw9J9svnaUCaOYmt4s3E4imRVmvXV89abJAn0KkZ8KTJNvvcrZg+cs
# Jhs8huzCNDpWouEE9jnejzgIVtrh1HUFCUj5TbRI1L3d1NZdUyzYUJw3T23Ip/g=
# SIG # End signature block
