function Repair-DbaInstanceName {
    <#
    .SYNOPSIS
        Renames @@SERVERNAME to match with the Windows name.

    .DESCRIPTION
        When a SQL Server's host OS is renamed, the SQL Server should be as well. This helps with Availability Groups and Kerberos.

        This command renames @@SERVERNAME to match with the Windows name. The new name is automatically determined. It does not matter if you use an alias to connect to the SQL instance.

        If the automatically determined new name matches the old name, the command will not run.

        https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AutoFix
        If this switch is enabled, the repair will be performed automatically.

    .PARAMETER Force
        If this switch is enabled, most confirmation prompts will be skipped.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: SPN
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Repair-DbaInstanceName

    .EXAMPLE
        PS C:\> Repair-DbaInstanceName -SqlInstance sql2014

        Checks to see if the server name is updatable and changes the name with a number of prompts.

    .EXAMPLE
        PS C:\> Repair-DbaInstanceName -SqlInstance sql2014 -AutoFix

        Checks to see if the server name is updatable and automatically performs the change. Replication or mirroring will be broken if necessary.

    .EXAMPLE
        PS C:\> Repair-DbaInstanceName -SqlInstance sql2014 -AutoFix -Force

        Checks to see if the server name is updatable and automatically performs the change, bypassing most prompts and confirmations. Replication or mirroring will be broken if necessary.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$AutoFix,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.isClustered) {
                Write-Message -Level Warning -Message "$instance is a cluster. Microsoft does not support renaming clusters."
                continue
            }


            # Check to see if we can easily proceed

            $nametest = Test-DbaInstanceName -SqlInstance $server
            $oldServerName = $nametest.ServerName
            $newServerName = $nametest.NewServerName

            if ($nametest.RenameRequired -eq $false) {
                Stop-Function -Continue -Message "Good news! $oldServerName's @@SERVERNAME does not need to be changed. If you'd like to rename it, first rename the Windows server."
            }

            if (-not $nametest.Updatable) {
                Write-Message -Level Output -Message "Test-DbaInstanceName reports that the rename cannot proceed with a rename in this $instance's current state."

                foreach ($nametesterror in $nametest.Blockers) {
                    if ($nametesterror -like '*replication*') {

                        if (-not $AutoFix) {
                            Stop-Function -Message "Cannot proceed because some databases are involved in replication. You can run exec sp_dropdistributor @no_checks = 1 but that may be pretty dangerous. Alternatively, you can run -AutoFix to automatically fix this issue. AutoFix will also break all database mirrors."
                            return
                        } else {
                            if ($Pscmdlet.ShouldProcess("console", "Prompt will appear for confirmation to break replication.")) {
                                $title = "You have chosen to AutoFix the blocker: replication."
                                $message = "We can run sp_dropdistributor which will pretty much destroy replication on this server. Do you wish to continue? (Y/N)"
                                $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                                $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 1)

                                if ($result -eq 1) {
                                    Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -Continue
                                } else {
                                    Write-Message -Level Output -Message "`nPerforming sp_dropdistributor @no_checks = 1."
                                    $sql = "sp_dropdistributor @no_checks = 1"
                                    Write-Message -Level Debug -Message $sql
                                    try {
                                        $null = $server.Query($sql)
                                    } catch {
                                        Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -Continue
                                    }
                                }
                            }
                        }
                    } elseif ($Error -like '*mirror*') {
                        if ($AutoFix -eq $false) {
                            Stop-Function -Message "Cannot proceed because some databases are being mirrored. Stop mirroring to proceed. Alternatively, you can run -AutoFix to automatically fix this issue. AutoFix will also stop replication." -Continue
                        } else {
                            if ($Pscmdlet.ShouldProcess("console", "Prompt will appear for confirmation to break replication.")) {
                                $title = "You have chosen to AutoFix the blocker: mirroring."
                                $message = "We can run sp_dropdistributor which will pretty much destroy replication on this server. Do you wish to continue? (Y/N)"
                                $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                                $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 1)

                                if ($result -eq 1) {
                                    Write-Message -Level Output -Message "Okay, moving on."
                                } else {
                                    Write-Message -Level Verbose -Message "Removing Mirroring"

                                    foreach ($database in $server.Databases) {
                                        if ($database.IsMirroringEnabled) {
                                            $dbName = $database.name

                                            try {
                                                Write-Message -Level Verbose -Message "Breaking mirror for $dbName."
                                                $database.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                                                $database.Alter()
                                                $database.Refresh()
                                            } catch {
                                                Stop-Function -Message "Failure" -Target $server -ErrorRecord $_
                                                return
                                                #throw "Could not break mirror for $dbName. Skipping."
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            # ^ That's embarrassing

            $instanceName = $server.InstanceName

            if (-not $instanceName) {
                $instanceName = "MSSQLSERVER"
            }

            try {
                $allsqlservices = Get-Service -ComputerName $instance.ComputerName -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "SQL*$instanceName*" -and $_.Status -eq "Running" }
            } catch {
                Write-Message -Level Warning -Message "Can't contact $instance using Get-Service. This means the script will not be able to automatically restart SQL services."
            }

            if ($nametest.Warnings -ne 'N/A') {
                $reportingservice = Get-Service -ComputerName $instance.ComputerName -DisplayName "SQL Server Reporting Services ($instanceName)" -ErrorAction SilentlyContinue

                if ($reportingservice.Status -eq "Running") {
                    if ($Pscmdlet.ShouldProcess($server.name, "Reporting Services is running for this instance. Would you like to automatically stop this service?")) {
                        $reportingservice | Stop-Service
                        Write-Message -Level Warning -Message "You must reconfigure Reporting Services using Reporting Services Configuration Manager or PowerShell once the server has been successfully renamed."
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($server.name, "Performing sp_dropserver to remove the old server name, $oldServerName, then sp_addserver to add $newServerName")) {
                $sql = "sp_dropserver '$oldServerName'"
                Write-Message -Level Debug -Message $sql
                try {
                    $null = $server.Query($sql)
                } catch {
                    Stop-Function -Message "Failure" -Target $server -ErrorRecord $_
                    return
                }

                $sql = "sp_addserver '$newServerName', local"
                Write-Message -Level Debug -Message $sql

                try {
                    $null = $server.Query($sql)
                } catch {
                    Stop-Function -Message "Failure" -Target $server -ErrorRecord $_
                    return
                }
                $renamed = $true
            }

            if ($null -eq $allsqlservices) {
                Write-Message -Level Warning -Message "Could not contact $($instance.ComputerName) using Get-Service. You must manually restart the SQL Server instance."
                $needsrestart = $true
            } else {
                if ($Pscmdlet.ShouldProcess($instance.ComputerName, "Rename complete! The SQL Service must be restarted to commit the changes. Would you like to restart the $instanceName instance now?")) {
                    try {
                        Write-Message -Level Verbose -Message "Stopping SQL Services for the $instanceName instance"
                        $allsqlservices | Stop-Service -Force -WarningAction SilentlyContinue # because it reports the wrong name
                        Write-Message -Level Verbose -Message "Starting SQL Services for the $instanceName instance."
                        $allsqlservices | Where-Object { $_.DisplayName -notlike "*reporting*" } | Start-Service -WarningAction SilentlyContinue # because it reports the wrong name
                    } catch {
                        Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -Continue
                    }
                }
            }

            if ($renamed -eq $true) {
                Write-Message -Level Verbose -Message "$instance successfully renamed from $oldServerName to $newServerName."
                Test-DbaInstanceName -SqlInstance $instance -SqlCredential $SqlCredential
            }

            if ($needsrestart -eq $true) {
                Write-Message -Level Warning -Message "SQL Service restart for $newServerName still required."
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUn4PWCkOSiXlmrnNMZ230soRW
# wK+gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFNULTmPwiUtdTzY//+03kk8NS1cUMA0GCSqGSIb3DQEBAQUABIIBAEFGZxpt
# jjaDSr/616nyYeiA2Js9ICZVRdZh0AuhT2udnZIWMp3KhjFkbleRO+38XrYsSCWE
# hhja9GVAdSEhfE1JW+bw/oQ6SfystLXZ+NSgpeK6MVOLvk0UgIuvdXhjwwG4SUV5
# /1PHDNcblhD1kTWmwIQfm/narSMXKvoLSlRoXiucs2G4mbdPYe5HRPCeiykc0Fd0
# 2kgLyL+ESWsnRZmBOx3SErzioO0nwkxSDCOutUcrmNoyGVKgOp+UwyTXTpLG8GVt
# yO9oDbCGQ9L3rGg0RR1cGi7Kmof1qN+tzTIkVv9mgJFNpgP9ig/eGaJpadwSRo89
# qxty8ip4/0yGnPqhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAwNVowLwYJKoZIhvcNAQkEMSIEIC4XdD1y3CWMPqwFN5ke3MlTTW7/
# oi5tilCBXVpbxRoFMA0GCSqGSIb3DQEBAQUABIIBABZDkLMmzdjvf1Jfue3tBi5g
# dlKIpHV1rqjG17+gzzxq+tME4xpOY5gdrZapmtLn/AlRl0aS44NfyL5VizKVDOKu
# CqNGvHDRF/Fed9jALA3TCjDgf3kduSZUbsNgt6b7EArNMm8ZOTMYKqaC7ZD2WEWc
# xkKqU9fIfXTmqCATofXZ8cNDXJSYAn8SaE92431sKmYdmWwoDsfSVTtV3K6rSzN6
# 84j4YWZcj4qk/7sKuCEUsoT3Oa2hxpZFfjuPGVxvpWDBGXnwI6oj1SJdpe9UNEgT
# qXiAH3+AOE582FZ1s4ZhHoZMrD3N5SiiCTLDYGC/s9jXGm7OJu7aL2u5G3Ek1t4=
# SIG # End signature block
