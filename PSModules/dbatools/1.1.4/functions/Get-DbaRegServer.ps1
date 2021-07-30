function Get-DbaRegServer {
    <#
    .SYNOPSIS
        Gets list of SQL Server objects stored in local registered groups, azure data studio and central management server.

    .DESCRIPTION
       Gets list of SQL Server objects stored in local registered groups, azure data studio and central management server.

       Local Registered Servers and Azure Data Studio support alternative authentication (excluding MFA) but Central Management Studio does not.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies one or more names to include. Name is the visible name in SSMS interface (labeled Registered Server Name)

    .PARAMETER ServerName
        Specifies one or more server names to include. Server Name is the actual instance name (labeled Server Name)

    .PARAMETER Group
        Specifies one or more groups to include from SQL Server Central Management Server.

    .PARAMETER ExcludeGroup
        Specifies one or more Central Management Server groups to exclude.

    .PARAMETER IncludeLocal
        Include local registered servers or Azure Data Studio registered servers in results when specifying SqlInstance.

    .PARAMETER Id
        Get server by Id(s)

    .PARAMETER IncludeSelf
        If this switch is enabled and you're connecting to a Central Management Server, the CMS server itself will be included in the results, along with all other Registered Servers.

    .PARAMETER ResolveNetworkName
        If this switch is enabled, the NetBIOS name and IP address(es) of each server will be returned.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: RegisteredServer, CMS
        Author: Bryan Hamby (@galador) | Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRegServer

    .EXAMPLE
        PS C:\> Get-DbaRegServer

        Gets a list of servers from the local registered servers and azure data studio

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a

        Gets a list of servers from the CMS on sqlserver2014a, using Windows Credentials.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -IncludeSelf

        Gets a list of servers from the CMS on sqlserver2014a and includes sqlserver2014a in the output results.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -SqlCredential $credential | Select-Object -Unique -ExpandProperty ServerName

        Returns only the server names from the CMS on sqlserver2014a, using SQL Authentication to authenticate to the server.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -Group HR, Accounting

        Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -Group HR\Development

        Returns a list of servers in the HR and sub-group Development from the CMS on sqlserver2014a.

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance = (Get-DbatoolsConfigValue -FullName 'commands.get-dbaregserver.defaultcms'),
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$ServerName,
        [string[]]$Group,
        [string[]]$ExcludeGroup,
        [int[]]$Id,
        [switch]$IncludeSelf,
        [switch]$ResolveNetworkName,
        [switch]$IncludeLocal = (Get-DbatoolsConfigValue -FullName 'commands.get-dbaregserver.includelocal'),
        [switch]$EnableException
    )
    begin {
        if ($ResolveNetworkName) {
            $defaults = 'ComputerName', 'FQDN', 'IPAddress', 'Name', 'ServerName', 'Group', 'Description', 'Source'
        }
        $defaults = 'Name', 'ServerName', 'Group', 'Description', 'Source'
        # thank you forever https://social.msdn.microsoft.com/Forums/sqlserver/en-US/57811d43-a2b9-4179-a97b-a9936ddb188e/how-to-retrieve-a-password-saved-by-sql-server?forum=sqltools
        function Unprotect-String([string] $base64String) {
            return [System.Text.Encoding]::Unicode.GetString([System.Security.Cryptography.ProtectedData]::Unprotect([System.Convert]::FromBase64String($base64String), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser))
        }
    }
    process {
        if (-not $PSBoundParameters.SqlInstance -and -not ($IsLinux -or $IsMacOs)) {
            $null = Get-ChildItem -Recurse "$(Get-DbatoolsPath -Name appdata)\Microsoft\*sql*" -Filter RegSrvr.xml | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }

        $servers = @()
        $serverToServerStore = @{ }
        foreach ($instance in $SqlInstance) {

            try {
                $serverstore = Get-DbaRegServerStore -SqlInstance $instance -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "Cannot access Central Management Server '$instance'." -ErrorRecord $_ -Continue
            }

            if ($Group) {
                $groupservers = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group -ExcludeGroup $ExcludeGroup
                if ($groupservers) {
                    $servers += $groupservers.GetDescendantRegisteredServers()
                }
            } else {
                $servers += ($serverstore.DatabaseEngineServerGroup.GetDescendantRegisteredServers())
                $serverstore.ServerConnection.Disconnect()
            }

            # save the $serverstore for later usage
            foreach ($server in $servers) {
                $serverToServerStore[$server] = $serverstore
            }
        }

        # Magic courtesy of Mathias Jessen and David Shifflet
        if (-not $PSBoundParameters.SqlInstance -or $PSBoundParameters.IncludeLocal) {
            $file = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]::LocalFileStore.DomainInstanceName
            if ($file) {
                if ((Test-Path -Path $file)) {
                    $class = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]
                    $initMethod = $class.GetMethod('InitChildObjects', [Reflection.BindingFlags]'Static,NonPublic')
                    $store = ($initMethod.Invoke($null, @($file)))
                    # Local Reg Servers
                    foreach ($tempserver in $store.DatabaseEngineServerGroup.GetDescendantRegisteredServers()) {
                        $servers += $tempserver | Add-Member -Force -Name Source -Value "Local Server Groups" -MemberType NoteProperty -PassThru
                    }
                    # Azure Reg Servers
                    $azureids = @()
                    if ($store.AzureDataStudioConnectionStore.Groups) {
                        $adsconnection = Get-ADSConnection
                    }
                    foreach ($azuregroup in $store.AzureDataStudioConnectionStore.Groups) {
                        $groupname = $azuregroup.Name
                        if ($groupname -eq 'ROOT' -or $groupname -eq '') {
                            $groupname = $null
                        }
                        $tempgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup $groupname
                        $tempgroup.Description = $azuregroup.Description

                        foreach ($server in ($store.AzureDataStudioConnectionStore.Connections | Where-Object GroupId -eq $azuregroup.Id)) {
                            $azureids += [pscustomobject]@{ id = $server.Id; group = $groupname }
                            $connname = $server.Options['connectionName']
                            if (-not $connname) {
                                $connname = $server.Options['server']
                            }
                            $adsconn = $adsconnection | Where-Object { $_.server -eq $server.Options['server'] -and -not $_.database }

                            $tempserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer $tempgroup, $connname
                            $tempserver.Description = $server.Options['Description']
                            if ($adsconn.ConnectionString) {
                                $tempserver.ConnectionString = $adsconn.ConnectionString
                            }
                            # update read-only or problematic properties
                            $tempserver | Add-Member -Force -Name Source -Value "Azure Data Studio" -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name ServerName -Value $server.Options['server'] -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name Id -Value $server.Id -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name CredentialPersistenceType -Value 1 -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name ServerType -Value DatabaseEngine -MemberType NoteProperty
                            $servers += $tempserver
                        }
                    }
                }
            }
        }

        if ($Name) {
            Write-Message -Level Verbose -Message "Filtering by name for $name"
            $servers = $servers | Where-Object Name -in $Name
        }

        if ($ServerName) {
            Write-Message -Level Verbose -Message "Filtering by servername for $servername"
            $servers = $servers | Where-Object ServerName -in $ServerName
        }

        if ($Id) {
            Write-Message -Level Verbose -Message "Filtering by id for $Id (1 = default/root)"
            $servers = $servers | Where-Object Id -in $Id
        }

        foreach ($server in $servers) {
            $az = $azureids | Where-Object Id -in $server.Id
            if ($az) {
                $groupname = $az.Group
            } else {
                $groupname = Get-RegServerGroupReverseParse $server
                if ($groupname -eq $server.Name) {
                    $groupname = $null
                } else {
                    $groupname = ($groupname).Split("\")
                    $groupname = $groupname[0 .. ($groupname.Count - 2)]
                    $groupname = ($groupname -join "\")
                }
            }
            # ugly way around it but it works
            $badform = "$($server.Name.Split("\")[0])\$($server.Name.Split("\")[0])"
            if ($groupname -eq $badform) {
                $groupname = $null
            }

            if ($ExcludeGroup -and ($groupname -in $ExcludeGroup)) {
                continue
            }

            if ($server.ConnectionStringWithEncryptedPassword) {
                $encodedconnstring = $connstring = $server.ConnectionStringWithEncryptedPassword
                if ($encodedconnstring -imatch 'password="?([^";]+)"?') {
                    $password = $Matches[1]
                    $password = Unprotect-String $password
                    $connstring = $encodedconnstring -ireplace 'password="?([^";]+)"?', "password=`"$password`""
                    Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ConnectionString -Value $connstring
                    Add-Member -Force -InputObject $server -MemberType NoteProperty -Name SecureConnectionString -Value (ConvertTo-SecureString -String $connstring -AsPlainText -Force)
                }
            }

            if (-not $server.Source) {
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name Source -value "Central Management Servers"
            }

            if ( $null -ne $serverToServerStore[$server] ) {
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -value $serverToServerStore[$server].ComputerName
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name InstanceName -value $serverToServerStore[$server].InstanceName
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name SqlInstance -value $serverToServerStore[$server].SqlInstance
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ParentServer -Value $serverToServerStore[$server].ParentServer
            }

            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name Group -value $groupname
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name FQDN -Value $null
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $null

            if ($ResolveNetworkName) {
                try {
                    $lookup = Resolve-DbaNetworkName $server.ServerName -Turbo
                    $server.ComputerName = $lookup.ComputerName
                    $server.FQDN = $lookup.FQDN
                    $server.IPAddress = $lookup.IPAddress
                } catch {
                    try {
                        $lookup = Resolve-DbaNetworkName $server.ServerName
                        $server.ComputerName = $lookup.ComputerName
                        $server.FQDN = $lookup.FQDN
                        $server.IPAddress = $lookup.IPAddress
                    } catch {
                        # here to avoid an empty catch
                        $null = 1
                    }
                }
            }

            # this is a bit dirty and should be addressed by someone who better knows recursion and regex
            if ($server.Source -ne "Central Management Servers") {
                if ($PSBoundParameters.Group -and $groupname -notin $PSBoundParameters.Group) { continue }
                if ($PSBoundParameters.ExcludeGroup -and $groupname -in $PSBoundParameters.ExcludeGroup) { continue }
            }

            Add-Member -Force -InputObject $server -MemberType ScriptMethod -Name ToString -Value { $this.ServerName }
            Select-DefaultView -InputObject $server -Property $defaults
        }

        if ($IncludeSelf -and $servers) {
            Write-Message -Level Verbose -Message "Adding CMS instance"
            $self = $servers[0].PsObject.Copy() | Select-Object -Property $defaults
            $self | Add-Member -MemberType NoteProperty -Name Name -Value "CMS Instance" -Force
            $self.ServerName = $instance
            $self.Group = $null
            $self.Description = $null
            Select-DefaultView -InputObject $self -Property $defaults
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUY+mVm2yVIoEp3sOGCIlGh58w
# +NqgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFLKdX+0oOyJB8gEXRMKTryfCVA51MA0GCSqGSIb3DQEBAQUABIIBAF3vLIUz
# wlES3QfT8BMMoHsiQ5mwCuyldNTwMsdQork1K8TJk9aIlixn5t2MaSwY/zPsPsJc
# L3zFyPd86pOaov3F+ykGkRPg/V+i6qRFE9hxcEZJLt/03fRSfNPUaPd1frFxJdzJ
# Eer4sfB7C+UbPVYPGiy3bprTBjEgHE4MSQ4Nb58ZHpfBb2Z5yuQwYxWY6Ur6AqOP
# tboHUhWy1ll+0f9nXspF/Ro2zF9RXNQPJWYvq3Dt2NJ4IOqUOBngNAu/16dQ7CSO
# bi6dQH6ttDmQLd1Yc7m9oUlB+wAt1M0hPLkpSyCKwtg12jfsV88VeGxiDGitDnoa
# fwYWBKNcUuejTi2hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk0MlowLwYJKoZIhvcNAQkEMSIEIAdqArxoFE/8uivvGGWHFs+JRVt0
# uLR/CQR18Bnr27ZzMA0GCSqGSIb3DQEBAQUABIIBAGpvU7z/yhVuc5RElsR5MsDO
# +xipe7EoNZ6TlwVQ9dAYY4NuHCDwitjaNM8M1YgnPTXntErpNvCmBU5jcYBIA/fi
# 9FMx66Lui0x0ec5gdxbC+Eo8rVjJwzpNYzo4TeDTfYJY3rUx1wX7Gh2HgV/5812I
# VIkuBhYPjM7BiUO+y0qo7q8xa+y2b3sYzzXkyQU5UPtbeNGT2jc058IqFd32C+vL
# FI16V0eHOF1nZWEf2tgQwJtDHgtkCqYtzuSkrgPH04pmykEIDjkDkgPW1Y89hMTY
# P7Bffvrn7KydpeQ9zYmbfGGkkPs0THP/GzuoD241LWqJ10PB+Ca6Tkm6ozFqjtM=
# SIG # End signature block
