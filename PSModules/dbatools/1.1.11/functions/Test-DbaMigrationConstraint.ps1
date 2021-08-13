function Test-DbaMigrationConstraint {
    <#
    .SYNOPSIS
        Show if you can migrate the database(s) between the servers.

    .DESCRIPTION
        When you want to migrate from a higher edition to a lower one there are some features that can't be used.
        This function will validate if you have any of this features in use and will report to you.
        The validation will be made ONLY on on SQL Server 2008 or higher using the 'sys.dm_db_persisted_sku_features' dmv.

        This function only validate SQL Server 2008 versions or higher.
        The editions supported by this function are:
        - Enterprise
        - Developer
        - Evaluation
        - Standard
        - Express

        Take into account the new features introduced on SQL Server 2016 SP1 for all versions. More information at https://blogs.msdn.microsoft.com/sqlreleaseservices/sql-server-2016-service-pack-1-sp1-released/

        The -Database parameter is auto-populated for command-line completion.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaMigrationConstraint

    .EXAMPLE
        PS C:\> Test-DbaMigrationConstraint -Source sqlserver2014a -Destination sqlcluster

        All databases on sqlserver2014a will be verified for features in use that can't be supported on sqlcluster.

    .EXAMPLE
        PS C:\> Test-DbaMigrationConstraint -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        All databases will be verified for features in use that can't be supported on the destination server. SQL credentials are used to authenticate against sqlserver2014a and Windows Authentication is used for sqlcluster.

    .EXAMPLE
        PS C:\> Test-DbaMigrationConstraint -Source sqlserver2014a -Destination sqlcluster -Database db1

        Only db1 database will be verified for features in use that can't be supported on the destination server.

    #>
    [CmdletBinding(DefaultParameterSetName = "DbMigration")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstance]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )

    begin {
        <#
            1804890536 = Enterprise
            1872460670 = Enterprise Edition: Core-based Licensing
            610778273 = Enterprise Evaluation
            284895786 = Business Intelligence
            -2117995310 = Developer
            -1592396055 = Express
            -133711905= Express with Advanced Services
            -1534726760 = Standard
            1293598313 = Web
            1674378470 = SQL Database
        #>

        $editions = @{
            "Enterprise" = 10;
            "Developer"  = 10;
            "Evaluation" = 10;
            "Standard"   = 5;
            "Express"    = 1
        }
        $notesCanMigrate = "Database can be migrated."
        $notesCannotMigrate = "Database cannot be migrated."
    }
    process {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source -Continue
        }

        try {
            $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $Destination -Continue
        }

        if (-Not $Database) {
            $Database = $sourceServer.Databases | Where-Object IsSystemObject -eq 0 | Select-Object Name, Status
        }

        if ($ExcludeDatabase) {
            $Database = $sourceServer.Databases | Where-Object Name -NotIn $ExcludeDatabase
        }

        if ($Database.Count -gt 0) {
            if ($Database -in @("master", "msdb", "tempdb")) {
                Stop-Function -Message "Migrating system databases is not currently supported."
                return
            }

            if ($sourceServer.VersionMajor -lt 9 -and $destServer.VersionMajor -gt 10) {
                Stop-Function -Message "Sql Server 2000 databases cannot be migrated to SQL Server version 2012 and above. Quitting."
                return
            }

            if ($sourceServer.Collation -ne $destServer.Collation) {
                Write-Message -Level Warning -Message "Collation on $Source, $($sourceServer.collation) differs from the $Destination, $($destServer.collation)."
            }

            if ($sourceServer.VersionMajor -gt $destServer.VersionMajor) {
                #indicate they must use 'Generate Scripts' and 'Export Data' options?
                Stop-Function -Message "You can't migrate databases from a higher version to a lower one. Quitting."
                return
            }

            if ($sourceServer.VersionMajor -lt 10) {
                Stop-Function -Message "This function does not support versions lower than SQL Server 2008 (v10)"
                return
            }

            #if editions differs, from higher to lower one, verify the sys.dm_db_persisted_sku_features - only available from SQL 2008 +
            if (($sourceServer.VersionMajor -ge 10 -and $destServer.VersionMajor -ge 10)) {
                foreach ($db in $Database) {
                    if ([string]::IsNullOrEmpty($db.Status)) {
                        $dbstatus = ($sourceServer.Databases | Where-Object Name -eq $db).Status.ToString()
                        $dbName = $db
                    } else {
                        $dbstatus = $db.Status.ToString()
                        $dbName = $db.Name
                    }

                    Write-Message -Level Verbose -Message "Checking database '$dbName'."

                    if ($dbstatus.Contains("Offline") -eq $false -or $db.IsAccessible -eq $true) {

                        [long]$destVersionNumber = $($destServer.VersionString).Replace(".", "")
                        [string]$sourceVersion = "$($sourceServer.Edition) $($sourceServer.ProductLevel) ($($sourceServer.Version))"
                        [string]$destVersion = "$($destServer.Edition) $($destServer.ProductLevel) ($($destServer.Version))"
                        [string]$dbFeatures = ""

                        #Check if database has any FILESTREAM filegroup
                        Write-Message -Level Verbose -Message "Checking if FileStream is in use for database '$dbName'."
                        if ($sourceServer.Databases[$dbName].FileGroups | Where-Object FileGroupType -eq 'FileStreamDataFileGroup') {
                            Write-Message -Level Verbose -Message "Found FileStream filegroup and files."
                            $fileStreamSource = Get-DbaSpConfigure -SqlInstance $sourceServer -ConfigName FilestreamAccessLevel
                            $fileStreamDestination = Get-DbaSpConfigure -SqlInstance $destServer -ConfigName FilestreamAccessLevel

                            if ($fileStreamSource.RunningValue -ne $fileStreamDestination.RunningValue) {
                                [pscustomobject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $false
                                    Notes               = "$notesCannotMigrate. Destination server dones not have the 'FilestreamAccessLevel' configuration (RunningValue: $($fileStreamDestination.RunningValue)) equal to source server (RunningValue: $($fileStreamSource.RunningValue))."
                                }
                                Continue
                            }
                        }

                        try {
                            $sql = "SELECT feature_name FROM sys.dm_db_persisted_sku_features"

                            $skuFeatures = $sourceServer.Query($sql, $dbName)

                            Write-Message -Level Verbose -Message "Checking features in use..."

                            if (@($skuFeatures).Count -gt 0) {
                                foreach ($row in $skuFeatures) {
                                    $dbFeatures += ",$($row["feature_name"])"
                                }

                                $dbFeatures = $dbFeatures.TrimStart(",")
                            }
                        } catch {
                            Stop-Function -Message "Issue collecting sku features." -ErrorRecord $_ -Target $sourceServer -Continue
                        }

                        #If SQL Server 2016 SP1 (13.0.4001.0) or higher
                        if ($destVersionNumber -ge 13040010) {
                            <#
                                Need to verify if Edition = EXPRESS and database uses 'Change Data Capture' (CDC)
                                This means that database cannot be migrated because Express edition doesn't have SQL Server Agent
                            #>
                            if ($editions.Item($destServer.Edition.ToString().Split(" ")[0]) -eq 1 -and $dbFeatures.Contains("ChangeCapture")) {
                                [pscustomobject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $false
                                    Notes               = "$notesCannotMigrate. Destination server edition is EXPRESS which does not support 'ChangeCapture' feature that is in use."
                                }
                            } else {
                                [pscustomobject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $true
                                    Notes               = $notesCanMigrate
                                }
                            }
                        }
                        #Version is lower than SQL Server 2016 SP1
                        else {
                            Write-Message -Level Verbose -Message "Source Server Edition: $($sourceServer.Edition) (Weight: $($editions.Item($sourceServer.Edition.ToString().Split(" ")[0])))"
                            Write-Message -Level Verbose -Message "Destination Server Edition: $($destServer.Edition) (Weight: $($editions.Item($destServer.Edition.ToString().Split(" ")[0])))"

                            #Check for editions. If destination edition is lower than source edition and exists features in use
                            if (($editions.Item($destServer.Edition.ToString().Split(" ")[0]) -lt $editions.Item($sourceServer.Edition.ToString().Split(" ")[0])) -and (!([string]::IsNullOrEmpty($dbFeatures)))) {
                                [pscustomobject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $false
                                    Notes               = "$notesCannotMigrate There are features in use not available on destination instance."
                                }
                            }
                            #
                            else {
                                [pscustomobject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $true
                                    Notes               = $notesCanMigrate
                                }
                            }
                        }
                    } else {
                        Write-Message -Level Warning -Message "Database '$dbName' is offline or not accessible. Bring database online and re-run the command."
                    }
                }
            } else {
                #SQL Server 2005 or under
                Write-Message -Level Warning -Message "This validation will not be made on versions lower than SQL Server 2008 (v10)."
                Write-Message -Level Verbose -Message "Source server version: $($sourceServer.VersionMajor)."
                Write-Message -Level Verbose -Message "Destination server version: $($destServer.VersionMajor)."
            }
        } else {
            Write-Message -Level Output -Message "There are no databases to validate."
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU0gi9uWHWnzQMYifDkZAgXIAz
# MpKgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFBl64oqR8sS7T1KYp1suiuRItFTqMA0GCSqGSIb3DQEBAQUABIIBAD96qMJj
# lbQuK9miuXEteqBpAA1eWKAZNw7NuH38p6PRf/lgKRv/orwi8ch27jrFUaEohucn
# 7x4iMEqzTvM74ZOAg55pb5cd0BtPYuSrs5pGcNVFGCguiYFdU48tWAkEajm6T4eD
# VK5A4F0qQ8BGWMm724feUMSCtCBob81fdG/9Ez3wpI7c89ryyADr1LKs/ann5cVq
# Lq83QVk28MY+1gHPkkp7vJ5yetaRPpwPr/EuTYidLif+t1dHho/ZyWxRWhtzxzF0
# 0eZMcUnBW18tDTQYH6UXecEf+yPL15rpBGGahzdmZDtuaeEfFMNmupio5dUtqqbE
# 85HOoDe9596JRB6hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjYwM1owLwYJKoZIhvcNAQkEMSIEIBRJiczhUanlSfo62AmtiXucAMDr
# hNAXqBTTcUmY7pddMA0GCSqGSIb3DQEBAQUABIIBAGYbHT0vi6TKe17gAeWUEmgA
# DGuA2LIGb9bSrnxKpMxm7ymEbb/wMgXg3wTVZx299Lz6EA0HpnfOdMb3KegXCKmr
# myFLXhn8qaybpas81VLDfOHsIQ86h+R4Zt7nKlwrgEBUs/u6vljeS0vSHDbAGCgC
# BaFytEA89mYnQ8oOYVS+eLJpT3gyRh3dKgRn2BNTjOaN3LmUnBYdt2vPCqoy2uC6
# UJb1xqjARYDMVsfpWtmaAh16c4SSNj9j4W00VEgZj7DipbRYWgSK9FnhqqmvL83d
# SIBZFxXd/AnAsPeSqCJdb2mI4aMveduLGbPp/FHSvXkfi1WJA6CAEQbj9ro9/SQ=
# SIG # End signature block
