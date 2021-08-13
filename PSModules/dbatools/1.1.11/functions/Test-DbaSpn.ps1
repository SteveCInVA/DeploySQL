function Test-DbaSpn {
    <#
    .SYNOPSIS
        Test-DbaSpn will determine what SPNs *should* be set for a given server (and any instances of SQL running on it) and return
        whether the SPNs are set or not.

    .DESCRIPTION
        This function is designed to take in a server name(s) and attempt to determine required SPNs. It was initially written to mimic the (previously) broken functionality of the Microsoft Kerberos Configuration manager and SQL Server 2016.

        - For any instances with TCP/IP enabled, the script will determine which port(s) the instances are listening on and generate the required SPNs.
        - For named instances NOT using dynamic ports, the script will generate a port-based SPN for those instances as well.
        - At a minimum, the script will test a base, port-less SPN for each instance discovered.

        Once the required SPNs are generated, the script will connect to Active Directory and search for any of the SPNs (if any) that are already set. The function will return a custom object(s) that contains the server name checked, the instance name discovered, the account the service is running under, and what the "required" SPN should be. It will also return a boolean property indicating if the SPN is set in Active Directory or not.

    .PARAMETER ComputerName
        The computer you want to discover any SQL Server instances on. This parameter is required.

    .PARAMETER Credential
        The credential you want to use to connect to the remote server and active directory.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SPN
        Author: Drew Furgiuele (@pittfurg), http://www.port1433.com | niphlod

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaSpn

    .EXAMPLE
        Test-DbaSpn -ComputerName SQLSERVERA -Credential ad\sqldba

        Connects to a computer (SQLSERVERA) and queries WMI for all SQL instances and return "required" SPNs. It will then take each SPN it generates
        and query Active Directory to make sure the SPNs are set.

    .EXAMPLE
        Test-DbaSpn -ComputerName SQLSERVERA,SQLSERVERB -Credential ad\sqldba

        Connects to multiple computers (SQLSERVERA, SQLSERVERB) and queries WMI for all SQL instances and return "required" SPNs.
        It will then take each SPN it generates and query Active Directory to make sure the SPNs are set.

    .EXAMPLE
        Test-DbaSpn -ComputerName SQLSERVERC -Credential ad\sqldba

        Connects to a computer (SQLSERVERC) on a specified and queries WMI for all SQL instances and return "required" SPNs.
        It will then take each SPN it generates and query Active Directory to make sure the SPNs are set. Note that the credential you pass must have be a valid login with appropriate rights on the domain

    #>
    [cmdletbinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    begin {
        # spare the cmdlet to search for the same account over and over
        $resultCache = @{ }
    }
    process {
        foreach ($computer in $ComputerName) {
            try {
                $resolved = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential -ErrorAction Stop
            } catch {
                $resolved = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Turbo
            }

            if ($null -eq $resolved.IPAddress) {
                Write-Message -Level Warning -Message "Cannot resolve IP address, moving on."
                continue
            }

            $hostEntry = $resolved.FullComputerName

            Write-Message -Message "Resolved ComputerName to FQDN: $hostEntry" -Level Verbose

            $Scriptblock = {

                function Convert-SqlVersion {
                    [cmdletbinding()]
                    param (
                        [version]$version
                    )

                    switch ($version.Major) {
                        9 { "SQL Server 2005" }
                        10 {
                            if ($version.Minor -eq 0) {
                                "SQL Server 2008"
                            } else {
                                "SQL Server 2008 R2"
                            }
                        }
                        11 { "SQL Server 2012" }
                        12 { "SQL Server 2014" }
                        13 { "SQL Server 2016" }
                        14 { "SQL Server 2017" }
                        15 { "SQL Server 2019" }
                        default { $version }
                    }
                }

                $spns = @()
                $servereName = $args[0]
                $hostEntry = $args[1]
                $instanceName = $args[2]
                $instanceCount = $wmi.ServerInstances.Count

                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose "Found $instanceCount instances"

                foreach ($instance in $wmi.ServerInstances) {
                    $spn = [pscustomobject] @{
                        ComputerName           = $servereName
                        InstanceName           = $instanceName
                        #SKUNAME
                        SqlProduct             = $null
                        InstanceServiceAccount = $null
                        RequiredSPN            = $null
                        IsSet                  = $false
                        Cluster                = $false
                        TcpEnabled             = $false
                        Port                   = $null
                        DynamicPort            = $false
                        Warning                = "None"
                        Error                  = "None"
                        # for piping
                        Credential             = $Credential
                    }

                    $spn.InstanceName = $instance.Name
                    $instanceName = $spn.InstanceName

                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose "Parsing $instanceName"

                    $services = $wmi.Services | Where-Object DisplayName -EQ "SQL Server ($instanceName)"
                    $spn.InstanceServiceAccount = $services.ServiceAccount
                    $spn.Cluster = ($services.advancedproperties | Where-Object Name -EQ 'Clustered').Value

                    if ($spn.Cluster) {
                        $hostEntry = ($services.advancedproperties | Where-Object Name -EQ 'VSNAME').Value.ToLowerInvariant()
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose "Found cluster $hostEntry"
                        $hostEntry = ([System.Net.Dns]::GetHostEntry($hostEntry)).HostName
                        $spn.ComputerName = $hostEntry
                    }

                    $rawVersion = [version]($services.AdvancedProperties | Where-Object Name -EQ 'VERSION').Value

                    $version = Convert-SqlVersion $rawVersion
                    $skuName = ($services.AdvancedProperties | Where-Object Name -EQ 'SKUNAME').Value

                    $spn.SqlProduct = "$version $skuName"

                    #is tcp enabled on this instance? If not, we don't need an spn, son
                    if ((($instance.ServerProtocols | Where-Object { $_.Displayname -eq "TCP/IP" }).ProtocolProperties | Where-Object { $_.Name -eq "Enabled" }).Value -eq $true) {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose "TCP is enabled, gathering SPN requirements"
                        $spn.TcpEnabled = $true
                        #Each instance has a default SPN of MSSQLSvc\<fqdn> or MSSSQLSvc\<fqdn>:Instance
                        if ($instance.Name -eq "MSSQLSERVER") {
                            $spn.RequiredSPN = "MSSQLSvc/$hostEntry"
                        } else {
                            $spn.RequiredSPN = "MSSQLSvc/" + $hostEntry + ":" + $instance.Name
                        }
                    }

                    $spns += $spn
                }
                # Now, for each spn, do we need a port set? Only if TCP is enabled and NOT DYNAMIC!
                foreach ($spn in $spns) {
                    $ports = @()

                    $ips = (($wmi.ServerInstances | Where-Object { $_.Name -eq $spn.InstanceName }).ServerProtocols | Where-Object { $_.DisplayName -eq "TCP/IP" -and $_.IsEnabled -eq "True" }).IpAddresses
                    $ipAllPort = $null
                    foreach ($ip in $ips) {
                        if ($ip.Name -eq "IPAll") {
                            $ipAllPort = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TCPPort" }).Value
                            if (($ip.IpAddressProperties | Where-Object { $_.Name -eq "TcpDynamicPorts" }).Value -ne "") {
                                $ipAllPort = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TcpDynamicPorts" }).Value + "d"
                            }
                        } else {
                            $enabled = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "Enabled" }).Value
                            $active = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "Active" }).Value
                            $tcpDynamicPorts = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TcpDynamicPorts" }).Value
                            if ($enabled -and $active -and $tcpDynamicPorts -eq "") {
                                $ports += ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TCPPort" }).Value
                            } elseif ($enabled -and $active -and $tcpDynamicPorts -ne "") {
                                $ports += $ipAllPort + "d"
                            }
                        }
                    }
                    if ($ipAllPort -ne "") {
                        #IPAll overrides any set ports. Not sure why that's the way it is?
                        $ports = $ipAllPort
                    }

                    $ports = $ports | Select-Object -Unique
                    foreach ($port in $ports) {
                        $newspn = $spn.PSObject.Copy()
                        if ($port -like "*d") {
                            $newspn.Port = ($port.replace("d", ""))
                            $newspn.RequiredSPN = $newspn.RequiredSPN.Replace(":" + $newSPN.InstanceName, ":" + $newspn.Port)
                            $newspn.DynamicPort = $true
                            $newspn.Warning = "Dynamic port is enabled"
                        } else {
                            #If this is a named instance, replace the instance name with a port number (for non-dynamic ported named instances)
                            $newspn.Port = $port
                            $newspn.DynamicPort = $false

                            if ($newspn.InstanceName -eq "MSSQLSERVER") {
                                $newspn.RequiredSPN = $newspn.RequiredSPN + ":" + $port
                            } else {
                                $newspn.RequiredSPN = $newspn.RequiredSPN.Replace(":" + $newSPN.InstanceName, ":" + $newspn.Port)
                            }
                        }
                        $spns += $newspn
                    }
                }
                $spns
            }


            try {
                $spns = Invoke-ManagedComputerCommand -ComputerName $hostEntry -ScriptBlock $Scriptblock -ArgumentList $resolved.FullComputerName, $hostEntry, $computer.InstanceName -Credential $Credential -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't connect to $computer" -ErrorRecord $_ -Continue
            }

            #Now query AD for each required SPN
            foreach ($spn in $spns) {
                $searchfor = 'User'
                if ($spn.InstanceServiceAccount -eq 'LocalSystem' -or $spn.InstanceServiceAccount -like 'NT SERVICE\*') {
                    Write-Message -Level Verbose -Message "Virtual account detected, changing target registration to computername"
                    $spn.InstanceServiceAccount = "$($resolved.Domain)\$($resolved.ComputerName)$"
                    $searchfor = 'Computer'
                } elseif ($spn.InstanceServiceAccount -like '*\*$') {
                    Write-Message -Level Verbose -Message "Managed Service Account detected"
                    $searchfor = 'Computer'
                }

                $serviceAccount = $spn.InstanceServiceAccount
                # spare the cmdlet to search for the same account over and over
                if ($spn.InstanceServiceAccount -notin $resultCache.Keys) {
                    Write-Message -Message "Searching for $serviceAccount" -Level Verbose
                    try {
                        $result = Get-DbaADObject -ADObject $serviceAccount -Type $searchfor -Credential $Credential -EnableException
                        $resultCache[$spn.InstanceServiceAccount] = $result
                    } catch {
                        if (![System.String]::IsNullOrEmpty($spn.InstanceServiceAccount)) {
                            Write-Message -Message "AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ($serviceAccount)." -Level Warning
                        }
                    }
                } else {
                    $result = $resultCache[$spn.InstanceServiceAccount]
                }
                if ($result.Count -gt 0) {
                    try {
                        $results = $result.GetUnderlyingObject()
                        if ($results.Properties.servicePrincipalName -contains $spn.RequiredSPN) {
                            $spn.IsSet = $true
                        }
                    } catch {
                        Write-Message -Message "The SQL Service account ($serviceAccount) has been found, but you don't have enough permission to inspect its SPNs" -Level Warning
                        continue
                    }
                } else {
                    Write-Message -Level Warning -Message "SQL Service account not found. Results may not be accurate."
                    $spn
                    continue
                }
                if (!$spn.IsSet -and $spn.TcpEnabled) {
                    $spn.Error = "SPN missing"
                }

                $spn | Select-DefaultView -ExcludeProperty Credential, DomainName
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUDyvY/MMEl4eq+xUJ9r0REWqC
# r3+gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFFcGS8QcgEtI31V/1EVIyaQF2fvzMA0GCSqGSIb3DQEBAQUABIIBAK0GKrsG
# gcXS8RnlayLKATW64VQ2w4KXwDL493oloZkP4wYI+ital+L1WuavSsPDym4Ur8dV
# 4Eh2SHDp00FWi1uznAVP0a/WhdzcHckbCbHgWdNf7ERw1LHl42OPNubMLpARtd/z
# jEQA2yq8Pm5Hcm8UReBDyaFrNJxP+bfS+zLgicgryeGGdF70aLm54poE9gBECDbY
# i6Fyb2WwzoSMkR2PpyxfHFywVOnClGaW9ZoqJ1Gzy5CHCBgY6OxcM1S+fhfJ1PVt
# XpwqJP+hfwOmn/EOIg0C6lstCS24NpURoJa7w5Uu6PatYluEPcSsldPRuoak8v3K
# YuAwWxUKyM2APYahggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjYwM1owLwYJKoZIhvcNAQkEMSIEIHYLb+fWyVe5FJ8eX812WAXEK7ta
# 5cmKMqFDAbDCmESAMA0GCSqGSIb3DQEBAQUABIIBALTPN49AM5ofE3CDcGLulY09
# GGx9mhC4APUzHUS/038mcPK2R5OEAbzVl7HKcSc3zo3bcfB2IJB0jMG8czGNtHgN
# w3BJpPiTiYErrr/9K7FrYSj5hN15ZtNwr98s69bt3b016Ef5Zii0D8ErMUwk+02b
# tmYF2W9V2RmRdq1v1kWUIutvGv660QCrTHF4mCZpeyV0sokjoEWDNQrf7Qp/5u1i
# MgCScxUu/M1LGQiqJQXZQZcbWeIzuKGaUW09n83Bc37os0BqmlF3IVRQSCJY5m3q
# hpGoQcYAbPn6u+ykResrscoRQp2vgR9Zy4TADDfPlfUYSmt190/FtC3Uf9aoPqg=
# SIG # End signature block
