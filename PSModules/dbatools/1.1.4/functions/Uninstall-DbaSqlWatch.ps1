Function Uninstall-DbaSqlWatch {
    <#
    .SYNOPSIS
        Uninstalls SqlWatch.

    .DESCRIPTION
        Deletes all user objects, agent jobs, and historical data associated with SqlWatch.

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database to install SqlWatch into. Defaults to master.

    .PARAMETER Confirm
        Prompts to confirm actions

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, SqlWatch
        Author: Ken K (github.com/koglerk)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://sqlwatch.io

    .LINK
        https://dbatools.io/Uninstall-DbaSqlWatch

    .EXAMPLE
        Uninstall-DbaSqlWatch -SqlInstance server1

        Deletes all user objects, agent jobs, and historical data associated with SqlWatch from the master database.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database = "master",
        [switch]$EnableException
    )

    begin {

        # validate database parameter

        if (Test-Bound -Not -ParameterName 'DacfxPath') {
            $dacfxPath = "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Dac.dll"
        }

        if ((Test-Path $dacfxPath) -eq $false) {
            Stop-Function -Message 'No usable version of Dac Fx found.'
        } else {
            try {
                Add-Type -Path $dacfxPath
                Write-Message -Level Verbose -Message "Dac Fx loaded."
            } catch {
                Stop-Function -Message 'No usable version of Dac Fx found.' -ErrorRecord $_
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($PSEdition -eq 'Core') {
            Stop-Function -Message "PowerShell Core is not supported, please use Windows PowerShell."
            return
        }
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # get SqlWatch objects
            $tables = Get-DbaDbTable -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sqlwatch_*" -or $PSItem.Name -like "dbachecks*" -or $PSItem.Name -eq "__RefactorLog" } | Sort-Object $PSItem.createdate -Descending
            $views = Get-DbaDbView -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "vw_sqlwatch_*" } | Sort-Object $PSItem.createdate -Descending
            $sprocs = Get-DbaDbStoredProcedure -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "usp_sqlwatch_*" -or $PSItem.Name -like "Stream*" } | Sort-Object $PSItem.createdate -Descending
            $funcs = Get-DbaDbUdf -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "ufn_sqlwatch_*" -or $PSItem.Name -like "Get*" -or $PSItem.Name -like "Read*" -and $PSItem.Name -ne "ufn_sqlwatch_get_threshold_comparator" } | Sort-Object $PSItem.createdate
            $funcs += Get-DbaDbUdf -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -eq "ufn_sqlwatch_get_threshold_comparator" }
            $agentJobs = Get-DbaAgentJob -SqlInstance $server | Where-Object { $PSItem.Name -like "SqlWatch-*" }
            $XESessions = Get-DbaXESession -SqlInstance $server | Where-Object { $PSItem.Name -like "SQLWATCH_*" }
            $Assemblies = Get-DbaDbAssembly -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "SqlWatch*" }
            $TableTypes = Get-DbaDbUserDefinedTableType -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "utype_*" }
            $BrokerQueues = Get-DbaDbServiceBrokerQueue -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sqlwatch_*" }
            $BrokerServices = Get-DbaDbServiceBrokerService -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sqlwatch_*" }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch SQL Agent jobs")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SQL Agent jobs from $server."
                    $agentJobs | Remove-DbaAgentJob | Out-Null
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch Agent Jobs on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch stored procedures")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch stored procedures from $database on $server."
                    if ($sprocs) {
                        $sprocs | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch stored procedures from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch views")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch views from $database on $server."
                    if ($views) {
                        $views | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch views from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch functions")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch functions from $database on $server."
                    if ($funcs) {
                        $funcs | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch functions from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch tables")) {
                try {
                    Write-Message -Level Verbose -Message "Removing foreign keys from SqlWatch tables in $database on $server."
                    if ($tables.ForeignKeys) {
                        $tables.ForeignKeys | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all foreign keys from SqlWatch tables in $database on $server." -ErrorRecord $_ -Target $server -Continue
                }

                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch tables from $database on $server."
                    if ($tables) {
                        $tables | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch tables from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch Assemblies")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch assemblies from $database on $server."
                    if ($Assemblies) {
                        $Assemblies | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch assemblies from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch Table Types")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch Table Types from $database on $server."
                    if ($TableTypes) {
                        $TableTypes | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch Table Types from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch Service Broker Services")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch service broker services from $database on $server."
                    if ($BrokerServices) {
                        $BrokerServices | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch broker services from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch Service Broker Queues")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch service broker queues from $database on $server."
                    if ($BrokerQueues) {
                        $BrokerQueues | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch broker queues from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch XE Sessions")) {
                try {
                    if ($XESessions) {
                        Remove-DbaXESession -SqlInstance $Server -Session $XESessions.Name -Confirm:$false
                    }
                } catch {
                    Stop-Function -Message "Could not remove all XE Session for SqlWatch on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Unpublishing DACPAC")) {
                try {
                    Write-Message -Level Verbose -Message "Unpublishing SqlWatch DACPAC from $database on $server."
                    $connectionString = $server | Select-Object -ExpandProperty ConnectionContext
                    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connectionString
                    $dacServices.Unregister($Database)
                } catch {
                    Stop-Function -Message "Failed to unpublish SqlWatch DACPAC from $database on $server." -ErrorRecord $_
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU74+ljtv4frM6nWx0ueyO5HXw
# 3DGgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFO2wnM6zRedEZqWZ0YJ7s3ivPxadMA0GCSqGSIb3DQEBAQUABIIBABndOSiO
# RsHugu1nDYJf/gnClYIrKVknkIhkgDA/v4/kLZ4fVgNRrmUpnuRZ2QBiu8PQiW16
# 3MhcVaoQT7eyV8+mnus7zrJEgOI/HDRMklN6Vnvaj+v5pFBxTKBnssK+cMbWFPnE
# h4Wb+LI4BW8hiae4SL9K/eqKMfu65NOBCTrlIzhhvMExCccDsKdZCk4n/MNzIgX+
# r0EiUwcgqdC0fAwkl7946iSq0NJaHXbSxOShIUz37ro8I4TXUyrU+Lnk5//WImOd
# TQoTQfPwtGIx0CJC83ZOV+BN6ASPhjCq7En7VziE92De9xwqnfFupnGoiqubR+GO
# Gb/l4/7MIhaA3IuhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAxN1owLwYJKoZIhvcNAQkEMSIEICQZA6kxMKONOQeF7qjaTfnxyc35
# 5GF8f8Z40P0ABCzFMA0GCSqGSIb3DQEBAQUABIIBAAQFi9XZmdf6ubZ23Tz80wFy
# f/d4F4brNN9RLjS5bdIY4yjSMRXnQLxQqMymL8Xafq6thbgxJ0diW7sxmaNHc19f
# 47ROuRrB0OLV9ZgnPpkETgSkSzk7OvZfcNDlYWGDSM4dVteS8rsocJv1RRPEEs9W
# WuYar6QLG7ZTcSKL/LTeFxsa2TNuEv9A6vnI5X0OWNxlevFUnsGlTAbZTmmRe2ow
# iUcWDVQbyAKSQ2cZK4wR/Pl7V786WAR0vBhOqvJQHTcg9eziRSy/33U1881ZsJ5f
# isD1ensB4/FdXvwqE7vo3UOZFiFPVYH7zQLQvIAFDUXikFPma6RhxvCgzFRZxLk=
# SIG # End signature block
