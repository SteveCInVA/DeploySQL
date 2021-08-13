function Copy-DbaLinkedServer {
    <#
    .SYNOPSIS
        Copy-DbaLinkedServer migrates Linked Servers from one SQL Server to another. Linked Server logins and passwords are migrated as well.

    .DESCRIPTION
        By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Linked Servers from one server to another, while maintaining username and password.

        Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/

    .PARAMETER Source
        Source SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LinkedServer
        The linked server(s) to process - this list is auto-populated from the server. If unspecified, all linked servers will be processed.

    .PARAMETER ExcludeLinkedServer
        The linked server(s) to exclude - this list is auto-populated from the server

    .PARAMETER UpgradeSqlClient
        Upgrade any SqlClient Linked Server to the current version

    .PARAMETER ExcludePassword
        Copies the logins but does not access, decrypt or create sensitive information

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        By default, if a Linked Server exists on the source and destination, the Linked Server is not copied over. Specifying -force will drop and recreate the Linked Server on the Destination server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WSMan, Migration, LinkedServer
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers
        Limitations: This just copies the SQL portion. It does not copy files (i.e. a local SQLite database, or Microsoft Access DB), nor does it configure ODBC entries.

    .LINK
        https://dbatools.io/Copy-DbaLinkedServer

    .EXAMPLE
        PS C:\> Copy-DbaLinkedServer -Source sqlserver2014a -Destination sqlcluster

        Copies all SQL Server Linked Servers on sqlserver2014a to sqlcluster. If Linked Server exists on destination, it will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaLinkedServer -Source sqlserver2014a -Destination sqlcluster -LinkedServer SQL2K5,SQL2k -Force

        Copies over two SQL Server Linked Servers (SQL2K and SQL2K2) from sqlserver to sqlcluster. If the credential already exists on the destination, it will be dropped.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$LinkedServer,
        [object[]]$ExcludeLinkedServer,
        [switch]$UpgradeSqlClient,
        [switch]$ExcludePassword,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if (-not $script:isWindows) {
            Stop-Function -Message "Copy-DbaCredential is only supported on Windows"
            return
        }
        $null = Test-ElevationRequirement -ComputerName $Source.ComputerName

        if ($Force) { $ConfirmPreference = 'none' }

        function Copy-DbaLinkedServers {
            param (
                [string[]]$LinkedServer,
                [bool]$force
            )

            Write-Message -Level Verbose -Message "Collecting Linked Server logins and passwords on $($sourceServer.Name)."
            if ($ExcludePassword) {
                $sourcelogins = @()
                foreach ($svr in $sourceServer.LinkedServers) {
                    $sourcelogins += [pscustomobject]@{
                        Name     = $sourcelogin.Name
                        Identity = $sourcelogin.LinkedServerLogins.RemoteUser
                        Password = $null
                    }
                }
            } else {
                $sourcelogins = Get-DecryptedObject -SqlInstance $sourceServer -Type LinkedServer
            }

            $serverlist = $sourceServer.LinkedServers

            if ($LinkedServer) {
                $serverlist = $serverlist | Where-Object Name -In $LinkedServer
            }
            if ($ExcludeLinkedServer) {
                $serverList = $serverlist | Where-Object Name -NotIn $ExcludeLinkedServer
            }

            foreach ($currentLinkedServer in $serverlist) {
                $provider = $currentLinkedServer.ProviderName
                try {
                    $destServer.LinkedServers.Refresh()
                    $destServer.LinkedServers.LinkedServerLogins.Refresh()
                } catch {
                    #here to avoid an empty catch
                    $null = 1
                }

                $linkedServerName = $currentLinkedServer.Name
                $linkedServerProductName = $currentLinkedServer.ProductName
                $linkedServerDataSource = $currentLinkedServer.DataSource

                $copyLinkedServer = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $linkedServerName
                    ProductName       = $linkedServerProductName
                    DataSource        = $linkedServerDataSource
                    Type              = "Linked Server"
                    Status            = $null
                    Notes             = $provider
                    DateTime          = [DbaDateTime](Get-Date)
                }

                # This does a check to warn of missing OleDbProviderSettings but should only be checked on SQL on Windows
                if ($destServer.Settings.OleDbProviderSettings.Name.Length -ne 0) {
                    if (!$destServer.Settings.OleDbProviderSettings.Name -contains $provider -and !$provider.StartsWith("SQLN")) {
                        $copyLinkedServer.Status = "Skipped"
                        $copyLinkedServer.Notes = "Missing provider"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Write-Message -Level Verbose -Message "$($destServer.Name) does not support the $provider provider. Skipping $linkedServerName."
                        continue
                    }
                }

                if ($null -ne $destServer.LinkedServers[$linkedServerName]) {
                    if (!$force) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$linkedServerName exists $($destServer.Name). Skipping.")) {
                            $copyLinkedServer.Status = "Skipped"
                            $copyLinkedServer.Notes = "Already exists on destination"
                            $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "$linkedServerName exists $($destServer.Name). Skipping."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping $linkedServerName")) {
                            if ($currentLinkedServer.Name -eq 'repl_distributor') {
                                Write-Message -Level Verbose -Message "repl_distributor cannot be dropped. Not going to try."
                                continue
                            }

                            $destServer.LinkedServers[$linkedServerName].Drop($true)
                            $destServer.LinkedServers.refresh()
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Attempting to migrate: $linkedServerName."
                If ($Pscmdlet.ShouldProcess($destinstance, "Migrating $linkedServerName")) {
                    try {
                        $sql = $currentLinkedServer.Script() | Out-String
                        Write-Message -Level Debug -Message $sql

                        if ($UpgradeSqlClient -and $sql -match "sqlncli") {
                            $destProviders = $destServer.Settings.OleDbProviderSettings | Where-Object { $_.Name -like 'SQLNCLI*' }
                            $newProvider = $destProviders | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name

                            Write-Message -Level Verbose -Message "Changing sqlncli to $newProvider"
                            $sql = $sql -replace ("sqlncli[0-9]+", $newProvider)
                        }

                        $destServer.Query($sql)

                        if ($copyLinkedServer.ProductName -eq 'SQL Server' -and $copyLinkedServer.Name -ne $copyLinkedServer.DataSource) {
                            $sql2 = "EXEC sp_setnetname '$($copyLinkedServer.Name)', '$($copyLinkedServer.DataSource)'; "
                            $destServer.Query($sql2)
                        }

                        $destServer.LinkedServers.Refresh()
                        Write-Message -Level Verbose -Message "$linkedServerName successfully copied."

                        $copyLinkedServer.Status = "Successful"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyLinkedServer.Status = "Failed"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Issue adding linked server $destServer." -Target $linkedServerName -InnerErrorRecord $_
                        $skiplogins = $true
                    }
                }

                if ($skiplogins -ne $true) {
                    $destlogins = $destServer.LinkedServers[$linkedServerName].LinkedServerLogins
                    $lslogins = $sourcelogins | Where-Object { $_.Name -eq $linkedServerName }

                    foreach ($login in $lslogins) {
                        $currentlogin = $destlogins | Where-Object { $_.RemoteUser -eq $login.Identity }

                        $copyLinkedServer.Type = $login.Identity

                        if ($currentlogin.RemoteUser.length -ne 0) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Migrating linked server identity $($login.Identity)")) {
                                try {
                                    if ($login.Password) {
                                        $currentlogin.SetRemotePassword($login.Password)
                                        $currentlogin.Alter()
                                    }

                                    $copyLinkedServer.Status = "Successful"
                                    $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                } catch {
                                    $copyLinkedServer.Status = "Failed"
                                    $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                    Stop-Function -Message "Failed to copy login." -Target $login -InnerErrorRecord $_
                                }
                            }
                        }
                    }
                }
            }
        }

        if ($null -ne $SourceSqlCredential.Username) {
            Write-Message -Level Verbose -Message "You are using a SQL Credential. Note that this script requires Windows Administrator access on the source server. Attempting with $($SourceSqlCredential.Username)."
        }
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            return
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        if (!(Test-SqlSa -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $source. Quitting." -Target $sourceServer
            return
        }

        Write-Message -Level Verbose -Message "Checking if Remote Registry is enabled on $Source."
        $resolvedComputerName = Resolve-DbaComputerName -ComputerName $Source
        try {
            $null = Invoke-Command2 -ComputerName $resolvedComputerName -ScriptBlock { Get-ItemProperty -Path "HKLM:\SOFTWARE\" }
        } catch {
            Stop-Function -Message "Can't connect to registry on $Source." -Target $resolvedComputerName -ErrorRecord $_
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            if (!(Test-SqlSa -SqlInstance $destServer -SqlCredential $DestinationSqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $destinstance" -Target $destServer -Continue
            }

            # Magic happens here
            Copy-DbaLinkedServers $LinkedServer -Force:$force
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU5HCIR+SJTsPGXg8klGIlT//x
# nX+gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFEYCy4oE3bp1jqy0wt7O8BUw9nYJMA0GCSqGSIb3DQEBAQUABIIBAJAEmkPU
# ZZ+rIPIGds1dlQ50GO/TS1eCmPjg0jrgsCZhAf5VmvjRwwieyJWL0/IcfdKJATlF
# pK8w2sqXf7euhxzlT4AoQVkRs6ayAIzYr/h7ziuiNnDFmlIO5riq4dckWkn2zmSn
# ckXD+O1506DPTMNcCDi7Epe1iq5M9hcOAK7++3DtZpz/fH0zEdeEWLBvv5y3chkJ
# OD4P1ml+XSUpGUrfb9mS9O7OeDlLWWwcMkq8CctRIP7vR4kk7DHjNJSEn4FL6wwY
# SH0cWp3JlYM2Rl1yGPWorIoC4NEzei+g1hX+0JShlw+DeiR65ooQjA2BTHZWm+xL
# Fb81A5fOIhXlh+ShggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUwMFowLwYJKoZIhvcNAQkEMSIEIHiTMQgpn22xy4ZC+fXgxXBO4E/C
# 8a2R5E5YfxNt1nBEMA0GCSqGSIb3DQEBAQUABIIBAJMRCMe1n9W2XVQE/1BIs6E3
# S4YQlGxc8uU8UK+jMZwNJjz6Kae1d1bcAEXEZFatE7G2hxmIRr9OetHD17GnKl4L
# 4nZeQVT1LW9n/NTm9eZKko1ufa+a2bgeiNDH0OwVKck0ihdrdPCuVXDhMigsihbr
# hspmcFB8blBkMGR5p6T9kG65YH7oQd/f/p4bt8TbSEStbFh7V9idNQnLRg/wQMAI
# TxF42QzIUn/KjJOQiUEIb+ecuImYy00mdZzkfZ+Lb0Xn8yiWWI+fD5n00XIrVHea
# un5/0Hw+8bAbQ9Uh+yUmQGTJj59q27yByqjv+x/9WXEyEE7v2KStj+qYLWq8NZU=
# SIG # End signature block
