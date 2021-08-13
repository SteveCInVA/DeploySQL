function Invoke-DbaDbUpgrade {
    <#
    .SYNOPSIS
        Take a database and upgrades it to compatibility of the SQL Instance its hosted on. Based on https://thomaslarock.com/2014/06/upgrading-to-sql-server-2014-a-dozen-things-to-check/

    .DESCRIPTION
        Updates compatibility level, then runs CHECKDB with data_purity, DBCC updateusage, sp_updatestats and finally sp_refreshview against all user views.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is autopopulated from the server

    .PARAMETER AllUserDatabases
        Run command against all user databases

    .PARAMETER Force
        Don't skip over databases that are already at the same level the instance is

    .PARAMETER NoCheckDb
        Skip checkdb

    .PARAMETER NoUpdateUsage
        Skip usage update

    .PARAMETER NoUpdateStats
        Skip stats update

    .PARAMETER NoRefreshView
        Skip view update

    .PARAMETER InputObject
        A collection of databases (such as returned by Get-DbaDatabase)

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Update database" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Shrink, Database
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbUpgrade

    .EXAMPLE
        PS C:\> Invoke-DbaDbUpgrade -SqlInstance PRD-SQL-MSD01 -Database Test

        Runs the below processes against the databases
        -- Puts compatibility of database to level of SQL Instance
        -- Runs CHECKDB DATA_PURITY
        -- Runs DBCC UPDATESUSAGE
        -- Updates all users statistics
        -- Runs sp_refreshview against every view in the database

    .EXAMPLE
        PS C:\> Invoke-DbaDbUpgrade -SqlInstance PRD-SQL-INT01 -Database Test -NoRefreshView

        Runs the upgrade command skipping the sp_refreshview update on all views

    .EXAMPLE
        PS C:\> Invoke-DbaDbUpgrade -SqlInstance PRD-SQL-INT01 -Database Test -Force

        If database Test is already at the correct compatibility, runs every necessary step

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 | Out-GridView -Passthru | Invoke-DbaDbUpgrade

        Get only specific databases using GridView and pass those to Invoke-DbaDbUpgrade

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$NoCheckDb,
        [switch]$NoUpdateUsage,
        [switch]$NoUpdateStats,
        [switch]$NoRefreshView,
        [switch]$AllUserDatabases,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {

        if (Test-Bound -not 'SqlInstance', 'InputObject') {
            Write-Message -Level Warning -Message "You must specify either a SQL instance or pipe a database collection"
            continue
        }

        if (Test-Bound -not 'Database', 'InputObject', 'ExcludeDatabase', 'AllUserDatabases') {
            Write-Message -Level Warning -Message "You must explicitly specify a database. Use -Database, -ExcludeDatabase, -AllUserDatabases or pipe a database collection"
            continue
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                $server.ConnectionContext.StatementTimeout = [Int32]::MaxValue
            } catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }
            $InputObject += $server.Databases | Where-Object IsAccessible
        }

        $InputObject = $InputObject | Where-Object { $_.IsSystemObject -eq $false }
        if ($Database) {
            $InputObject = $InputObject | Where-Object Name -In $Database
        }
        if ($ExcludeDatabase) {
            $InputObject = $InputObject | Where-Object Name -NotIn $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            # create objects to use in updates
            $server = $db.Parent
            $ServerVersion = $server.VersionMajor
            Write-Message -Level Verbose -Message "SQL Server is using Version: $ServerVersion"

            $ogcompat = $db.CompatibilityLevel
            $dbName = $db.Name
            $dbversion = switch ($db.CompatibilityLevel) {
                "Version100" { 10 } # SQL Server 2008
                "Version110" { 11 } # SQL Server 2012
                "Version120" { 12 } # SQL Server 2014
                "Version130" { 13 } # SQL Server 2016
                "Version140" { 14 } # SQL Server 2017
                default { 9 } # SQL Server 2005
            }
            if (-not $Force) {
                # skip over databases at the correct level, unless -Force
                if ($dbversion -ge $ServerVersion) {
                    Write-Message -Level VeryVerbose -Message "Skipping $db because compatibility is at the correct level. Use -Force if you want to run all the additional steps"
                    continue
                }
            }
            Write-Message -Level Verbose -Message "Updating $db compatibility to SQL Instance level"
            if ($dbversion -lt $ServerVersion) {
                If ($Pscmdlet.ShouldProcess($server, "Updating $db version on $server from $dbversion to $ServerVersion")) {
                    $Comp = $ServerVersion * 10
                    $tsqlComp = "ALTER DATABASE $db SET COMPATIBILITY_LEVEL = $Comp"
                    try {
                        $db.ExecuteNonQuery($tsqlComp)
                        $comResult = $Comp
                    } catch {
                        Write-Message -Level Warning -Message "Failed run Compatibility Upgrade" -ErrorRecord $_ -Target $instance
                        $comResult = "Fail"
                    }
                }
            } else {
                $comResult = "No change"
            }

            if (!($NoCheckDb)) {
                Write-Message -Level Verbose -Message "Updating $db with DBCC CHECKDB DATA_PURITY"
                If ($Pscmdlet.ShouldProcess($server, "Updating $db with DBCC CHECKDB DATA_PURITY")) {
                    $tsqlCheckDB = "DBCC CHECKDB ('$dbName') WITH DATA_PURITY, NO_INFOMSGS"
                    try {
                        $db.ExecuteNonQuery($tsqlCheckDB)
                        $DataPurityResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed run DBCC CHECKDB with DATA_PURITY on $db" -ErrorRecord $_ -Target $instance
                        $DataPurityResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignoring CHECKDB DATA_PURITY"
            }

            if (!($NoUpdateUsage)) {
                Write-Message -Level Verbose -Message "Updating $db with DBCC UPDATEUSAGE"
                If ($Pscmdlet.ShouldProcess($server, "Updating $db with DBCC UPDATEUSAGE")) {
                    $tsqlUpdateUsage = "DBCC UPDATEUSAGE ($db) WITH NO_INFOMSGS;"
                    try {
                        $db.ExecuteNonQuery($tsqlUpdateUsage)
                        $UpdateUsageResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed to run DBCC UPDATEUSAGE on $db" -ErrorRecord $_ -Target $instance
                        $UpdateUsageResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignore DBCC UPDATEUSAGE"
                $UpdateUsageResult = "Skipped"
            }

            if (!($NoUpdatestats)) {
                Write-Message -Level Verbose -Message "Updating $db statistics"
                If ($Pscmdlet.ShouldProcess($server, "Updating $db statistics")) {
                    $tsqlStats = "EXEC sp_updatestats;"
                    try {
                        $db.ExecuteNonQuery($tsqlStats)
                        $UpdateStatsResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed to run sp_updatestats on $db" -ErrorRecord $_ -Target $instance
                        $UpdateStatsResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignoring sp_updatestats"
                $UpdateStatsResult = "Skipped"
            }

            if (!($NoRefreshView)) {
                Write-Message -Level Verbose -Message "Refreshing $db Views"
                $dbViews = $db.Views | Where-Object IsSystemObject -eq $false
                $RefreshViewResult = "Success"
                foreach ($dbview in $dbviews) {
                    $viewName = $dbView.Name
                    $viewSchema = $dbView.Schema
                    $fullName = $viewSchema + "." + $viewName

                    $tsqlupdateView = "EXECUTE sp_refreshview N'$fullName';  "

                    If ($Pscmdlet.ShouldProcess($server, "Refreshing view $fullName on $db")) {
                        try {
                            $db.ExecuteNonQuery($tsqlupdateView)
                        } catch {
                            Write-Message -Level Warning -Message "Failed update view $fullName on $db" -ErrorRecord $_ -Target $instance
                            $RefreshViewResult = "Fail"
                        }
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignore View Refreshes"
                $RefreshViewResult = "Skipped"
            }

            If ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                $db.Refresh()

                [PSCustomObject]@{
                    ComputerName          = $server.ComputerName
                    InstanceName          = $server.ServiceName
                    SqlInstance           = $server.DomainInstanceName
                    Database              = $db.name
                    OriginalCompatibility = $ogcompat.ToString().Replace('Version', '')
                    CurrentCompatibility  = $db.CompatibilityLevel.ToString().Replace('Version', '')
                    Compatibility         = $comResult
                    DataPurity            = $DataPurityResult
                    UpdateUsage           = $UpdateUsageResult
                    UpdateStats           = $UpdateStatsResult
                    RefreshViews          = $RefreshViewResult
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU4XF7Wd01D56MxBZiR7tbAhEp
# 9x2gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFM7nmPenihyUCL48HiauzmYE956pMA0GCSqGSIb3DQEBAQUABIIBABA1kAE5
# QIXSQbwEXAC4EpKEMW30XJ/Uap0ZJcX185iaFI1xgPWyoOLak6BbDYHf0FH6/zU7
# L3iEmOlQsiMtR8h6x8m95UXjUrMvsmeFdt26K9PZBTjxkXBGAflaLZ3JdcR+TiSR
# zBRUENE9s2J+POD2Z8daBsNh6FUt2qANzSyRohJi14qVu65FSuY/lRZ41PAfg4ul
# bzNXvYg2U9AdYSPQz7bQBWATA1/URtz1OadYI+A0Zhj5Mw4zeanwPNLjs8FuiQ5Q
# tMFo4YCWEBxn8mqvHnFx8Yu6kpUhRWSxhVNRS0H6WYvZGv1ABUpG7Anq23aht+MI
# t7MhomC5OlrGXUKhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzNlowLwYJKoZIhvcNAQkEMSIEIK1LQT15PX+qWldlTVTDWMxxq0mm
# ZJj8lgCh5qg3YnraMA0GCSqGSIb3DQEBAQUABIIBAJmGhg7wKRd6FCDm4e1xW/C4
# Hhmz6B+VY34vKEhNks1UO2bSQI2WmKoiYwvtux6Tmp/JsYkdHC7O8bL0MQfMLCI9
# qqmbljtlCh6ljp7VTmN00iVerHIkTOPy0JRC2B6RmzYTJ4e2arHRlXBrqk3Q9chc
# F92yeG+IgZYQNa4SyQ2jNiKDB3keaS1A9h3+gs+r3e0uWm/fDpZW5OdlfTGvJQsY
# hjb2sptClmx85E43AJO+BZxppIoad0KnU0BBViJBRZ80I/qWqMHRrmAuSliX4qPE
# XDQhVBNMzyFuwh3OmLC5lw0lggQjsRVwF5w8sm1XewLkzWIE/YEBzYgH+BBFSeE=
# SIG # End signature block
