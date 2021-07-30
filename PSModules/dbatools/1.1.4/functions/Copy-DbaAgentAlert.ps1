function Copy-DbaAgentAlert {
    <#
    .SYNOPSIS
        Copy-DbaAgentAlert migrates alerts from one SQL Server to another.

    .DESCRIPTION
        By default, all alerts are copied. The -Alert parameter is auto-populated for command-line completion and can be used to copy only specific alerts.

        If the alert already exists on the destination, it will be skipped unless -Force is used.

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

    .PARAMETER Alert
        The alert(s) to process. This list is auto-populated from the server. If unspecified, all alerts will be processed.

    .PARAMETER ExcludeAlert
        The alert(s) to exclude. This list is auto-populated from the server.

    .PARAMETER IncludeDefaults
        Copy SQL Agent defaults such as FailSafeEmailAddress, ForwardingServer, and PagerSubjectTemplate.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Alert will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Agent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaAgentAlert

    .EXAMPLE
        PS C:\> Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster

        Copies all alerts from sqlserver2014a to sqlcluster using Windows credentials. If alerts with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster -Alert PSAlert -SourceSqlCredential $cred -Force

        Copies a only the alert named PSAlert from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an alert with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Alert,
        [object[]]$ExcludeAlert,
        [switch]$IncludeDefaults,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            $serverAlerts = $sourceServer.JobServer.Alerts
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destAlerts = $destServer.JobServer.Alerts

            if ($IncludeDefaults -eq $true) {
                if ($PSCmdlet.ShouldProcess($destinstance, "Creating Alert Defaults")) {
                    $copyAgentAlertStatus = [pscustomobject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Name              = "Alert Defaults"
                        Type              = "Alert Defaults"
                        Status            = $null
                        Notes             = $null
                        DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                    }
                    try {
                        Write-Message -Message "Creating Alert Defaults" -Level Verbose
                        $sql = $sourceServer.JobServer.AlertSystem.Script() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"

                        Write-Message -Message $sql -Level Debug
                        $null = $destServer.Query($sql)

                        $copyAgentAlertStatus.Status = "Successful"
                    } catch {
                        $copyAgentAlertStatus.Status = "Failed"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue creating alert defaults." -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue
                    }
                    $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }

            $destServerOperators = $destServer.JobServer.Operators

            foreach ($serverAlert in $serverAlerts) {
                $alertName = $serverAlert.name
                $copyAgentAlertStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $alertName
                    Type              = "Agent Alert"
                    Notes             = $null
                    Status            = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }
                if (($Alert -and $Alert -notcontains $alertName) -or ($ExcludeAlert -and $ExcludeAlert -contains $alertName)) {
                    continue
                }

                if ($serverAlert.HasNotification) {
                    $alertOperators = $serverAlert.EnumNotifications()
                    if ($destServerOperators.Name -notin $alertOperators.OperatorName) {
                        $missingOperators = ($alertOperators | Where-Object OperatorName -NotIn $destServerOperators.Name).OperatorName
                        if ($missingOperators.Count -gt 0 -or $missingOperators.Length -gt 0) {
                            $operatorList = $missingOperators -join ','
                            if ($PSCmdlet.ShouldProcess($destinstance, "Missing operator(s) at destination.")) {
                                $copyAgentAlertStatus.Status = "Skipped"
                                $copyAgentAlertStatus.Notes = "Operator(s) [$operatorList] do not exist on destination"
                                $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Message "One or more operators alerted by [$alertName] is not present at the destination. Alert will not be copied. Use Copy-DbaAgentOperator to copy the operator(s) to the destination. Missing operator(s): $operatorList" -Level Warning
                                continue
                            }
                        }
                    }
                }

                if ($destAlerts.name -contains $serverAlert.name) {
                    if ($force -eq $false) {
                        if ($PSCmdlet.ShouldProcess($destinstance, "Alert [$alertName] exists at destination. Use -Force to drop and migrate.")) {
                            $copyAgentAlertStatus.Status = "Skipped"
                            $copyAgentAlertStatus.Notes = "Already exists on destination"
                            $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Message "Alert [$alertName] exists at destination. Use -Force to drop and migrate." -Level Verbose
                        }
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($destinstance, "Dropping alert $alertName and recreating")) {
                        try {
                            Write-Message -Message "Dropping Alert $alertName on $destServer." -Level Verbose

                            $sql = "EXEC msdb.dbo.sp_delete_alert @name = N'$($alertname)';"
                            Write-Message -Message $sql -Level Debug
                            $null = $destServer.Query($sql)
                            $destAlerts.Refresh()
                        } catch {
                            $copyAgentAlertStatus.Status = "Failed"
                            $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue dropping/recreating alert" -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue
                        }
                    }
                }

                if ($destAlerts | Where-Object { $_.Severity -eq $serverAlert.Severity -and $_.MessageID -eq $serverAlert.MessageID -and $_.DatabaseName -eq $serverAlert.DatabaseName -and $_.EventDescriptionKeyword -eq $serverAlert.EventDescriptionKeyword }) {
                    if ($PSCmdlet.ShouldProcess($destinstance, "Checking for conflicts")) {
                        $conflictMessage = "Alert [$alertName] has already been defined to use"
                        if ($serverAlert.Severity -gt 0) { $conflictMessage += " severity $($serverAlert.Severity)" }
                        if ($serverAlert.MessageID -gt 0) { $conflictMessage += " error number $($serverAlert.MessageID)" }
                        if ($serverAlert.DatabaseName) { $conflictMessage += " on database '$($serverAlert.DatabaseName)'" }
                        if ($serverAlert.EventDescriptionKeyword) { $conflictMessage += " with error text '$($serverAlert.Severity)'" }
                        $conflictMessage += ". Skipping."

                        Write-Message -Level Verbose -Message $conflictMessage
                        $copyAgentAlertStatus.Status = "Skipped"
                        $copyAgentAlertStatus.Notes = $conflictMessage
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }
                if ($serverAlert.JobName -and $destServer.JobServer.Jobs.Name -NotContains $serverAlert.JobName) {
                    Write-Message -Level Verbose -Message "Alert [$alertName] has job [$($serverAlert.JobName)] configured as response. The job does not exist on destination $destServer. Skipping."
                    if ($PSCmdlet.ShouldProcess($destinstance, "Checking for conflicts")) {
                        $copyAgentAlertStatus.Status = "Skipped"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if ($PSCmdlet.ShouldProcess($destinstance, "Creating Alert $alertName")) {
                    try {
                        Write-Message -Message "Copying Alert $alertName" -Level Verbose
                        $sql = $serverAlert.Script() | Out-String
                        $sql = $sql -replace "@job_id=N'........-....-....-....-............", "@job_id=N'00000000-0000-0000-0000-000000000000"

                        Write-Message -Message $sql -Level Debug
                        $null = $destServer.Query($sql)

                        $copyAgentAlertStatus.Status = "Successful"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyAgentAlertStatus.Status = "Failed"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue creating alert" -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue
                    }
                }

                $destServer.JobServer.Alerts.Refresh()
                $destServer.JobServer.Jobs.Refresh()

                $newAlert = $destServer.JobServer.Alerts[$alertName]
                $notifications = $serverAlert.EnumNotifications()
                $jobName = $serverAlert.JobName

                # JobId = 00000000-0000-0000-0000-000 means the Alert does not execute/is attached to a SQL Agent Job.
                if ($serverAlert.JobId -ne '00000000-0000-0000-0000-000000000000') {
                    $copyAgentAlertStatus = [pscustomobject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Name              = $alertName
                        Type              = "Agent Alert Job Association"
                        Notes             = "Associated with $jobName"
                        Status            = $null
                        DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                    }
                    if ($PSCmdlet.ShouldProcess($destinstance, "Adding $alertName to $jobName")) {
                        try {
                            <# THERE needs to be validation within this block to see if the $jobName actually exists on the source server. #>
                            Write-Message -Message "Adding $alertName to $jobName" -Level Verbose
                            $newJob = $destServer.JobServer.Jobs[$jobName]
                            $newJobId = ($newJob.JobId) -replace " ", ""
                            $sql = $sql -replace '00000000-0000-0000-0000-000000000000', $newJobId
                            $sql = $sql -replace 'sp_add_alert', 'sp_update_alert'

                            Write-Message -Message $sql -Level Debug
                            $null = $destServer.Query($sql)

                            $copyAgentAlertStatus.Status = "Successful"
                            $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        } catch {
                            $copyAgentAlertStatus.Status = "Failed"
                            $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue adding alert to job" -Category InvalidOperation -ErrorRecord $_ -Target $destServer
                        }
                    }
                }

                if ($PSCmdlet.ShouldProcess($destinstance, "Moving Notifications $alertName")) {
                    try {
                        $copyAgentAlertStatus = [pscustomobject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Name              = $alertName
                            Type              = "Agent Alert Notification"
                            Notes             = $null
                            Status            = $null
                            DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                        }
                        # can't add them this way, we need to modify the existing one or give all options that are supported.
                        foreach ($notify in $notifications) {
                            $notifyCollection = @()
                            if ($notify.UseNetSend -eq $true) {
                                Write-Message -Message "Adding net send" -Level Verbose
                                $notifyCollection += "NetSend"
                            }

                            if ($notify.UseEmail -eq $true) {
                                Write-Message -Message "Adding email" -Level Verbose
                                $notifyCollection += "NotifyEmail"
                            }

                            if ($notify.UsePager -eq $true) {
                                Write-Message -Message "Adding pager" -Level Verbose
                                $notifyCollection += "Pager"
                            }

                            $notifyMethods = $notifyCollection -join ", "
                            $newAlert.AddNotification($notify.OperatorName, [Microsoft.SqlServer.Management.Smo.Agent.NotifyMethods]$notifyMethods)
                        }
                        $copyAgentAlertStatus.Status = "Successful"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyAgentAlertStatus.Status = "Failed"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue moving notifications for the alert" -Category InvalidOperation -ErrorRecord $_ -Target $destServer
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU13UexwJK+4CsZtp28cd/dVkr
# ZG6gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFEkedaXH1PqXxYy7VZNPmarplepQMA0GCSqGSIb3DQEBAQUABIIBAAiVonxJ
# BlbbUAmHb7cKF8QLFTRskQDCfWfSaHwUgfJ6tGmv2rYk0d74mYf43XgTxDhqbqKo
# KF+aCa7vwxtgriTdsbym2NS/8I5+j0D0PDta+ZDGKvk9w3cdpj3U8XdwoC8EskAh
# tRlWxQggWZViT+lLltFCaSlUAMnYeaSYXlHObdHgmA7imA+9832vetvzNlv7bmSw
# awpIl5XwWyO4k12Hl//dVCVpu108NBCC6uG8MIMktFCjbkwl5sV/WQd/LSTmX1wx
# JmB2iDbhBkBLa5V1jaFarAvirI29LtnJaSoUH2Q4z6KN2EW/xd07Fjyl8wVBz97e
# zHDD/YQfmARB0K+hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkxNVowLwYJKoZIhvcNAQkEMSIEIOqsMPjGZ/huNV8rNdj3zeH/xaw+
# uRqrQQy3EbIcVOrGMA0GCSqGSIb3DQEBAQUABIIBAE3lNEeduQ/CVUlrGBpQyPNd
# WazKBpWTdruCvnN1kNyIA02yhbvKtD5TnaTwfHbM4v0GMqFYYerEzHrfEqMz+jBs
# G40f8AUuK5UD0fvDn5B7xNgZLLnLwE8+HrTCEbbY/JmdhVaxJNVmFMGt7TWJNyPo
# ePzsBY7p9aJGf7VLLEs2jL4l+EwcENLRrJfkdj5E3FJYLf1Xj9WG3vV2RSLUGexz
# sZGMNlOcWCugE04gEwE7Q/dipdEkFJ4o5Jl/7ZcedNhpZZ2EwtkuU21aA7YkuPrr
# rxK3iI0wvmwItbrYoY2VEwBR6V3ScH2whQPJkBJ46OujOJ0CRR9ZLURSylwQdww=
# SIG # End signature block
