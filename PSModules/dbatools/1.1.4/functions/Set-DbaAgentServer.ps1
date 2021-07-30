function Set-DbaAgentServer {
    <#
    .SYNOPSIS
        Set-DbaAgentServer updates properties of a SQL Agent Server.

    .DESCRIPTION
        Set-DbaAgentServer updates properties in the SQL Server Server with parameters supplied.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Enables piping agent server objects

    .PARAMETER AgentLogLevel
        Specifies the agent log level.
        Allowed values 1, "Errors", 2, "Warnings", 3, "Errors, Warnings", 4, "Informational", 5, "Errors, Informational", 6, "Warnings, Informational", 7, "All"
        The text value can either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER AgentMailType
        Specifies the agent mail type.
        Allowed values 0, "SqlAgentMail", 1, "DatabaseMail"
        The text value can either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER AgentShutdownWaitTime
        The Agent Shutdown Wait Time value of the server agent. The accepted value range is between 5 and 600.

    .PARAMETER DatabaseMailProfile
        The Database Mail Profile to be used. Must exists on database mail profiles.

    .PARAMETER ErrorLogFile
        Error log file location

    .PARAMETER IdleCpuDuration
        Idle CPU Duration value to be used. The accepted value range is between 20 and 86400.

    .PARAMETER IdleCpuPercentage
        Idle CPU Percentage value to be used. The accepted value range is between 10 and 100.

    .PARAMETER CpuPolling
        Enable or Disable the Polling.
        Allowed values Enabled, Disabled

    .PARAMETER LocalHostAlias
        The value for Local Host Alias configuration

    .PARAMETER LoginTimeout
        The value for Login Timeout configuration. The accepted value range is between 5 and 45.

    .PARAMETER MaximumHistoryRows
        Indicates the Maximum job history log size (in rows). The acceptable value range is between 2 and 999999. To turn off the job history limitations use the value -1 and specify 0 for MaximumJobHistoryRows. See the example listed below.

    .PARAMETER MaximumJobHistoryRows
        Indicates the Maximum job history rows per job. The acceptable value range is between 2 and 999999. To turn off the job history limitations use the value 0 and specify -1 for MaximumHistoryRows. See the example listed below.

    .PARAMETER NetSendRecipient
        The Net send recipient value

    .PARAMETER ReplaceAlertTokens
        Enable or Disable the Token replacement property.
        Allowed values Enabled, Disabled

    .PARAMETER SaveInSentFolder
        Enable or Disable the copy of the sent messages is save in the Sent Items folder.
        Allowed values Enabled, Disabled

    .PARAMETER SqlAgentAutoStart
        Enable or Disable the SQL Agent Auto Start.
        Allowed values Enabled, Disabled

    .PARAMETER SqlAgentMailProfile
        The SQL Server Agent Mail Profile to be used. Must exists on database mail profiles.

    .PARAMETER SqlAgentRestart
        Enable or Disable the SQL Agent Restart.
        Allowed values Enabled, Disabled

    .PARAMETER SqlServerRestart
        Enable or Disable the SQL Server Restart.
        Allowed values Enabled, Disabled

    .PARAMETER WriteOemErrorLog
        Enable or Disable the Write OEM Error Log.
        Allowed values Enabled, Disabled

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Server
        Author: Cláudio Silva (@claudioessilva), https://claudioessilva.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentServer

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -MaximumHistoryRows 10000 -MaximumJobHistoryRows 100

        Changes the job history retention to 10000 rows with an maximum of 100 rows per job.

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -CpuPolling Enabled

        Enable the CPU Polling configurations.

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1, sql2, sql3 -AgentLogLevel 'Errors, Warnings'

        Set the agent log level to Errors and Warnings on multiple servers.

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -CpuPolling Disabled

        Disable the CPU Polling configurations.

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -MaximumJobHistoryRows 1000 -MaximumHistoryRows 10000

        Set the max history limitations. This is the equivalent to calling:  EXEC msdb.dbo.sp_set_sqlagent_properties @jobhistory_max_rows=10000, @jobhistory_max_rows_per_job=1000

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -MaximumJobHistoryRows 0 -MaximumHistoryRows -1

        Disable the max history limitations. This is the equivalent to calling:  EXEC msdb.dbo.sp_set_sqlagent_properties @jobhistory_max_rows=-1, @jobhistory_max_rows_per_job=0

    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.JobServer[]]$InputObject,
        [ValidateSet(1, "Errors", 2, "Warnings", 3, "Errors, Warnings", 4, "Informational", 5, "Errors, Informational", 6, "Warnings, Informational", 7, "All")]
        [object]$AgentLogLevel,
        [ValidateSet(0, "SqlAgentMail", 1, "DatabaseMail")]
        [object]$AgentMailType,
        [ValidateRange(5, 600)][int]$AgentShutdownWaitTime,
        [string]$DatabaseMailProfile,
        [string]$ErrorLogFile,
        [ValidateRange(20, 86400)][int]$IdleCpuDuration,
        [ValidateRange(10, 100)][int]$IdleCpuPercentage,
        [ValidateSet("Enabled", "Disabled")]
        [string]$CpuPolling,
        [string]$LocalHostAlias,
        [ValidateRange(5, 45)][int]$LoginTimeout,
        [int]$MaximumHistoryRows, # validated in the begin block
        [int]$MaximumJobHistoryRows, # validated in the begin block
        [string]$NetSendRecipient,
        [ValidateSet("Enabled", "Disabled")]
        [string]$ReplaceAlertTokens,
        [ValidateSet("Enabled", "Disabled")]
        [string]$SaveInSentFolder,
        [ValidateSet("Enabled", "Disabled")]
        [string]$SqlAgentAutoStart,
        [string]$SqlAgentMailProfile,
        [ValidateSet("Enabled", "Disabled")]
        [string]$SqlAgentRestart,
        [ValidateSet("Enabled", "Disabled")]
        [string]$SqlServerRestart,
        [ValidateSet("Enabled", "Disabled")]
        [string]$WriteOemErrorLog,
        [switch]$EnableException
    )

    begin {
        # Check of the agent mail type is of type string and set the integer value
        if (($AgentMailType -notin 0, 1) -and ($null -ne $AgentMailType)) {
            $AgentMailType = switch ($AgentMailType) { "SqlAgentMail" { 0 } "DatabaseMail" { 1 } }
        }

        # Check of the agent log level is of type string and set the integer value
        if (($AgentLogLevel -notin 0, 1) -and ($null -ne $AgentLogLevel)) {
            $AgentLogLevel = switch ($AgentLogLevel) { "Errors" { 1 } "Warnings" { 2 } "Errors, Warnings" { 3 } "Informational" { 4 } "Errors, Informational" { 5 } "Warnings, Informational" { 6 } "All" { 7 } }
        }

        if ($PSBoundParameters.ContainsKey("MaximumHistoryRows") -and ($MaximumHistoryRows -ne -1 -and $MaximumHistoryRows -notin 2..999999)) {
            Stop-Function -Message "You must specify a MaximumHistoryRows value of -1 (i.e. turn off max history) or a value between 2 and 999999. See the command description for examples."
            return
        }

        if ($PSBoundParameters.ContainsKey("MaximumJobHistoryRows") -and ($MaximumJobHistoryRows -ne 0 -and $MaximumJobHistoryRows -notin 2..999999)) {
            Stop-Function -Message "You must specify a MaximumJobHistoryRows value of 0 (i.e. turn off max history) or a value between 2 and 999999. See the command description for examples."
            return
        }
    }
    process {

        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $SqlInstance)) {
            Stop-Function -Message "You must specify an Instance or pipe in results from another command" -Target $SqlInstance
            return
        }

        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $InputObject += $server.JobServer
            $InputObject.Refresh()
        }

        foreach ($jobServer in $InputObject) {
            $server = $jobServer.Parent

            #region job server options
            # Settings the options for the job server
            if ($AgentLogLevel) {
                Write-Message -Message "Setting Agent log level to $AgentLogLevel" -Level Verbose
                $jobServer.AgentLogLevel = $AgentLogLevel
            }

            if ($AgentMailType) {
                Write-Message -Message "Setting Agent Mail Type to $AgentMailType" -Level Verbose
                $jobServer.AgentMailType = $AgentMailType
            }

            if ($AgentShutdownWaitTime) {
                Write-Message -Message "Setting Agent Shutdown Wait Time to $AgentShutdownWaitTime" -Level Verbose
                $jobServer.AgentShutdownWaitTime = $AgentShutdownWaitTime
            }

            if ($DatabaseMailProfile) {
                if ($DatabaseMailProfile -in (Get-DbaDbMail -SqlInstance $server).Profiles.Name) {
                    Write-Message -Message "Setting Database Mail Profile to $DatabaseMailProfile" -Level Verbose
                    $jobServer.DatabaseMailProfile = $DatabaseMailProfile
                } else {
                    Write-Message -Message "Database mail profile not found on $server" -Level Warning
                }
            }

            if ($ErrorLogFile) {
                Write-Message -Message "Setting agent server ErrorLogFile to $ErrorLogFile" -Level Verbose
                $jobServer.ErrorLogFile = $ErrorLogFile
            }

            if ($IdleCpuDuration) {
                Write-Message -Message "Setting agent server IdleCpuDuration to $IdleCpuDuration" -Level Verbose
                $jobServer.IdleCpuDuration = $IdleCpuDuration
            }

            if ($IdleCpuPercentage) {
                Write-Message -Message "Setting agent server IdleCpuPercentage to $IdleCpuPercentage" -Level Verbose
                $jobServer.IdleCpuPercentage = $IdleCpuPercentage
            }

            if ($CpuPolling) {
                Write-Message -Message "Setting agent server IsCpuPollingEnabled to $IsCpuPollingEnabled" -Level Verbose
                $jobServer.IsCpuPollingEnabled = if ($CpuPolling -eq "Enabled") { $true } else { $false }
            }

            if ($LocalHostAlias) {
                Write-Message -Message "Setting agent server LocalHostAlias to $LocalHostAlias" -Level Verbose
                $jobServer.LocalHostAlias = $LocalHostAlias
            }

            if ($LoginTimeout) {
                Write-Message -Message "Setting agent server LoginTimeout to $LoginTimeout" -Level Verbose
                $jobServer.LoginTimeout = $LoginTimeout
            }

            if ($MaximumHistoryRows) {
                Write-Message -Message "Setting agent server MaximumHistoryRows to $MaximumHistoryRows" -Level Verbose
                $jobServer.MaximumHistoryRows = $MaximumHistoryRows
            }

            if ($PSBoundParameters.ContainsKey("MaximumJobHistoryRows")) {
                Write-Message -Message "Setting agent server MaximumJobHistoryRows to $MaximumJobHistoryRows" -Level Verbose
                $jobServer.MaximumJobHistoryRows = $MaximumJobHistoryRows
            }

            if ($NetSendRecipient) {
                Write-Message -Message "Setting agent server NetSendRecipient to $NetSendRecipient" -Level Verbose
                $jobServer.NetSendRecipient = $NetSendRecipient
            }

            if ($ReplaceAlertTokens) {
                Write-Message -Message "Setting agent server ReplaceAlertTokensEnabled to $ReplaceAlertTokens" -Level Verbose
                $jobServer.ReplaceAlertTokensEnabled = if ($ReplaceAlertTokens -eq "Enabled") { $true } else { $false }
            }

            if ($SaveInSentFolder) {
                Write-Message -Message "Setting agent server SaveInSentFolder to $SaveInSentFolder" -Level Verbose
                $jobServer.SaveInSentFolder = if ($SaveInSentFolder -eq "Enabled") { $true } else { $false }
            }

            if ($SqlAgentAutoStart) {
                Write-Message -Message "Setting agent server SqlAgentAutoStart to $SqlAgentAutoStart" -Level Verbose
                $jobServer.SqlAgentAutoStart = if ($SqlAgentAutoStart -eq "Enabled") { $true } else { $false }
            }

            if ($SqlAgentMailProfile) {
                Write-Message -Message "Setting agent server SqlAgentMailProfile to $SqlAgentMailProfile" -Level Verbose
                $jobServer.SqlAgentMailProfile = $SqlAgentMailProfile
            }

            if ($SqlAgentRestart) {
                Write-Message -Message "Setting agent server SqlAgentRestart to $SqlAgentRestart" -Level Verbose
                $jobServer.SqlAgentRestart = if ($SqlAgentRestart -eq "Enabled") { $true } else { $false }
            }

            if ($SqlServerRestart) {
                Write-Message -Message "Setting agent server SqlServerRestart to $SqlServerRestart" -Level Verbose
                $jobServer.SqlServerRestart = if ($SqlServerRestart -eq "Enabled") { $true } else { $false }
            }

            if ($WriteOemErrorLog) {
                Write-Message -Message "Setting agent server WriteOemErrorLog to $WriteOemErrorLog" -Level Verbose
                $jobServer.WriteOemErrorLog = if ($WriteOemErrorLog -eq "Enabled") { $true } else { $false }
            }

            #endregion server agent options

            # Execute
            if ($PSCmdlet.ShouldProcess($SqlInstance, "Changing the agent server")) {
                try {
                    Write-Message -Message "Changing the agent server" -Level Verbose

                    # Change the agent server
                    $jobServer.Alter()
                } catch {
                    Stop-Function -Message "Something went wrong changing the agent server" -ErrorRecord $_ -Target $instance -Continue
                }

                Get-DbaAgentServer -SqlInstance $server | Where-Object Name -eq $jobServer.name
            }
        }
    }
    end {
        Write-Message -Message "Finished changing agent server(s)" -Level Verbose
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUMZp3uL48WPWz1T+a91zDYob9
# 7CegghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFOTu+CINKoOFuifx5Gh+SdP2gpRHMA0GCSqGSIb3DQEBAQUABIIBAI+eaFot
# SejQTtx9hmnLhnu57lM67G3Y39zDYvU+gE3lstUOWXFsbCqnybvY0rNIhKnnjfeu
# 1m4fVmc4mXF9Y0W0YJy/tKomsZ9BmQZNwHb7YepNIxxOb6m50Pjxa+S5GDUTAyrP
# GFzlJgRlkhuwVEm6VjH3zj0BCZ5vDd/pBbu+MU8c8xqXS1gPQ4tAphJpq1I+ViW7
# fgl+eHdVLp1qfWC1oot4f5GPmMrTe3otuoLhPqJU5AiezEPbIcz8ylcRUjjGncv1
# L9Muc1C3zb3qN9TxFyMmwacG8lcrm/+j5JNNpNgcRg8DmPU8j7pJNS07fGQ62Bx/
# Zc35+uZMzTTH52ehggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAwN1owLwYJKoZIhvcNAQkEMSIEIBwZpHyRWfT247Gx5t+NKZ8Fttxd
# 1Vlf9ky2j45WRbsLMA0GCSqGSIb3DQEBAQUABIIBAGfB1VkAiAf2xpDdzCfHCx15
# FrBVrCmZNsBf9wCZ4EvnNfAJ1A7pI/TXi0Lie2fpYW5ETPsudpdlqZPN/+QBMkL6
# 7iyT+tPTwfo758eJOacs84Q8ilZJD7OAvg5b9nG1yDP5gYZt9ZLuiaZv8lYQaO7f
# rwNK3gRHPUpXsdxkCAI/wT6HUe8tgcujVoLUUdB1YreIp6vYcSKXmleukHrOcdhe
# twUKS1cQ+329V/d1wlR+mvgs0FKTBuf+afvGx9VPWPzDD9rh0a88gmuUVMxZnt5s
# b6QIGDvAe8WXu6O7sN+okFiSNRwgRyhRwRrifNAv4E0cnJIQ84d8HbW4YAC3ZGw=
# SIG # End signature block
