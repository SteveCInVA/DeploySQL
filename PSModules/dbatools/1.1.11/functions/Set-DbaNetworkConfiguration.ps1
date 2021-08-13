function Set-DbaNetworkConfiguration {
    <#
    .SYNOPSIS
        Sets the network configuration of a SQL Server instance.

    .DESCRIPTION
        Sets the network configuration of a SQL Server instance.

        Parameters are available for typical tasks like enabling or disabling a protocol or switching between dynamic and static ports.
        The object returned by Get-DbaNetworkConfiguration can be used to adjust settings of the properties
        and then passed to this command via pipeline or -InputObject parameter.

        A change to the network configuration with SQL Server requires a restart to take effect,
        support for this can be done via the RestartService parameter.

        Remote SQL WMI is used by default, with PS Remoting used as a fallback.

        For a detailed explanation of the different properties see the documentation at:
        https://docs.microsoft.com/en-us/sql/tools/configuration-manager/sql-server-network-configuration

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER EnableProtocol
        Enables one of the following network protocols: SharedMemory, NamedPipes, TcpIp.

    .PARAMETER DisableProtocol
        Disables one of the following network protocols: SharedMemory, NamedPipes, TcpIp.

    .PARAMETER DynamicPortForIPAll
        Configures the instance to listen on a dynamic port for all IP addresses.
        Will enable the TCP/IP protocol if needed.
        Will set TcpIpProperties.ListenAll to $true if needed.
        Will reset the last used dynamic port if already set.

    .PARAMETER StaticPortForIPAll
        Configures the instance to listen on one or more static ports for all IP addresses.
        Will enable the TCP/IP protocol if needed.
        Will set TcpIpProperties.ListenAll to $true if needed.

    .PARAMETER RestartService
        Every change to the network configuration needs a service restart to take effect.
        This switch will force a restart of the service if the network configuration has changed.

    .PARAMETER InputObject
        The output object from Get-DbaNetworkConfiguration.
        Get-DbaNetworkConfiguration has to be run with -OutputType Full (default) to get the complete object.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: SQLWMI
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaNetworkConfiguration

    .EXAMPLE
        PS C:\> Set-DbaNetworkConfiguration -SqlInstance sql2016 -EnableProtocol SharedMemory -RestartService

        Ensures that the shared memory network protocol for the default instance on sql2016 is enabled.
        Restarts the service if needed.

    .EXAMPLE
        PS C:\> Set-DbaNetworkConfiguration -SqlInstance sql2016\test -StaticPortForIPAll 14331, 14332 -RestartService

        Ensures that the TCP/IP network protocol is enabled and configured to use the ports 14331 and 14332 for all IP addresses.
        Restarts the service if needed.

    .EXAMPLE
        PS C:\> $netConf = Get-DbaNetworkConfiguration -SqlInstance sqlserver2014a
        PS C:\> $netConf.TcpIpProperties.KeepAlive = 60000
        PS C:\> $netConf | Set-DbaNetworkConfiguration -RestartService -Confirm:$false

        Changes the value of the KeepAlive property for the default instance on sqlserver2014a and restarts the service.
        Does not prompt for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High", DefaultParameterSetName = 'NonPipeline')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateSet('SharedMemory', 'NamedPipes', 'TcpIp')]
        [string]$EnableProtocol,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateSet('SharedMemory', 'NamedPipes', 'TcpIp')]
        [string]$DisableProtocol,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [switch]$DynamicPortForIPAll,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [int[]]$StaticPortForIPAll,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$RestartService,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [object[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $wmiScriptBlock = {
            # This scriptblock will be processed by Invoke-ManagedComputerCommand.
            # It is extended there above this line by the following lines:
            #   $ipaddr = $args[$args.GetUpperBound(0)]
            #   [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
            #   $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $ipaddr
            #   $null = $wmi.Initialize()
            # So we can use $wmi here and assume that there is a successful connection.

            # We take on object as the first parameter which has to include the instance name and the target network configuration.
            $targetConf = $args[0]
            $changes = @()
            $verbose = @()
            $exception = $null

            try {
                $verbose += "Getting server protocols for $($targetConf.InstanceName)"
                $wmiServerProtocols = ($wmi.ServerInstances | Where-Object { $_.Name -eq $targetConf.InstanceName } ).ServerProtocols

                $verbose += 'Getting server protocol shared memory'
                $wmiSpSm = $wmiServerProtocols | Where-Object { $_.Name -eq 'Sm' }
                if ($null -eq $targetConf.SharedMemoryEnabled) {
                    $verbose += 'SharedMemoryEnabled not in target object'
                } elseif ($wmiSpSm.IsEnabled -ne $targetConf.SharedMemoryEnabled) {
                    $wmiSpSm.IsEnabled = $targetConf.SharedMemoryEnabled
                    $wmiSpSm.Alter()
                    $changes += "Changed SharedMemoryEnabled to $($targetConf.SharedMemoryEnabled)"
                }

                $verbose += 'Getting server protocol named pipes'
                $wmiSpNp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Np' }
                if ($null -eq $targetConf.NamedPipesEnabled) {
                    $verbose += 'NamedPipesEnabled not in target object'
                } elseif ($wmiSpNp.IsEnabled -ne $targetConf.NamedPipesEnabled) {
                    $wmiSpNp.IsEnabled = $targetConf.NamedPipesEnabled
                    $wmiSpNp.Alter()
                    $changes += "Changed NamedPipesEnabled to $($targetConf.NamedPipesEnabled)"
                }

                $verbose += 'Getting server protocol TCP/IP'
                $wmiSpTcp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Tcp' }
                if ($null -eq $targetConf.TcpIpEnabled) {
                    $verbose += 'TcpIpEnabled not in target object'
                } elseif ($wmiSpTcp.IsEnabled -ne $targetConf.TcpIpEnabled) {
                    $wmiSpTcp.IsEnabled = $targetConf.TcpIpEnabled
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpEnabled to $($targetConf.TcpIpEnabled)"
                }

                $verbose += 'Getting properties for server protocol TCP/IP'
                $wmiSpTcpEnabled = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'Enabled' }
                if ($null -eq $targetConf.TcpIpProperties.Enabled) {
                    $verbose += 'TcpIpProperties.Enabled not in target object'
                } elseif ($wmiSpTcpEnabled.Value -ne $targetConf.TcpIpProperties.Enabled) {
                    $wmiSpTcpEnabled.Value = $targetConf.TcpIpProperties.Enabled
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpProperties.Enabled to $($targetConf.TcpIpProperties.Enabled)"
                }

                $wmiSpTcpKeepAlive = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'KeepAlive' }
                if ($null -eq $targetConf.TcpIpProperties.KeepAlive) {
                    $verbose += 'TcpIpProperties.KeepAlive not in target object'
                } elseif ($wmiSpTcpKeepAlive.Value -ne $targetConf.TcpIpProperties.KeepAlive) {
                    $wmiSpTcpKeepAlive.Value = $targetConf.TcpIpProperties.KeepAlive
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpProperties.KeepAlive to $($targetConf.TcpIpProperties.KeepAlive)"
                }

                $wmiSpTcpListenOnAllIPs = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'ListenOnAllIPs' }
                if ($null -eq $targetConf.TcpIpProperties.ListenAll) {
                    $verbose += 'TcpIpProperties.ListenAll not in target object'
                } elseif ($wmiSpTcpListenOnAllIPs.Value -ne $targetConf.TcpIpProperties.ListenAll) {
                    $wmiSpTcpListenOnAllIPs.Value = $targetConf.TcpIpProperties.ListenAll
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpProperties.ListenAll to $($targetConf.TcpIpProperties.ListenAll)"
                }

                $verbose += 'Getting properties for IPn'
                $wmiIPn = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -ne 'IPAll' }
                foreach ($ip in $wmiIPn) {
                    $ipTarget = $targetConf.TcpIpAddresses | Where-Object { $_.Name -eq $ip.Name }

                    $ipActive = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'Active' }
                    if ($null -eq $ipTarget.Active) {
                        $verbose += 'Active not in target IP address object'
                    } elseif ($ipActive.Value -ne $ipTarget.Active) {
                        $ipActive.Value = $ipTarget.Active
                        $wmiSpTcp.Alter()
                        $changes += "Changed Active for $($ip.Name) to $($ipTarget.Active)"
                    }

                    $ipEnabled = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'Enabled' }
                    if ($null -eq $ipTarget.Enabled) {
                        $verbose += 'Enabled not in target IP address object'
                    } elseif ($ipEnabled.Value -ne $ipTarget.Enabled) {
                        $ipEnabled.Value = $ipTarget.Enabled
                        $wmiSpTcp.Alter()
                        $changes += "Changed Enabled for $($ip.Name) to $($ipTarget.Enabled)"
                    }

                    $ipIpAddress = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'IpAddress' }
                    if ($null -eq $ipTarget.IpAddress) {
                        $verbose += 'IpAddress not in target IP address object'
                    } elseif ($ipIpAddress.Value -ne $ipTarget.IpAddress) {
                        $ipIpAddress.Value = $ipTarget.IpAddress
                        $wmiSpTcp.Alter()
                        $changes += "Changed IpAddress for $($ip.Name) to $($ipTarget.IpAddress)"
                    }

                    $ipTcpDynamicPorts = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' }
                    if ($null -eq $ipTarget.TcpDynamicPorts) {
                        $verbose += 'TcpDynamicPorts not in target IP address object'
                    } elseif ($ipTcpDynamicPorts.Value -ne $ipTarget.TcpDynamicPorts) {
                        $ipTcpDynamicPorts.Value = $ipTarget.TcpDynamicPorts
                        $wmiSpTcp.Alter()
                        $changes += "Changed TcpDynamicPorts for $($ip.Name) to $($ipTarget.TcpDynamicPorts)"
                    }

                    $ipTcpPort = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
                    if ($null -eq $ipTarget.TcpPort) {
                        $verbose += 'TcpPort not in target IP address object'
                    } elseif ($ipTcpPort.Value -ne $ipTarget.TcpPort) {
                        $ipTcpPort.Value = $ipTarget.TcpPort
                        $wmiSpTcp.Alter()
                        $changes += "Changed TcpPort for $($ip.Name) to $($ipTarget.TcpPort)"
                    }
                }

                $verbose += 'Getting properties for IPAll'
                $wmiIPAll = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -eq 'IPAll' }
                $ipTarget = $targetConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }

                $ipTcpDynamicPorts = $wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' }
                if ($null -eq $ipTarget.TcpDynamicPorts) {
                    $verbose += 'TcpDynamicPorts not in target IP address object'
                } elseif ($ipTcpDynamicPorts.Value -ne $ipTarget.TcpDynamicPorts) {
                    $ipTcpDynamicPorts.Value = $ipTarget.TcpDynamicPorts
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpDynamicPorts for $($wmiIPAll.Name) to $($ipTarget.TcpDynamicPorts)"
                }

                $ipTcpPort = $wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
                if ($null -eq $ipTarget.TcpPort) {
                    $verbose += 'TcpPort not in target IP address object'
                } elseif ($ipTcpPort.Value -ne $ipTarget.TcpPort) {
                    $ipTcpPort.Value = $ipTarget.TcpPort
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpPort for $($wmiIPAll.Name) to $($ipTarget.TcpPort)"
                }
            } catch {
                $exception = $_
            }

            [PSCustomObject]@{
                Changes   = $changes
                Verbose   = $verbose
                Exception = $exception
            }
        }
    }

    process {
        if ($SqlInstance -and (Test-Bound -Not -ParameterName EnableProtocol, DisableProtocol, DynamicPortForIPAll, StaticPortForIPAll)) {
            Stop-Function -Message "You must choose an action if SqlInstance is used."
            return
        }

        if ($SqlInstance -and (Test-Bound -ParameterName EnableProtocol, DisableProtocol, DynamicPortForIPAll, StaticPortForIPAll -Not -Max 1)) {
            Stop-Function -Message "Only one action is allowed at a time."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Get network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)."
                $netConf = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -EnableException
            } catch {
                Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
            }

            if ($EnableProtocol) {
                if ($netConf."${EnableProtocol}Enabled") {
                    Write-Message -Level Verbose -Message "Protocol $EnableProtocol is already enabled on $instance."
                } else {
                    Write-Message -Level Verbose -Message "Will enable protocol $EnableProtocol on $instance."
                    $netConf."${EnableProtocol}Enabled" = $true
                    if ($EnableProtocol -eq 'TcpIp') {
                        $netConf.TcpIpProperties.Enabled = $true
                    }
                }
            }

            if ($DisableProtocol) {
                if ($netConf."${DisableProtocol}Enabled") {
                    Write-Message -Level Verbose -Message "Will disable protocol $EnableProtocol on $instance."
                    $netConf."${DisableProtocol}Enabled" = $false
                    if ($DisableProtocol -eq 'TcpIp') {
                        $netConf.TcpIpProperties.Enabled = $false
                    }
                } else {
                    Write-Message -Level Verbose -Message "Protocol $EnableProtocol is already disabled on $instance."
                }
            }

            if ($DynamicPortForIPAll) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance."
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if (-not $netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.ListenAll = $true
                }
                $ipAll = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IPAll to '0' on $instance."
                $ipAll.TcpDynamicPorts = '0'
                Write-Message -Level Verbose -Message "Will set property TcpPort of IPAll to '' on $instance."
                $ipAll.TcpPort = ''
            }

            if ($StaticPortForIPAll) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance."
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if (-not $netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.ListenAll = $true
                }
                $ipAll = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IPAll to '' on $instance."
                $ipAll.TcpDynamicPorts = ''
                $port = $StaticPortForIPAll -join ','
                Write-Message -Level Verbose -Message "Will set property TcpPort of IPAll to '$port' on $instance."
                $ipAll.TcpPort = $port
            }

            $InputObject += $netConf
        }

        foreach ($netConf in $InputObject) {
            try {
                $output = [PSCustomObject]@{
                    ComputerName  = $netConf.ComputerName
                    InstanceName  = $netConf.InstanceName
                    SqlInstance   = $netConf.SqlInstance
                    Changes       = @()
                    RestartNeeded = $false
                    Restarted     = $false
                }

                if ($Pscmdlet.ShouldProcess("Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName)")) {
                    $return = Invoke-ManagedComputerCommand -ComputerName $netConf.ComputerName -Credential $Credential -ScriptBlock $wmiScriptBlock -ArgumentList $netConf
                    $output.Changes = $return.Changes
                    foreach ($msg in $return.Verbose) {
                        Write-Message -Level Verbose -Message $msg
                    }
                    if ($return.Exception) {
                        Stop-Function -Message "Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName) failed with: $($return.Exception)" -Target $netConf.ComputerName -ErrorRecord $output.Exception -Continue
                    }
                }

                if ($return.Changes.Count -gt 0) {
                    $output.RestartNeeded = $true
                    if ($RestartService) {
                        if ($Pscmdlet.ShouldProcess("Restarting service for instance $($netConf.InstanceName) on $($netConf.ComputerName)")) {
                            try {
                                $null = Restart-DbaService -ComputerName $netConf.ComputerName -InstanceName $netConf.InstanceName -Credential $Credential -Type Engine -Force -EnableException -Confirm:$false
                                $output.Restarted = $true
                            } catch {
                                Write-Message -Level Warning -Message "A restart of the service for instance $($netConf.InstanceName) on $($netConf.ComputerName) failed ($_). Restart of instance is necessary for the new settings to take effect."
                            }
                        }
                    } else {
                        Write-Message -Level Warning -Message "A restart of the service for instance $($netConf.InstanceName) on $($netConf.ComputerName) is needed for the changes to take effect."
                    }
                }

                $output

            } catch {
                Stop-Function -Message "Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName) not possible." -Target $netConf.ComputerName -ErrorRecord $_ -Continue
            }
        }
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU90Cw1n38McOA/7WA6BRXTjhC
# YOGgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFL9rU3i2TdjNLaARhiVxdXSkYfpUMA0GCSqGSIb3DQEBAQUABIIBALUetwgW
# UY0qsgG1BYDeHa/G13/dJyt6qcXMVVTk+SJrkoTziBKNwwDYQLdt4CpByNAFdsnv
# ZplFnEjM5FhoTYIKBL9ZEVbSPoHB9jWLaoFHpGS4ycQexH8NeZdZoXqPQaKJDgUp
# kCXBkE3oRVx9PWW43FYi4+H3xX4CFg7yZKdLffE7ZQn2rNhDNHyUnMTGKbVjGI29
# ix7+KaEMu1ic9B5cU9LdnCpDArqvFwvBOT+8Mzjq7uQqXd+AsQsaaEVbMhArxnkc
# PQZnmhnEHO8hf7/ZFfUJL2u70RYS/dRGD0varHK++3mxawWaNWw/jR1TEUC+hekJ
# AKyTqqyjGZjsGk6hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjU1NlowLwYJKoZIhvcNAQkEMSIEIM4nPi2XtHKSVqpIxo2cAV11lkAu
# TX3GiMmEpADfKTnCMA0GCSqGSIb3DQEBAQUABIIBAIwJUol5Ho5UxS8JTNUB6Lbw
# aiDU+2zNyobP/Mk2Bw4z5ZM5lfY0D8/pWaJF2lDnFcHPeUOchusHczdEcQvYKr3v
# K+iDHRve3GnJzQ2Fei9lSZjz3ZfwuKGjsEJsCw4L7/r7L0b8fOuI8nF4FeRxm3De
# 49xcUr0ZRp1iVJF+vbpg2mCUYXMrUH6XLh7Hw24upbmvI+TZfGHlVfPE2XPEgbAk
# PhHK4SifzcYnxTm2/Y0lhfrFxXXP7DvetEViBypnTmutiJjX4nb9RQL7lYRBE4av
# k5vQiDWu/tcjBnLL6pF0zDMjcdIuBxB4FCoZ1cU0tXrPfp1m3OU2M2F3pJLrCd0=
# SIG # End signature block
