function Copy-DbaRegServer {
    <#
    .SYNOPSIS
        Migrates SQL Server Central Management groups and server instances from one SQL Server to another.

    .DESCRIPTION
        Copy-DbaRegServer copies all groups, subgroups, and server instances from one SQL Server to another.

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

    .PARAMETER Group
        This is an auto-populated array that contains your Central Management Server top-level groups on Source. You can specify one, many or none.

        If Group is not specified, all groups in your Central Management Server will be copied.

    .PARAMETER SwitchServerName
        If this switch is enabled, all instance names will be changed from Source to Destination.

        Central Management Server does not allow you to add a shared registered server with the same name as the Configuration Server.

    .PARAMETER Force
        If this switch is enabled, group(s) will be dropped and recreated if they already exists on destination.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaRegServer

    .EXAMPLE
        PS C:\> Copy-DbaRegServer -Source sqlserver2014a -Destination sqlcluster

        All groups, subgroups, and server instances are copied from sqlserver2014a CMS to sqlcluster CMS.

    .EXAMPLE
        PS C:\> Copy-DbaRegServer -Source sqlserver2014a -Destination sqlcluster -Group Group1,Group3

        Top-level groups Group1 and Group3 along with their subgroups and server instances are copied from sqlserver to sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaRegServer -Source sqlserver2014a -Destination sqlcluster -Group Group1,Group3 -SwitchServerName -SourceSqlCredential $SourceSqlCredential -DestinationSqlCredential $DestinationSqlCredential

        Top-level groups Group1 and Group3 along with their subgroups and server instances are copied from sqlserver to sqlcluster. When adding sql instances to sqlcluster, if the server name of the migrating instance is "sqlcluster", it will be switched to "sqlserver".

        If SwitchServerName is not specified, "sqlcluster" will be skipped.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [Alias('CMSGroup')]
        [string[]]$Group,
        [switch]$SwitchServerName,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        function Invoke-ParseServerGroup {
            [cmdletbinding()]
            param (
                $sourceGroup,
                $destinationGroup,
                $SwitchServerName
            )
            if ($destinationGroup.Name -eq "DatabaseEngineServerGroup" -and $sourceGroup.Name -ne "DatabaseEngineServerGroup") {
                $currentServerGroup = $destinationGroup
                $groupName = $sourceGroup.Name
                $destinationGroup = $destinationGroup.ServerGroups[$groupName]

                $copyDestinationGroupStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $groupName
                    Type              = "CMS Destination Group"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($null -ne $destinationGroup) {

                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Checking to see if $groupName exists")) {
                            $copyDestinationGroupStatus.Status = "Skipped"
                            $copyDestinationGroupStatus.Notes = "Already exists on destination"
                            $copyDestinationGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Destination group $groupName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    }
                    if ($Pscmdlet.ShouldProcess($destinstance, "Dropping group $groupName")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping group $groupName"
                            $destinationGroup.Drop()
                        } catch {
                            $copyDestinationGroupStatus.Status = "Failed"
                            $copyDestinationGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue dropping group" -Target $groupName -ErrorRecord $_ -Continue
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating group $groupName")) {
                    Write-Message -Level Verbose -Message "Creating group $($sourceGroup.Name)"
                    $destinationGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($currentServerGroup, $sourceGroup.Name)
                    $destinationGroup.Create()

                    $copyDestinationGroupStatus.Status = "Successful"
                    $copyDestinationGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }

            # Add Servers
            foreach ($instance in $sourceGroup.RegisteredServers) {
                $instanceName = $instance.Name
                $serverName = $instance.ServerName

                $copyInstanceStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $instanceName
                    Type              = "CMS Instance"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($serverName.ToLowerInvariant() -eq $toCmStore.DomainInstanceName.ToLowerInvariant()) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Checking to see if server is the CMS equals current server name")) {
                        if ($SwitchServerName) {
                            $serverName = $fromCmStore.DomainInstanceName
                            $instanceName = $fromCmStore.DomainInstanceName
                            Write-Message -Level Verbose -Message "SwitchServerName was used and new CMS equals current server name. $($toCmStore.DomainInstanceName.ToLowerInvariant()) changed to $serverName."
                        } else {
                            $copyInstanceStatus.Status = "Skipped"
                            $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "$serverName is Central Management Server. Add prohibited. Skipping."
                            continue
                        }
                    }
                }

                if ($destinationGroup.RegisteredServers.Name -contains $instanceName) {

                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Checking to see if $instanceName in $groupName exists")) {
                            $copyInstanceStatus.Status = "Skipped"
                            $copyInstanceStatus.Notes = "Already exists on destination"
                            $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Instance $instanceName exists in group $groupName at destination. Use -Force to drop and migrate."
                        }
                        continue
                    }

                    if ($Pscmdlet.ShouldProcess($destinstance, "Dropping instance $instanceName from $groupName and recreating")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping instance $instance from $groupName"
                            $destinationGroup.RegisteredServers[$instanceName].Drop()
                        } catch {
                            $copyInstanceStatus.Status = "Failed"
                            $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue dropping instance from group" -Target $instanceName -ErrorRecord $_ -Continue
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Copying $instanceName")) {
                    $newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($destinationGroup, $instanceName)
                    $newServer.ServerName = $serverName
                    $newServer.Description = $instance.Description

                    if ($serverName -ne $fromCmStore.DomainInstanceName) {
                        $newServer.SecureConnectionString = $instance.SecureConnectionString
                        $newServer.ConnectionString = $instance.ConnectionString.ToString()
                    }

                    try {
                        $newServer.Create()

                        $copyInstanceStatus.Status = "Successful"
                        $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyInstanceStatus.Status = "Failed"
                        $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        if ($_.Exception -match "same name") {
                            Stop-Function -Message "Could not add Switched Server instance name." -Target $instanceName -ErrorRecord $_ -Continue
                        } else {
                            Stop-Function -Message "Failed to add $serverName" -Target $instanceName -ErrorRecord $_ -Continue
                        }
                    }
                    Write-Message -Level Verbose -Message "Added Server $serverName as $instanceName to $($destinationGroup.Name)"
                }
            }

            # Add Groups
            foreach ($fromSubGroup in $sourceGroup.ServerGroups) {
                $fromSubGroupName = $fromSubGroup.Name
                if ($Pscmdlet.ShouldProcess($destinstance, "Copying group $fromSubGroupName")) {
                    $toSubGroup = $destinationGroup.ServerGroups[$fromSubGroupName]

                    $copyGroupStatus = [pscustomobject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Name              = $fromSubGroupName
                        Type              = "CMS Group"
                        Status            = $null
                        Notes             = $null
                        DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                    }
                }

                if ($null -ne $toSubGroup) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Checking to see if subgroup $fromSubGroupName exists")) {
                            $copyGroupStatus.Status = "Skipped"
                            $copyGroupStatus.Notes = "Already exists on destination"
                            $copyGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Subgroup $fromSubGroupName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    }

                    if ($Pscmdlet.ShouldProcess($destinstance, "Dropping subgroup $fromSubGroupName recreating")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping subgroup $fromSubGroupName"
                            $toSubGroup.Drop()
                        } catch {
                            $copyGroupStatus.Status = "Failed"
                            $copyGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue dropping subgroup" -Target $toSubGroup -ErrorRecord $_ -Continue
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating group $($fromSubGroup.Name)")) {
                    Write-Message -Level Verbose -Message "Creating group $($fromSubGroup.Name)"
                    $toSubGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($destinationGroup, $fromSubGroup.Name)
                    $toSubGroup.create()

                    $copyGroupStatus.Status = "Successful"
                    $copyGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }

                Invoke-ParseServerGroup -sourceGroup $fromSubGroup -destinationgroup $toSubGroup -SwitchServerName $SwitchServerName
            }
        }

        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
            $fromCmStore = Get-DbaRegServerStore -SqlInstance $sourceServer
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $toCmStore = Get-DbaRegServerStore -SqlInstance $destServer

            $stores = $fromCmStore.DatabaseEngineServerGroup
            if ($Group) {
                $stores = @();
                foreach ($groupName in $Group) {
                    $stores += $fromCmStore.DatabaseEngineServerGroup.ServerGroups[$groupName]
                }
            }

            foreach ($store in $stores) {
                Invoke-ParseServerGroup -sourceGroup $store -destinationgroup $toCmStore.DatabaseEngineServerGroup -SwitchServerName $SwitchServerName
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUPhdpkOjsbuEdEH0+/p/tdpfq
# MW2gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFO3VIco+QPG0v+r/BP1F7rzbTn28MA0GCSqGSIb3DQEBAQUABIIBAK9EC2eX
# ++h6QxUaxg0SLND7Ae9oTydScStjweDqOLLzgZS2mlofMnHV/N2R8/lKcPl9h0qZ
# ULWQpnZwT07caHYqFoQDRsCpDa8T+YQIJ2c/U+X8S92xdVrrswpVo92LDlxt/Pvf
# 51eqXK8oAezvM0JcNWtl2jDFwoQeNyT/5+Z6uGI++ORPtrUPtkOwmuxXWc8R8eo8
# 5DUHXw+GoBDmh1pLiidwdl51ccklIbEtNEjEgu9Dm62fSHETY1g5NAZX+2XbBcGU
# Eajlk9tKGirAmw2KwQZ+ttCJCKSl7nTKdTONFEYqiRX+udkdW64Pito9gdXTinbQ
# AZ8i+E9mICVkazOhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUwMFowLwYJKoZIhvcNAQkEMSIEIPzXTnFj72GXBIibnJUidBexPTs7
# qgNW7somFm/msxnvMA0GCSqGSIb3DQEBAQUABIIBAGLwj8iDedI7+neciz03isgz
# uwf9nouq3IVUTPx6YhIUUIJLrcV034PqVbPTzBX+5aLOGS33HONsi1JmPOx0qvnV
# UIMTzc6X53YQVHoswFEgRxs1H6v8kHSeI23w2HnLzD4eZUFn4/CWbrp9j0P49lX3
# OAZxlEpJ6/HHzMfiKroCtzJisIb2trdcBKcxyh2AaqaSq94oWnOEdvS7JFbjDWp6
# HySz3dQVzbo4wpVn3k1CD3uKK6UquDBANcFDiSvTkNI27a1LnunP/9TWPYAGGP/N
# HVaKgUKTAuvFAT3oDPnNg8mNqe/oounpQlkR7gkXxtG5sD55l+0Pe9sWCdrIMdQ=
# SIG # End signature block
