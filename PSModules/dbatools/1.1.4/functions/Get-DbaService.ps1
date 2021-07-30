function Get-DbaService {
    <#
    .SYNOPSIS
        Gets the SQL Server related services on a computer.

    .DESCRIPTION
        Gets the SQL Server related services on one or more computers.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER InstanceName
        Only returns services that belong to the specific instances.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Type
        Use -Type to collect only services of the desired SqlServiceType.
        Can be one of the following: "Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "PolyBase", "Launchpad"

    .PARAMETER ServiceName
        Can be used to specify service names explicitly, without looking for service types/instances.

    .PARAMETER AdvancedProperties
        Collect additional properties from the SqlServiceAdvancedProperty Namespace
        This collects information about Version, Service Pack Level", SkuName, Clustered status and the Cluster Service Name
        This adds additional overhead to the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Service, SqlServer, Instance, Connect
        Author: Klaas Vandenberghe ( @PowerDBAKlaas )

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaService

    .EXAMPLE
        PS C:\> Get-DbaService -ComputerName sqlserver2014a

        Gets the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Get-DbaService -AdvancedProperties

        Gets the SQL Server related services on computers sql1, sql2 and sql3. Includes Advanced Properties from the SqlServiceAdvancedProperty Namespace

    .EXAMPLE
        PS C:\> $cred = Get-Credential WindowsUser
        PS C:\> Get-DbaService -ComputerName sql1,sql2 -Credential $cred  | Out-GridView

        Gets the SQL Server related services on computers sql1 and sql2 via the user WindowsUser, and shows them in a grid view.

    .EXAMPLE
        PS C:\> Get-DbaService -ComputerName sql1,sql2 -InstanceName MSSQLSERVER

        Gets the SQL Server related services related to the default instance MSSQLSERVER on computers sql1 and sql2.

    .EXAMPLE
        PS C:\> Get-DbaService -ComputerName $MyServers -Type SSRS

        Gets the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

    .EXAMPLE
        PS C:\> $MyServers =  Get-Content .\servers.txt
        PS C:\> Get-DbaService -ComputerName $MyServers -ServiceName MSSQLSERVER,SQLSERVERAGENT

        Gets the SQL Server related services with ServiceName MSSQLSERVER or SQLSERVERAGENT  for all the servers that are stored in the file. Every line in the file can only contain one hostname for a server.

    .EXAMPLE
        PS C:\> $services = Get-DbaService -ComputerName sql1 -Type Agent,Engine
        PS C:\> $services.ChangeStartMode('Manual')

        Gets the SQL Server related services of types Sql Agent and DB Engine on computer sql1 and changes their startup mode to 'Manual'.

    .EXAMPLE
        PS C:\> (Get-DbaService -ComputerName sql1 -Type Engine).Restart($true)

        Calls a Restart method for each Engine service on computer sql1.

    #>
    [CmdletBinding(DefaultParameterSetName = "Search")]
    param (
        [parameter(ValueFromPipeline, Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(ParameterSetName = "Search")]
        [Alias("Instance")]
        [string[]]$InstanceName,
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = "Search")]
        [ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "PolyBase", "Launchpad")]
        [string[]]$Type,
        [Parameter(ParameterSetName = "ServiceName")]
        [string[]]$ServiceName,
        [switch]$AdvancedProperties,
        [switch]$EnableException
    )

    begin {
        #Dictionary to transform service type IDs into the names from Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer.Services.Type
        $ServiceIdMap = @(
            @{ Name = "Engine"; Id = 1 },
            @{ Name = "Agent"; Id = 2 },
            @{ Name = "FullText"; Id = 3, 9 },
            @{ Name = "SSIS"; Id = 4 },
            @{ Name = "SSAS"; Id = 5 },
            @{ Name = "SSRS"; Id = 6 },
            @{ Name = "Browser"; Id = 7 },
            @{ Name = "PolyBase"; Id = 10, 11 },
            @{ Name = "Launchpad"; Id = 12 },
            @{ Name = "Unknown"; Id = 8 }
        )
        if ($PsCmdlet.ParameterSetName -match 'Search') {
            if ($Type) {
                $searchClause = ""
                foreach ($itemType in $Type) {
                    foreach ($id in ($ServiceIdMap | Where-Object { $_.Name -eq $itemType }).Id) {
                        if ($searchClause) { $searchClause += ' OR ' }
                        $searchClause += "SQLServiceType = $id"
                    }
                }
            } else {
                $searchClause = "SQLServiceType > 0"
            }
        } elseif ($PsCmdlet.ParameterSetName -match 'ServiceName') {
            if ($ServiceName) {
                $searchClause = ""
                foreach ($sn in $ServiceName) {
                    if ($searchClause) { $searchClause += ' OR ' }
                    $searchClause += "ServiceName = '$sn'"
                }
            } else {
                $searchClause = "SQLServiceType > 0"
            }
        }
    }
    process {
        foreach ($computer in $ComputerName.ComputerName) {
            try {
                $resolvedComputerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential -EnableException).FullComputerName
                $null = Get-DbaCmObject -ComputerName $resolvedComputerName -Namespace root\Microsoft -ClassName __NAMESPACE -EnableException
            } catch {
                Stop-Function -Message "Failed to resolve or to connect to $computer." -Target $computer -Category ConnectionError -ErrorRecord $_ -Continue
            }

            $namespaces = @( )
            $services = @()
            $outputServices = @()

            if (!$Type -or 'SSRS' -in $Type) {
                Write-Message -Level Verbose -Message "Getting SQL Reporting Server services on $computer" -Target $computer
                $reportingServices = Get-DbaReportingService -ComputerName $resolvedComputerName -InstanceName $InstanceName -Credential $Credential -ServiceName $ServiceName
                $outputServices += $reportingServices
            }

            Write-Message -Level Verbose -Message "Getting SQL Server namespaces on $computer" -Target $computer
            try {
                $namespaces = Get-DbaCmObject -ComputerName $resolvedComputerName -Credential $Credential -Namespace root\Microsoft\SQLServer -Query "Select Name FROM __NAMESPACE WHERE Name Like 'ComputerManagement%'" -EnableException | Sort-Object Name -Descending
                Write-Message -Level Verbose -Message "The following namespaces have been found: $($namespaces.Name -join ', ')."
            } catch {
                Write-Message -Level Verbose -Message "No namespaces found in relevant namespace on $computer."
            }

            foreach ($namespace in $namespaces) {
                try {
                    Write-Message -Level Verbose -Message "Getting Cim class SqlService in Namespace $($namespace.Name) on $computer." -Target $computer
                    foreach ($service in (Get-DbaCmObject -ComputerName $resolvedComputerName -Credential $Credential -Namespace "root\Microsoft\SQLServer\$($namespace.Name)" -Query "SELECT * FROM SqlService WHERE $searchClause" -EnableException)) {
                        Write-Message -Level Verbose -Message "Found service $($service.ServiceName) in namespace $($namespace.Name)."
                        $services += $service
                    }
                    # Use highest namespace available, so break if services have been found
                    break
                } catch {
                    Write-Message -Level Verbose -Message "Failed to acquire services from namespace $($namespace.Name)." -Target $Computer -ErrorRecord $_
                }
            }

            # Remove services returned by the SSRS namespace
            $services = $services | Where-Object ServiceName -notin $reportingServices.ServiceName

            # Add custom properties and methods to the service objects
            foreach ($service in $services) {
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ComputerName -Value $service.HostName
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ServiceType -Value ($ServiceIdMap | Where-Object { $_.Id -contains $service.SQLServiceType }).Name
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name State -Value $(switch ($service.State) { 1 { 'Stopped' } 2 { 'Start Pending' }  3 { 'Stop Pending' } 4 { 'Running' } })
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name StartMode -Value $(switch ($service.StartMode) { 1 { 'Unknown' } 2 { 'Automatic' }  3 { 'Manual' } 4 { 'Disabled' } })

                if ($service.ServiceName -in ("MSSQLSERVER", "SQLSERVERAGENT", "ReportServer", "MSSQLServerOLAPService", "MSSQLFDLauncher", "SQLPBDMS", "SQLPBENGINE", "MSSQLLAUNCHPAD")) {
                    $instance = "MSSQLSERVER"
                } else {
                    if ($service.ServiceType -in @("Agent", "Engine", "SSRS", "SSAS", "FullText", "PolyBase", "Launchpad")) {
                        if ($service.ServiceName.indexof('$') -ge 0) {
                            $instance = $service.ServiceName.split('$')[1]
                        } else {
                            $instance = "Unknown"
                        }
                    } else {
                        $instance = ""
                    }
                }
                $priority = switch ($service.ServiceType) {
                    "Engine" { 200 }
                    default { 100 }
                }
                #If only specific instances are selected
                if (!$InstanceName -or $instance -in $InstanceName) {
                    #Add other properties and methods
                    Add-Member -Force -InputObject $service -NotePropertyName InstanceName -NotePropertyValue $instance
                    Add-Member -Force -InputObject $service -NotePropertyName ServicePriority -NotePropertyValue $priority
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Stop" -Value {
                        param ([bool]$Force = $false)
                        Stop-DbaService -InputObject $this -Force:$Force
                    }
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Start" -Value { Start-DbaService -InputObject $this }
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Restart" -Value {
                        param ([bool]$Force = $false)
                        Restart-DbaService -InputObject $this -Force:$Force
                    }
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "ChangeStartMode" -Value {
                        param (
                            [parameter(Mandatory)]
                            [string]$Mode
                        )
                        $supportedModes = @("Automatic", "Manual", "Disabled")
                        if ($Mode -notin $supportedModes) {
                            Stop-Function -Message ("Incorrect mode '$Mode'. Use one of the following values: {0}" -f ($supportedModes -join ' | ')) -EnableException $false -FunctionName 'Get-DbaService'
                            Return
                        }
                        Set-ServiceStartMode -InputObject $this -Mode $Mode -ErrorAction Stop
                        $this.StartMode = $Mode
                    }

                    if ($AdvancedProperties) {
                        $namespaceValue = $service.CimClass.ToString().ToUpper().Replace(":SQLSERVICE", "").Replace("ROOT/MICROSOFT/SQLSERVER/", "")
                        $serviceAdvancedProperties = Get-DbaCmObject -ComputerName $Computer -Namespace "root\Microsoft\SQLServer\$($namespaceValue)" -Query "SELECT * FROM SqlServiceAdvancedProperty WHERE ServiceName = '$($service.ServiceName)'"

                        Add-Member -Force -InputObject $service -MemberType NoteProperty -Name Version -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'VERSION' ).PropertyStrValue
                        Add-Member -Force -InputObject $service -MemberType NoteProperty -Name SPLevel -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'SPLEVEL' ).PropertyNumValue
                        Add-Member -Force -InputObject $service -MemberType NoteProperty -Name SkuName -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'SKUNAME' ).PropertyStrValue

                        $ClusterServiceTypeList = @(1, 2, 5, 7)
                        if ($ClusterServiceTypeList -contains $service.SQLServiceType) {
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name Clustered -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'CLUSTERED' ).PropertyNumValue
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name VSName -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'VSNAME' ).PropertyStrValue
                        } else {
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name Clustered -Value ''
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name VSName -Value ''
                        }
                    }
                    $outputServices += $service
                }
            }
            if ($AdvancedProperties) {
                $defaults = "ComputerName", "ServiceName", "ServiceType", "InstanceName", "DisplayName", "StartName", "State", "StartMode", "Version", "SPLevel", "SkuName", "Clustered", "VSName"
            } else {
                $defaults = "ComputerName", "ServiceName", "ServiceType", "InstanceName", "DisplayName", "StartName", "State", "StartMode"
            }
            if ($outputServices) {
                $outputServices | Select-DefaultView -Property $defaults -TypeName DbaSqlService
            } else {
                Write-Message -Level Verbose -Message "No services found in relevant namespaces on $computer."
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUV7FN+pqDiSzimq+prTR9PlKx
# 3AugghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFO8XU8YiLDUslXwjOTTKr9Zg6CxlMA0GCSqGSIb3DQEBAQUABIIBAEpjn3ZC
# jMHEp0yqqzZUDLsi5noG5OOtjQB4awxgzV9HvyBWAXJJP89GZEI33qEHXvPGkaVa
# fEVmnJUdOen3yp4XdfyGwQBx6xy4S+0xdUBbQriF96aWUfW3LD7bC+t7dohpgkPU
# jGCMl+L/FsENTONZRkNjQ+NsCf4M5UQCAwivfFYnLuY9sCzmi4OE87TXE0y5XyVC
# Ch6kkCnDUGhH3W3fFVWAtdxP9kH9zpx3KACnuJBIejW5oqYBCpvCpB6zMCMJp4Ux
# XthZMQbDqV7gHpHpQHCOwfaKHo8meP1Wr6zEn8imvqY4rKSRrDvTAq0qlqcQUU+a
# 9ZM3f0aWxOVP1GShggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk0M1owLwYJKoZIhvcNAQkEMSIEIBbgxbutf+2QqLIpnm4C0/q/VphB
# Fa7QN30trJ20J0Y2MA0GCSqGSIb3DQEBAQUABIIBADT3bnbdXSXJaKNWd7cR+Umm
# KsMqEXeAoVme1CYi+gTm+VtU7cCSxC7OmDqjzIfcC9SoV1VDYf9fh0CQ14W6jhc8
# T6f0kpW/e/55tfQ0PzfWgZ6pd3krtotbZy/3gpuWxzTuiKrBryzU2OQNg0PkE/7C
# H+gtUzXXAaZn+dgFlk3TDfcZUYfaEauI9PJZeoMMek4ow4cQBQDZ32877Ae7vPf/
# qUMFvxaZ/DctWW2NbpqjKru3ni4hLfeMdSqXMyCFZ3Fer/9CoP1RdPiggXJyV35q
# 8RFqT8GAiFKHtreUj8E3yUIh+LNSIHVsLLTmTCCpIpF5v4KIRgtGSWJ4eJ8q/yY=
# SIG # End signature block
