function Sync-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Syncs dependent objects such as jobs, logins and custom errors for availability groups

    .DESCRIPTION
        Syncs dependent objects for availability groups. Such objects include:

        SpConfigure
        CustomErrors
        Credentials
        DatabaseMail
        LinkedServers
        Logins
        LoginPermissions
        SystemTriggers
        DatabaseOwner
        AgentCategory
        AgentOperator
        AgentAlert
        AgentProxy
        AgentSchedule
        AgentJob

        Note that any of these can be excluded. For specific object exclusions (such as a single job), using the underlying Copy-Dba* command will be required.

        This command does not filter by which logins are in use by the ag databases or which linked servers are used. All objects that are not excluded will be copied like hulk smash.

    .PARAMETER Primary
        The primary SQL Server instance. Server version must be SQL Server version 2012 or higher.

    .PARAMETER PrimarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Secondary
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        The name of the Availability Group.

    .PARAMETER Exclude
        Exclude one or more objects to export

        SpConfigure
        CustomErrors
        Credentials
        DatabaseMail
        LinkedServers
        Logins
        LoginPermissions
        SystemTriggers
        DatabaseOwner
        AgentCategory
        AgentOperator
        AgentAlert
        AgentProxy
        AgentSchedule
        AgentJob

    .PARAMETER Login
        Specific logins to sync. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
        Specific logins to exclude when performing the sync. If unspecified, all logins will be processed.

    .PARAMETER Job
        Specific jobs to sync. If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        Specific jobs to exclude when performing the sync. If unspecified, all jobs will be processed.

    .PARAMETER DisableJobOnDestination
        If this switch is enabled, the newly migrated job will be disabled on the destination server.

    .PARAMETER InputObject
        Enables piping from Get-DbaAvailabilityGroup.

    .PARAMETER Force
        If this switch is enabled, the objects will dropped and recreated on Destination.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Sync-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> Sync-DbaAvailabilityGroup -Primary sql2016a -AvailabilityGroup db3

        Syncs the following on all replicas found in the db3 AG:
        SpConfigure, CustomErrors, Credentials, DatabaseMail, LinkedServers
        Logins, LoginPermissions, SystemTriggers, DatabaseOwner, AgentCategory,
        AgentOperator, AgentAlert, AgentProxy, AgentSchedule, AgentJob

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016a | Sync-DbaAvailabilityGroup -ExcludeType LoginPermissions, LinkedServers -ExcludeLogin login1, login2 -Job job1, job2

        Syncs the following on all replicas found in all AGs on the specified instance:
        SpConfigure, CustomErrors, Credentials, DatabaseMail, Logins,
        SystemTriggers, DatabaseOwner, AgentCategory, AgentOperator
        AgentAlert, AgentProxy, AgentSchedule, AgentJob.

        Copies all logins except for login1 and login2 and only syncs job1 and job2

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016a | Sync-DbaAvailabilityGroup -WhatIf

        Shows what would happen if the command were to run but doesn't actually perform the action.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
        [string]$AvailabilityGroup,
        [Alias("ExcludeType")]
        [ValidateSet('AgentCategory', 'AgentOperator', 'AgentAlert', 'AgentProxy', 'AgentSchedule', 'AgentJob', 'Credentials', 'CustomErrors', 'DatabaseMail', 'DatabaseOwner', 'LinkedServers', 'Logins', 'LoginPermissions', 'SpConfigure', 'SystemTriggers')]
        [string[]]$Exclude,
        [string[]]$Login,
        [string[]]$ExcludeLogin,
        [string[]]$Job,
        [string[]]$ExcludeJob,
        [switch]$DisableJobOnDestination,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $allcombos = @()
    }
    process {
        if (Test-Bound -Not Primary, InputObject) {
            Stop-Function -Message "You must supply either -Primary or an Input Object"
            return
        }

        if (-not $AvailabilityGroup -and -not $Secondary -and -not $InputObject) {
            Stop-Function -Message "You must specify a secondary or an availability group."
            return
        }

        if ($InputObject) {
            $server = $InputObject.Parent
        } else {
            try {
                $server = Connect-SqlInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $Primary" -Category ConnectionError -ErrorRecord $_ -Target $Primary
                return
            }
        }

        if ($AvailabilityGroup) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $AvailabilityGroup
        }

        if ($InputObject) {
            $Secondary += (($InputObject.AvailabilityReplicas | Where-Object Name -ne $server.DomainInstanceName).Name | Select-Object -Unique)
        }

        if ($Secondary) {
            $Secondary = $Secondary | Sort-Object
            $secondaries = @()
            foreach ($computer in $Secondary) {
                try {
                    $secondaries += Connect-SqlInstance -SqlInstance $computer -SqlCredential $SecondarySqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $computer" -Category ConnectionError -ErrorRecord $_ -Target $Primary
                    return
                }
            }
        }

        $thiscombo = [pscustomobject]@{
            PrimaryServer   = $server
            SecondaryServer = $secondaries
        }

        # In the event that someone pipes in an availability group, this will keep the sync from running a bunch of times
        $dupe = $false

        foreach ($ag in $allcombos) {
            if ($ag.PrimaryServer.Name -eq $thiscombo.PrimaryServer.Name -and
                $ag.SecondaryServer.Name.ToString() -eq $thiscombo.SecondaryServer.Name.ToString()) {
                $dupe = $true
            }
        }

        if ($dupe -eq $false) {
            $allcombos += $thiscombo
        }
    }

    end {
        if (Test-FunctionInterrupt) { return }

        # now that all combinations have been figured out, begin sync without duplicating work
        foreach ($ag in $allcombos) {
            $server = $ag.PrimaryServer
            $secondaries = $ag.SecondaryServer

            $stepCounter = 0
            $activity = "Syncing availability group $AvailabilityGroup"

            if (-not $secondaries) {
                Stop-Function -Message "No secondaries found."
                return
            }

            $primaryserver = $server.Name
            $secondaryservers = $secondaries.Name -join ", "

            if ($Exclude -notcontains "SpConfigure") {
                if ($PSCmdlet.ShouldProcess("Syncing SQL Server Configuration from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing SQL Server Configuration"
                    Copy-DbaSpConfigure -Source $server -Destination $secondaries
                }
            }

            if ($Exclude -notcontains "Logins") {
                if ($PSCmdlet.ShouldProcess("Syncing logins from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing logins"
                    Copy-DbaLogin -Source $server -Destination $secondaries -Login $Login -ExcludeLogin $ExcludeLogin -Force:$Force
                }
            }

            if ($Exclude -notcontains "DatabaseOwner") {
                if ($PSCmdlet.ShouldProcess("Updating database owners to match newly migrated logins from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Updating database owners to match newly migrated logins"
                    foreach ($sec in $secondaries) {
                        $null = Update-SqlDbOwner -Source $server -Destination $sec
                    }
                }
            }

            if ($Exclude -notcontains "CustomErrors") {
                if ($PSCmdlet.ShouldProcess("Syncing custom errors (user defined messages) from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing custom errors (user defined messages)"
                    Copy-DbaCustomError -Source $server -Destination $secondaries -Force:$Force
                }
            }

            if ($Exclude -notcontains "Credentials") {
                if ($PSCmdlet.ShouldProcess("Syncing SQL credentials from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing SQL credentials"
                    Copy-DbaCredential -Source $server -Destination $secondaries -Force:$Force
                }
            }

            if ($Exclude -notcontains "DatabaseMail") {
                if ($PSCmdlet.ShouldProcess("Syncing database mail from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing database mail"
                    Copy-DbaDbMail -Source $server -Destination $secondaries -Force:$Force
                }
            }

            if ($Exclude -notcontains "LinkedServers") {
                if ($PSCmdlet.ShouldProcess("Syncing linked servers from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing linked servers"
                    Copy-DbaLinkedServer -Source $server -Destination $secondaries -Force:$Force
                }
            }

            if ($Exclude -notcontains "SystemTriggers") {
                if ($PSCmdlet.ShouldProcess("Syncing System Triggers from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing System Triggers"
                    Copy-DbaInstanceTrigger -Source $server -Destination $secondaries -Force:$Force
                }
            }

            if ($Exclude -notcontains "AgentCategory") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Categories from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Categories"
                    Copy-DbaAgentJobCategory -Source $server -Destination $secondaries -Force:$force
                    $secondaries.JobServer.JobCategories.Refresh()
                    $secondaries.JobServer.OperatorCategories.Refresh()
                    $secondaries.JobServer.AlertCategories.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentOperator") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Operators from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Operators"
                    Copy-DbaAgentOperator -Source $server -Destination $secondaries -Force:$force
                    $secondaries.JobServer.Operators.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentAlert") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Alerts from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Alerts"
                    Copy-DbaAgentAlert -Source $server -Destination $secondaries -Force:$force -IncludeDefaults
                    $secondaries.JobServer.Alerts.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentProxy") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Proxy Accounts from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Proxy Accounts"
                    Copy-DbaAgentProxy -Source $server -Destination $secondaries -Force:$force
                    $secondaries.JobServer.ProxyAccounts.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentSchedule") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Schedules from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Schedules"
                    Copy-DbaAgentSchedule -Source $server -Destination $secondaries -Force:$force
                    $secondaries.JobServer.SharedSchedules.Refresh()
                    $secondaries.JobServer.Refresh()
                    $secondaries.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentJob") {
                if ($PSCmdlet.ShouldProcess("Syncing Agent Jobs from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Jobs"
                    Copy-DbaAgentJob -Source $server -Destination $secondaries -Force:$force -Job $Job -ExcludeJob $ExcludeJob -DisableOnDestination:$DisableJobOnDestination
                }
            }

            if ($Exclude -notcontains "LoginPermissions") {
                if ($PSCmdlet.ShouldProcess("Syncing login permissions from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing login permissions"
                    Sync-DbaLoginPermission -Source $server -Destination $secondaries -Login $Login -ExcludeLogin $ExcludeLogin
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUbJCbbL5One3bco1ymljkXdhZ
# u+OgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFIoIIrBB9gmlW6sDrNufpjStLgTtMA0GCSqGSIb3DQEBAQUABIIBABWgx+iS
# r75SG1iHPEiQaKw8UWkRHxUpUpDbvwMteLKVWZluaZQJZ2TZblyS6V0/ccCPwYxk
# +2BmEloOrSJQnSv9P/56M2Hctu62cFyTkmwjEZNIKurgWY8zKMTaOCtfQEvTFzGi
# uHXwZJaNn8KIWgjPY0bHABV+YoLr6oT3ntMSXwQsMGSDIKuyF/hxVe5zUPgse9kF
# ty8BEwSVs0V+saxT4QXORDdrLUz+/kh0uzCKyxmGAV9weKmOkMsH7pf5FCL5TI3i
# msO7GhTLcxTuZJ9fyFDWz07XXhJ1uFtvtJYvr13xXoZiagudLw5hSa1xbrmUQh0d
# oy2oI6EkQ1Nx7rihggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjU1OVowLwYJKoZIhvcNAQkEMSIEIDow6FhXiIzly630MUUFBvhV0p36
# oVAyQ1FsoMZrT4uTMA0GCSqGSIb3DQEBAQUABIIBADv/N/rigSTJjORZABgXj/h1
# pBQXMLJ8s8cSaJZ5bAwzEP25fK6RcFzGsVsKHrJdRUAZbeNTxNnDLZcRdTXq5G9l
# qtc33gomsxkeAnTbUlQse0cmiWMd5vowu7Dbrhabpw4PAMBPt9DLqMi6dKCovjnO
# JCpTJQLdYXwUCBeixuWKXkgTInsaAOy/2P/oovVKOnmEzT62WhbmU2z9A7Wo6m14
# 3+IAsP3+x0vLz8dPtdg9TZADAc0ou5JfjGx+TNvvC5N1bCG8PsBePdAB921YOPKA
# y8c+WaTP1dgNYnATswQjkEkdyYsp/dV92UCdFyI8y37A92evmKkBNCzRH+2bdzQ=
# SIG # End signature block
